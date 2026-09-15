import 'package:asone_contracts/asone_contracts.dart';

import '../demo_ids.dart';

/// In-memory [MessageRepositoryApi] implementation.
class DemoMessageStore implements MessageRepositoryApi {
  DemoMessageStore({List<Map<String, dynamic>>? seed}) : _rows = [...?seed];

  final List<Map<String, dynamic>> _rows;

  List<Map<String, dynamic>> _sortedRowsOf(String conversationId) {
    final rows = _rows
        .where((row) => row['conversation_id'] == conversationId)
        .toList();
    rows.sort(
      (a, b) =>
          (a['created_at'] as String).compareTo(b['created_at'] as String),
    );
    return rows;
  }

  Map<String, dynamic>? _rowById(String id) {
    for (final row in _rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  @override
  Future<MessagePageContract> getMessagePage(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
    String? afterMessageId,
  }) async {
    if (limit <= 0 || limit > 200) {
      throw ArgumentError.value(limit, 'limit');
    }
    if (beforeMessageId != null && afterMessageId != null) {
      throw ArgumentError('beforeMessageId 与 afterMessageId 不能同时使用');
    }
    final all = _sortedRowsOf(conversationId);
    if (afterMessageId != null) {
      final index = all.indexWhere((row) => row['id'] == afterMessageId);
      final window = index < 0
          ? const <Map<String, dynamic>>[]
          : all.sublist(index + 1);
      final slice = window.take(limit).toList();
      return _page(
        slice,
        hasOlder: true,
        hasNewer: window.length > slice.length,
      );
    }
    if (beforeMessageId != null) {
      final index = all.indexWhere((row) => row['id'] == beforeMessageId);
      final window = index < 0 ? all : all.sublist(0, index);
      final slice = _tail(window, limit);
      return _page(
        slice,
        hasOlder: window.length > slice.length,
        hasNewer: true,
      );
    }
    final slice = _tail(all, limit);
    return _page(slice, hasOlder: all.length > slice.length, hasNewer: false);
  }

  static List<Map<String, dynamic>> _tail(
    List<Map<String, dynamic>> rows,
    int limit,
  ) => rows.sublist(rows.length > limit ? rows.length - limit : 0);

  static MessagePageContract _page(
    List<Map<String, dynamic>> rows, {
    required bool hasOlder,
    required bool hasNewer,
  }) => MessagePageContract(
    items: List.unmodifiable(rows.map(MessageContract.fromJson)),
    hasOlder: hasOlder,
    hasNewer: hasNewer,
  );

  @override
  Future<MessageContract> saveMessage(
    String conversationId,
    String role,
    String content, {
    DateTime? createdAt,
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool toolUsed = false,
  }) async {
    if (!const {'user', 'assistant', 'system'}.contains(role)) {
      throw ArgumentError.value(role, 'role', '不支持的消息角色');
    }
    final row = <String, dynamic>{
      'id': demoId('message'),
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'created_at': (createdAt ?? demoNow().toUtc()).toIso8601String(),
      if (reasoning != null) 'reasoning': reasoning,
      if (answerStatus != null) 'answer_status': answerStatus,
      if (failureHint != null) 'failure_hint': failureHint,
      'tool_used': toolUsed,
    };
    _rows.add(row);
    return MessageContract.fromJson(row);
  }

  @override
  Future<void> updateMessage(String messageId, String newContent) async {
    final row = _rowById(messageId);
    if (row == null) throw StateError('消息不存在或已删除');
    row['content'] = newContent;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final before = _rows.length;
    _rows.removeWhere((row) => row['id'] == messageId);
    if (_rows.length == before) throw StateError('消息不存在或已删除');
  }

  @override
  Future<void> clearMessages(String conversationId) async {
    _rows.removeWhere((row) => row['conversation_id'] == conversationId);
  }

  @override
  Future<List<MessageContract>> getMessages(
    String conversationId, {
    Set<String>? onlyMessageIds,
  }) async {
    final rows = _sortedRowsOf(conversationId);
    final selected = onlyMessageIds == null
        ? rows
        : rows.where((row) => onlyMessageIds.contains(row['id'])).toList();
    return selected.map(MessageContract.fromJson).toList();
  }

  @override
  Future<void> updateMessageContent(
    String messageId,
    String content, {
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool? toolUsed,
  }) async {
    final row = _rowById(messageId);
    if (row == null) throw StateError('消息不存在或已删除');
    row['content'] = content;
    if (reasoning != null) row['reasoning'] = reasoning;
    if (answerStatus != null) row['answer_status'] = answerStatus;
    if (failureHint != null) row['failure_hint'] = failureHint;
    if (toolUsed != null) row['tool_used'] = toolUsed;
  }

  @override
  Future<MessageAttachmentContract> attachLocalFileToMessage({
    required String messageId,
    required String sourcePath,
    required String originalName,
    String? mimeType,
  }) async => _attach(
    messageId,
    MessageAttachmentContract(
      id: demoId('attachment'),
      name: originalName,
      status: 'available',
      mimeType: mimeType,
    ),
  );

  @override
  Future<MessageAttachmentContract> attachLinkToMessage({
    required String messageId,
    required String url,
  }) async => _attach(
    messageId,
    MessageAttachmentContract(
      id: demoId('attachment'),
      name: url,
      status: 'available',
      mimeType: 'text/uri-list',
      sourceUrl: url,
    ),
  );

  /// 演示版不读取真实文件：仅把附件元数据挂到消息行。
  MessageAttachmentContract _attach(
    String messageId,
    MessageAttachmentContract attachment,
  ) {
    final row = _rowById(messageId);
    if (row == null) throw StateError('消息不存在或已删除');
    final existing = (row['attachments'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((raw) => raw.cast<String, Object?>())
        .toList();
    existing.add(attachment.toJson());
    row['attachments'] = existing;
    return attachment;
  }

  @override
  Future<MessageSearchPage> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
    int offset = 0,
  }) async {
    final needle = query.trim().toLowerCase();
    final matches = _rows.where((row) {
      if (conversationId != null && row['conversation_id'] != conversationId) {
        return false;
      }
      return (row['content'] as String? ?? '').toLowerCase().contains(needle);
    }).toList();
    final items = matches
        .skip(offset)
        .take(limit)
        .map(
          (row) => SearchResult(
            messageId: row['id'] as String,
            conversationId: row['conversation_id'] as String,
            role: row['role'] as String,
            content: row['content'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
    return MessageSearchPage(
      items: List.unmodifiable(items),
      total: matches.length,
    );
  }

  @override
  Future<List<Map<String, Object?>>> getMessageSegments(
    String messageId,
  ) async => const [];
}
