import 'package:asone_contracts/asone_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MessageContract JSON 往返保留公开字段', () {
    final createdAt = DateTime.utc(2026, 9, 11, 8, 30);
    final message = MessageContract(
      id: 'msg-1',
      conversationId: 'conv-1',
      role: MessageRole.assistant,
      content: '你好，今天有什么安排？',
      createdAt: createdAt,
      answerStatus: MessageAnswerStatus.completed,
      elapsedMs: 850,
      hasToolTrace: true,
      reasoning: '用户在打招呼，回应并询问安排。',
      attachments: const [
        MessageAttachmentContract(
          id: 'att-1',
          name: '计划链接',
          status: 'available',
          mimeType: 'text/uri-list',
          sourceUrl: 'https://example.invalid/plan',
        ),
      ],
    );

    final restored = MessageContract.fromJson(message.toJson());
    expect(restored.id, 'msg-1');
    expect(restored.role, MessageRole.assistant);
    expect(restored.content, message.content);
    expect(restored.createdAt, createdAt);
    expect(restored.answerStatus, MessageAnswerStatus.completed);
    expect(restored.elapsedMs, 850);
    expect(restored.hasToolTrace, isTrue);
    expect(restored.reasoning, message.reasoning);
    expect(
      restored.attachments.single.sourceUrl,
      'https://example.invalid/plan',
    );
    expect(restored.attachments.single.isLink, isTrue);
    expect(restored.streaming, isFalse);
  });

  test('附件契约不携带本地存储路径', () {
    const attachment = MessageAttachmentContract(
      id: 'att-2',
      name: 'photo.png',
      status: 'available',
      mimeType: 'image/png',
      byteSize: 2048,
    );
    final json = attachment.toJson();
    expect(json.containsKey('storage_path'), isFalse);
    expect(json.containsKey('source_path'), isFalse);
    expect(attachment.isImage, isTrue);
    expect(attachment.isAvailable, isTrue);
  });

  test('回复状态容错解析，未知值归为 null', () {
    expect(
      MessageContract.parseAnswerStatus('streaming'),
      MessageAnswerStatus.streaming,
    );
    expect(MessageContract.parseAnswerStatus('bogus'), isNull);
    expect(MessageContract.parseAnswerStatus(null), isNull);
  });

  test('流式状态派生自 answerStatus', () {
    final streaming = MessageContract(
      id: 'msg-2',
      conversationId: 'conv-1',
      role: MessageRole.assistant,
      content: '正在输入…',
      createdAt: DateTime.utc(2026, 9, 11),
      answerStatus: MessageAnswerStatus.streaming,
    );
    expect(streaming.streaming, isTrue);
  });

  test('MessageRepositoryApi 可实现且分页包装可用', () async {
    final api = _FakeMessageRepository();
    final saved = await api.saveMessage('conv-1', 'user', '你好');
    expect(saved.role, MessageRole.user);

    final page = await api.getMessagePage('conv-1');
    expect(page.items, hasLength(1));
    expect(page.hasOlder, isFalse);
    expect(page.hasNewer, isFalse);

    await api.updateMessage(saved.id, '你好呀');
    await api.deleteMessage(saved.id);
    expect((await api.getMessagePage('conv-1')).items, isEmpty);
    await api.clearMessages('conv-1');
  });
}

class _FakeMessageRepository implements MessageRepositoryApi {
  final List<MessageContract> _messages = [];
  int _sequence = 0;

  @override
  Future<MessagePageContract> getMessagePage(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
    String? afterMessageId,
  }) async {
    final items = _messages
        .where((message) => message.conversationId == conversationId)
        .take(limit)
        .toList();
    return MessagePageContract(
      items: List.unmodifiable(items),
      hasOlder: false,
      hasNewer: false,
    );
  }

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
    final message = MessageContract(
      id: 'msg-${++_sequence}',
      conversationId: conversationId,
      role: MessageRole.values.byName(role),
      content: content,
      createdAt: createdAt ?? DateTime.utc(2026, 9, 11),
      answerStatus: MessageContract.parseAnswerStatus(answerStatus),
      failureHint: failureHint,
      reasoning: reasoning,
      hasToolTrace: toolUsed,
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<void> updateMessage(String messageId, String newContent) async {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    final old = _messages[index];
    _messages[index] = MessageContract(
      id: old.id,
      conversationId: old.conversationId,
      role: old.role,
      content: newContent,
      createdAt: old.createdAt,
      answerStatus: old.answerStatus,
      failureHint: old.failureHint,
      elapsedMs: old.elapsedMs,
      hasToolTrace: old.hasToolTrace,
      reasoning: old.reasoning,
      attachments: old.attachments,
    );
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    _messages.removeWhere((message) => message.id == messageId);
  }

  @override
  Future<void> clearMessages(String conversationId) async {
    _messages.removeWhere(
      (message) => message.conversationId == conversationId,
    );
  }

  @override
  Future<List<MessageContract>> getMessages(
    String conversationId, {
    Set<String>? onlyMessageIds,
  }) async => _messages
      .where((message) => message.conversationId == conversationId)
      .where(
        (message) =>
            onlyMessageIds == null || onlyMessageIds.contains(message.id),
      )
      .toList();

  @override
  Future<void> updateMessageContent(
    String messageId,
    String content, {
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool? toolUsed,
  }) async => updateMessage(messageId, content);

  @override
  Future<MessageAttachmentContract> attachLocalFileToMessage({
    required String messageId,
    required String sourcePath,
    required String originalName,
    String? mimeType,
  }) async => MessageAttachmentContract(
    id: 'att-${++_sequence}',
    name: originalName,
    status: 'available',
    mimeType: mimeType,
  );

  @override
  Future<MessageAttachmentContract> attachLinkToMessage({
    required String messageId,
    required String url,
  }) async => MessageAttachmentContract(
    id: 'att-${++_sequence}',
    name: url,
    status: 'available',
    mimeType: 'text/uri-list',
    sourceUrl: url,
  );

  @override
  Future<MessageSearchPage> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
    int offset = 0,
  }) async {
    final matches = _messages
        .where((message) => message.content.contains(query))
        .toList();
    return MessageSearchPage(
      items: [
        for (final message in matches)
          SearchResult(
            messageId: message.id,
            conversationId: message.conversationId,
            role: message.role.name,
            content: message.content,
            createdAt: message.createdAt,
          ),
      ],
      total: matches.length,
    );
  }

  @override
  Future<List<Map<String, Object?>>> getMessageSegments(
    String messageId,
  ) async => const [];
}
