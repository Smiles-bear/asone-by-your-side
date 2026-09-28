import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../import_models.dart';
import '../import_source_error.dart';
import 'parser_models.dart';
import 'record_parser.dart';

typedef RikkaHubWorkspaceFactory = Future<Directory> Function();

class RikkaHubBackupReader {
  RikkaHubBackupReader({
    DatabaseFactory? databaseFactoryOverride,
    RikkaHubWorkspaceFactory? workspaceFactory,
    this.checkCancelled,
  }) : _databaseFactoryOverride = databaseFactoryOverride,
       _workspaceFactory = workspaceFactory ?? _createWorkspace;

  static const _requiredEntries = {
    'rikka_hub.db',
    'rikka_hub-wal',
    'rikka_hub-shm',
    'settings.json',
  };
  static const _databaseEntries = {
    'rikka_hub.db',
    'rikka_hub-wal',
    'rikka_hub-shm',
  };

  final DatabaseFactory? _databaseFactoryOverride;
  final RikkaHubWorkspaceFactory _workspaceFactory;
  final void Function()? checkCancelled;

  Future<ParsedImport?> parseIfRecognized({
    required Map<String, Uint8List> entries,
    required String sourceName,
  }) async {
    final byBaseName = <String, Uint8List>{};
    for (final entry in entries.entries) {
      final normalized = entry.key.replaceAll('\\', '/');
      final baseName = normalized.split('/').last;
      if (_requiredEntries.contains(baseName)) {
        if (byBaseName.containsKey(baseName)) {
          return _failure(sourceName, 'RikkaHub 备份包含重复数据库文件，请重新导出完整备份');
        }
        byBaseName[baseName] = entry.value;
      }
    }
    if (!byBaseName.keys.any(_databaseEntries.contains)) return null;
    if (!_requiredEntries.every(byBaseName.containsKey)) {
      return _failure(sourceName, 'RikkaHub 备份不完整，请保留数据库及 WAL、SHM 文件后重新导出');
    }

    Directory? workspace;
    Database? db;
    try {
      checkCancelled?.call();
      workspace = await _workspaceFactory();
      final dbPath = '${workspace.path}${Platform.pathSeparator}rikka_hub.db';
      await File(dbPath).writeAsBytes(byBaseName['rikka_hub.db']!, flush: true);
      await File(
        '$dbPath-wal',
      ).writeAsBytes(byBaseName['rikka_hub-wal']!, flush: true);
      await File(
        '$dbPath-shm',
      ).writeAsBytes(byBaseName['rikka_hub-shm']!, flush: true);
      checkCancelled?.call();
      final factory = _databaseFactoryOverride ?? databaseFactory;
      db = await factory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      return await _readDatabase(db, sourceName);
    } on FileSystemException {
      rethrow;
    } on ImportSourceException catch (error) {
      return _failure(sourceName, error.message);
    } on DatabaseException {
      return _failure(sourceName, 'RikkaHub 备份数据库无法读取，请重新导出完整备份');
    } on FormatException {
      return _failure(sourceName, 'RikkaHub 聊天结构不完整，请重新导出完整备份');
    } on Object {
      return _failure(sourceName, 'RikkaHub 备份无法安全解析，请重新导出后再试');
    } finally {
      try {
        await db?.close();
      } finally {
        if (workspace != null) await _deleteWorkspace(workspace);
      }
    }
  }

  Future<ParsedImport> _readDatabase(Database db, String sourceName) async {
    final conversations = <SourceConversation>[];
    final counts = _RikkaHubImportCounts();
    final conversationRows = await db.query(
      'ConversationEntity',
      columns: ['id', 'title', 'create_at'],
      orderBy: 'create_at ASC, id ASC',
    );
    if (conversationRows.isEmpty) {
      throw const ImportSourceException('RikkaHub 备份中没有聊天记录');
    }
    for (
      var conversationIndex = 0;
      conversationIndex < conversationRows.length;
      conversationIndex++
    ) {
      checkCancelled?.call();
      final row = conversationRows[conversationIndex];
      final conversationId = _requiredString(row['id']);
      final rawTitle = row['title'];
      final title = rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'RikkaHub 会话 ${conversationIndex + 1}';
      final messages = await _readConversationMessages(
        db,
        conversationId,
        counts,
      );
      if (messages.isNotEmpty) {
        conversations.add(
          SourceConversation(
            id: 'rikkahub:$conversationId',
            title: title,
            messages: messages,
          ),
        );
      }
    }
    if (conversations.isEmpty) {
      throw const ImportSourceException('RikkaHub 备份中没有可导入的可见聊天正文');
    }
    return ParsedImport(
      bundle: ImportBundle(
        schemaVersion: importSchemaVersion,
        conversations: conversations,
      ),
      parserId: 'zip-safe-container',
      parserVersion: '2.1.0',
      containerFormat: 'rikkahub-backup',
      confidence: 1,
      capabilities: const {
        'rikkahub_database',
        'selected_reply_only',
        'visible_text_only',
        'configuration_excluded',
      },
      warnings: counts.warnings,
      imageCount: counts.imageParts,
      fileCount: counts.documentParts,
      sourceName: sourceName,
    );
  }

