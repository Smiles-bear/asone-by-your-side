import 'dart:convert';

import '../import_models.dart';
import 'import_parser.dart';
import 'parser_models.dart';
import 'record_parser.dart';
import 'text_decoder.dart';

class JsonImportParser implements ImportParser {
  const JsonImportParser();

  @override
  String get id => 'json-records';

  @override
  String get version => '2.0.0';

  @override
  Set<String> get capabilities => const {
    'roles',
    'timestamps',
    'multiple_conversations',
    'ordered_messages',
    'attachment_references',
  };

  @override
  ParserProbe probe(ImportFileSource source) {
    if (source.extension != 'json') return const ParserProbe(confidence: 0);
    try {
      final value = jsonDecode(decodeImportText(source.bytes).text);
      if (_hasExactShape(value)) {
        return const ParserProbe(confidence: 0.98, reason: '精确消息字段匹配');
      }
      return const ParserProbe(confidence: 0.35, reason: '仅容器匹配');
    } on Object {
      return const ParserProbe(confidence: 0.8, reason: 'JSON 扩展名');
    }
  }

  @override
  Future<ParsedImport> parse(
    ImportFileSource source, {
    required ImportParserLimits limits,
  }) async {
    if (source.bytes.length > limits.maxInputBytes) {
      return _failure(source, '文件超过 ${limits.maxInputBytes} bytes');
    }
    try {
      final decoded = decodeImportText(source.bytes);
      final root = jsonDecode(decoded.text);
      final rawConversations = _conversations(root);
      final conversations = <SourceConversation>[];
      final uncertain = <String>{};
      final warnings = [...decoded.warnings];
      final errors = <String>[];
      var imageCount = 0;
      var fileCount = 0;
      for (
        var conversationIndex = 0;
        conversationIndex < rawConversations.length;
        conversationIndex++
      ) {
        final rawConversation = rawConversations[conversationIndex];
        final rawMessages = rawConversation.messages;
        final messages = <SourceMessage>[];
        for (var index = 0; index < rawMessages.length; index++) {
          final value = rawMessages[index];
          if (value is! Map) {
            errors.add('会话 ${conversationIndex + 1} 第 ${index + 1} 条不是对象');
            continue;
          }
          final record = value.cast<String, Object?>();
          final content = record['content'];
          if (content is! String) {
            errors.add(
              '会话 ${conversationIndex + 1} 第 ${index + 1} 条缺少 content',
            );
            continue;
          }
          final role = parseRole(record['role']);
          final timestamp = parseTimestamp(
            record['created_at'] ?? record['timestamp'],
          );
          if (role.status == 'uncertain') uncertain.add(role.sourceRole);
          if (timestamp.warning != null) warnings.add(timestamp.warning!);
          final rawAttachments = record['attachments'];
          final attachments = <SourceAttachment>[];
          if (rawAttachments != null) {
            if (rawAttachments is! List) {
              errors.add(
                '会话 ${conversationIndex + 1} 第 ${index + 1} 条 attachments 不是数组',
              );
            } else {
              for (final rawAttachment in rawAttachments) {
                try {
                  attachments.add(
                    SourceAttachment.fromJson(
                      (rawAttachment as Map).cast<String, Object?>(),
                    ),
                  );
                  if (attachments.last.kind == 'image') {
                    imageCount++;
                  } else {
                    fileCount++;
                  }
                } on Object catch (error) {
                  errors.add(
                    '会话 ${conversationIndex + 1} 第 ${index + 1} 条附件无效: $error',
                  );
                }
              }
            }
          }
          final rawId = record['id'];
          messages.add(
            SourceMessage(
              id: rawId is String && rawId.isNotEmpty
                  ? rawId
                  : 'message-$index',
              sequence: index,
              role: role.role,
              content: content,
              createdAt: timestamp.value,
              timestampStatus: timestamp.status,
              sourceRole: role.sourceRole,
              roleStatus: role.status,
              hasStableSourceId: rawId is String && rawId.isNotEmpty,
              attachments: attachments,
            ),
          );
        }
        conversations.add(
          SourceConversation(
            id: rawConversation.id,
            title: rawConversation.title,
            messages: messages,
          ),
        );
      }
      if (conversations.isEmpty ||
          conversations.every(
            (conversation) => conversation.messages.isEmpty,
          )) {
        errors.add('文件为空或没有消息');
      }
      return ParsedImport(
        bundle: ImportBundle(
          schemaVersion: importSchemaVersion,
          conversations: conversations,
        ),
        parserId: id,
        parserVersion: version,
        containerFormat: 'json',
        confidence: 0.98,
        capabilities: capabilities,
        warnings: warnings,
        errors: errors,
        uncertainRoles: uncertain,
        imageCount: imageCount,
        fileCount: fileCount,
        boundariesSafe: errors.isEmpty,
        sourceName: source.name,
      );
    } on Object catch (error) {
      return _failure(source, 'JSON 损坏或结构不完整: $error');
    }
  }

  ParsedImport _failure(ImportFileSource source, String error) => ParsedImport(
    bundle: const ImportBundle(
      schemaVersion: importSchemaVersion,
      conversations: [],
    ),
    parserId: id,
    parserVersion: version,
    containerFormat: 'json',
    confidence: 0.8,
    capabilities: capabilities,
    errors: [error],
    boundariesSafe: false,
    sourceName: source.name,
  );
}

bool _hasExactShape(Object? value) {
  final List messages;
  if (value is List) {
    messages = value;
  } else if (value is Map && value['messages'] is List) {
    messages = value['messages']! as List;
  } else if (value is Map && value['conversations'] is List) {
    messages = (value['conversations']! as List)
        .whereType<Map>()
        .expand(
          (conversation) => (conversation['messages'] as List?) ?? const [],
        )
        .toList();
  } else {
    messages = const [];
  }
  return messages.isNotEmpty &&
      messages.every(
        (message) =>
            message is Map &&
            message['role'] is String &&
            message['content'] is String,
      );
}

List<_RawConversation> _conversations(Object? root) {
  if (root is List) {
    return [_RawConversation('conversation-0', '导入会话', root)];
  }
  if (root is! Map) throw const FormatException('JSON 根节点必须是对象或数组');
  if (root['messages'] is List) {
    return [
      _RawConversation(
        (root['id'] as String?) ?? 'conversation-0',
        (root['title'] as String?) ?? '导入会话',
        root['messages']! as List,
      ),
    ];
  }
  final values = root['conversations'];
  if (values is! List) throw const FormatException('缺少 messages/conversations');
  return List.generate(values.length, (index) {
    final value = values[index];
    if (value is! Map || value['messages'] is! List) {
      throw FormatException('第 ${index + 1} 个会话结构不完整');
    }
    return _RawConversation(
      (value['id'] as String?) ?? 'conversation-$index',
      (value['title'] as String?) ?? '导入会话 ${index + 1}',
      value['messages']! as List,
    );
  });
}

class _RawConversation {
  const _RawConversation(this.id, this.title, this.messages);

  final String id;
  final String title;
  final List messages;
}
