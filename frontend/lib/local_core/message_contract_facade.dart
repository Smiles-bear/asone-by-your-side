import 'package:asone_contracts/asone_contracts.dart';

import 'core_repository.dart';
import 'message_contract_mapper.dart';

/// 消息公开契约的私有侧门面。
///
/// 包装 [CoreRepository] 的消息域方法，在返回边界经
/// [MessageContractMapper] 做白名单映射；写入路径参数直传。
class MessageContractFacade implements MessageRepositoryApi {
  MessageContractFacade(this._repository);

  final CoreRepository _repository;

  @override
  Future<MessagePageContract> getMessagePage(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
    String? afterMessageId,
  }) async {
    final page = await _repository.getMessagePage(
      conversationId,
      limit: limit,
      beforeMessageId: beforeMessageId,
      afterMessageId: afterMessageId,
    );
    return MessagePageContract(
      items: List.unmodifiable([
        for (final message in page.messages)
          if (MessageContractMapper.toPublic(
                message,
                conversationId: conversationId,
              )
              case final mapped?)
            mapped,
      ]),
      hasOlder: page.hasOlder,
      hasNewer: page.hasNewer,
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
    final message = await _repository.saveMessage(
      conversationId,
      role,
      content,
      createdAt: createdAt,
      reasoning: reasoning,
      answerStatus: answerStatus,
      failureHint: failureHint,
      toolUsed: toolUsed,
    );
    final mapped = MessageContractMapper.toPublic(
      message,
      conversationId: conversationId,
    );
    if (mapped == null) throw StateError('消息落库结果缺少标识');
    return mapped;
  }

  @override
  Future<void> updateMessage(String messageId, String newContent) =>
      _repository.updateMessage(messageId, newContent);

  @override
  Future<void> deleteMessage(String messageId) =>
      _repository.deleteMessage(messageId);

  @override
  Future<void> clearMessages(String conversationId) =>
      _repository.clearMessages(conversationId);

  @override
  Future<List<MessageContract>> getMessages(
    String conversationId, {
    Set<String>? onlyMessageIds,
  }) async {
    final messages = await _repository.getMessages(
      conversationId,
      onlyMessageIds: onlyMessageIds,
    );
    return List.unmodifiable([
      for (final message in messages)
        if (MessageContractMapper.toPublic(
              message,
              conversationId: conversationId,
            )
            case final mapped?)
          mapped,
    ]);
  }

  @override
  Future<void> updateMessageContent(
    String messageId,
    String content, {
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool? toolUsed,
  }) => _repository.updateMessageContent(
    messageId,
    content,
    reasoning: reasoning,
    answerStatus: answerStatus,
    failureHint: failureHint,
    toolUsed: toolUsed,
  );

  @override
  Future<MessageAttachmentContract> attachLocalFileToMessage({
    required String messageId,
    required String sourcePath,
    required String originalName,
    String? mimeType,
  }) async => MessageContractMapper.attachmentToPublic(
    await _repository.attachLocalFileToMessage(
      messageId: messageId,
      sourcePath: sourcePath,
      originalName: originalName,
      mimeType: mimeType,
    ),
  );

  @override
  Future<MessageAttachmentContract> attachLinkToMessage({
    required String messageId,
    required String url,
  }) async => MessageContractMapper.attachmentToPublic(
    await _repository.attachLinkToMessage(messageId: messageId, url: url),
  );

  @override
  Future<MessageSearchPage> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
    int offset = 0,
  }) async {
    final raw = await _repository.searchMessages(
      query,
      conversationId: conversationId,
      limit: limit,
      offset: offset,
    );
    final items = (raw['items'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((row) => SearchResult.fromJson(row.cast<String, dynamic>()))
        .toList();
    return MessageSearchPage(
      items: List.unmodifiable(items),
      total: raw['total'] as int? ?? items.length,
    );
  }

  @override
  Future<List<Map<String, Object?>>> getMessageSegments(String messageId) =>
      _repository.getMessageSegments(messageId);
}