  Future<List<SourceMessage>> _readConversationMessages(
    Database db,
    String conversationId,
    _RikkaHubImportCounts counts,
  ) async {
    final messages = <SourceMessage>[];
    final selectedIds = <String>{};
    int? previousNodeIndex;
    var offset = 0;
    while (true) {
      checkCancelled?.call();
      final nodeRows = await db.query(
        'message_node',
        columns: ['node_index', 'messages', 'select_index'],
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'node_index ASC',
        limit: 100,
        offset: offset,
      );
      if (nodeRows.isEmpty) break;
      for (final node in nodeRows) {
        final nodeIndex = node['node_index'];
        if (nodeIndex is! int ||
            previousNodeIndex != null && nodeIndex <= previousNodeIndex) {
          throw const ImportSourceException('RikkaHub 消息顺序不完整，请重新导出完整备份');
        }
        previousNodeIndex = nodeIndex;
        final selected = _selectedVariant(node, counts);
        final message = _messageFromVariant(
          selected,
          selectedIds,
          counts,
          messages.length,
        );
        if (message != null) messages.add(message);
      }
      offset += nodeRows.length;
    }
    return messages;
  }

  Map _selectedVariant(
    Map<String, Object?> node,
    _RikkaHubImportCounts counts,
  ) {
    final rawMessages = node['messages'];
    final selectedIndex = node['select_index'];
    if (rawMessages is! String || selectedIndex is! int) {
      throw const ImportSourceException('RikkaHub 消息节点不完整，请重新导出完整备份');
    }
    final variants = jsonDecode(rawMessages);
    if (variants is! List ||
        variants.isEmpty ||
        selectedIndex < 0 ||
        selectedIndex >= variants.length) {
      throw const ImportSourceException('RikkaHub 当前回复索引无效，请在原应用重新导出');
    }
    counts.alternateReplies += variants.length - 1;
    final selected = variants[selectedIndex];
    if (selected is! Map) {
      throw const ImportSourceException('RikkaHub 当前回复结构无效，请重新导出');
    }
    return selected;
  }

  SourceMessage? _messageFromVariant(
    Map selected,
    Set<String> selectedIds,
    _RikkaHubImportCounts counts,
    int sequence,
  ) {
    final messageId = _requiredString(selected['id']);
    if (!selectedIds.add(messageId)) {
      throw const ImportSourceException('RikkaHub 聊天包含重复消息标识，请重新导出');
    }
    final role = selected['role'];
    if (role is! String ||
        !const {'user', 'assistant', 'system'}.contains(role)) {
      throw const ImportSourceException('RikkaHub 消息角色无法安全识别，请重新导出');
    }
    final parts = selected['parts'];
    if (parts is! List) {
      throw const ImportSourceException('RikkaHub 消息正文结构无效，请重新导出');
    }
    final content = _visibleContent(parts, counts);
    if (content.isEmpty) {
      counts.emptyVisibleMessages++;
      return null;
    }
    final timestamp = parseTimestamp(selected['createdAt']);
    if (timestamp.value == null) {
      throw const ImportSourceException('RikkaHub 消息时间无效，请重新导出完整备份');
    }
    return SourceMessage(
      id: messageId,
      sequence: sequence,
      role: role,
      content: content,
      createdAt: timestamp.value,
      timestampStatus: timestamp.status,
      sourceRole: role,
      roleStatus: 'explicit',
    );
  }

  String _visibleContent(List parts, _RikkaHubImportCounts counts) {
    final visibleText = <String>[];
    for (final rawPart in parts) {
      if (rawPart is! Map || rawPart['type'] is! String) {
        throw const ImportSourceException('RikkaHub 消息片段结构无效，请重新导出');
      }
      switch (rawPart['type']) {
        case 'text':
          final text = rawPart['text'];
          if (text is! String) {
            throw const ImportSourceException('RikkaHub 文本片段无效，请重新导出');
          }
          if (text.isNotEmpty) visibleText.add(text);
          break;
        case 'reasoning':
          counts.reasoningParts++;
          break;
        case 'tool':
          counts.toolParts++;
          break;
        case 'image':
          counts.imageParts++;
          break;
        case 'document':
          counts.documentParts++;
          break;
        default:
          throw const ImportSourceException('RikkaHub 包含未知消息片段，请更新软件后再试');
      }
    }
    return visibleText.join('\n').trim();
  }

  ParsedImport _failure(String sourceName, String message) => ParsedImport(
    bundle: const ImportBundle(
      schemaVersion: importSchemaVersion,
      conversations: [],
    ),
    parserId: 'zip-safe-container',
    parserVersion: '2.1.0',
    containerFormat: 'rikkahub-backup',
    confidence: 1,
    capabilities: const {'rikkahub_database'},
    errors: [message],
    boundariesSafe: false,
    sourceName: sourceName,
  );

  static String _requiredString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const ImportSourceException('RikkaHub 备份缺少稳定消息标识，请重新导出');
    }
    return value.trim();
  }

  static Future<Directory> _createWorkspace() =>
      Directory.systemTemp.createTemp('azruiyoi-rikkahub-import-');

  static Future<void> _deleteWorkspace(Directory directory) async {
    if (!await directory.exists()) return;
    final parent = directory.parent.absolute.path;
    final systemTemp = Directory.systemTemp.absolute.path;
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (parent != systemTemp || !name.startsWith('azruiyoi-rikkahub-import-')) {
      throw const FileSystemException('拒绝清理非本次创建的临时目录');
    }
    await directory.delete(recursive: true);
  }
}

class _RikkaHubImportCounts {
  int alternateReplies = 0;
  int reasoningParts = 0;
  int toolParts = 0;
  int imageParts = 0;
  int documentParts = 0;
  int emptyVisibleMessages = 0;

  List<String> get warnings => [
    if (alternateReplies > 0) '另有 $alternateReplies 条备选回复未导入',
    if (reasoningParts > 0 || toolParts > 0)
      '$reasoningParts 条思考片段和 $toolParts 条工具记录未作为聊天正文导入',
    if (imageParts > 0 || documentParts > 0)
      '${imageParts + documentParts} 个图片/文档引用未随备份恢复',
    if (emptyVisibleMessages > 0) '$emptyVisibleMessages 个无可见正文的内部节点未导入',
  ];
}
