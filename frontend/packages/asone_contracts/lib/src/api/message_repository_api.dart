import '../models/message_contract.dart';

/// 聊天消息公开数据访问契约（基础文字消息）。
///
/// 语音、导演脚本、工具确认卡、配置帮助卡等闭源语义不在本接口范围；
/// 流式增量事件 v1 不定义（公开侧聊天为"发送 → 整条出现"）。
abstract interface class MessageRepositoryApi {
  /// 分页拉取会话消息（显示顺序）；游标用消息 id。
  ///
  /// [beforeMessageId] 与 [afterMessageId] 不能同时使用。
  Future<MessagePageContract> getMessagePage(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
    String? afterMessageId,
  });

  /// 保存一条消息并返回落库后的契约对象。
  ///
  /// [role] 取值 user / assistant / system；[answerStatus] 取值
  /// streaming / completed / failed / cancelled。
  Future<MessageContract> saveMessage(
    String conversationId,
    String role,
    String content, {
    DateTime? createdAt,
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool toolUsed = false,
  });

  /// 更新消息正文（保留版本与时间戳语义由实现决定）。
  Future<void> updateMessage(String messageId, String newContent);

  /// 拉取会话消息（显示顺序），可按 id 集合过滤。
  Future<List<MessageContract>> getMessages(
    String conversationId, {
    Set<String>? onlyMessageIds,
  });

  /// 精确更新消息正文与可选状态字段（null 表示不改动对应列）。
  Future<void> updateMessageContent(
    String messageId,
    String content, {
    String? reasoning,
    String? answerStatus,
    String? failureHint,
    bool? toolUsed,
  });

  /// 为消息关联本地文件附件；返回的契约对象不含本地存储路径。
  Future<MessageAttachmentContract> attachLocalFileToMessage({
    required String messageId,
    required String sourcePath,
    required String originalName,
    String? mimeType,
  });

  /// 为消息关联链接附件。
  Future<MessageAttachmentContract> attachLinkToMessage({
    required String messageId,
    required String url,
  });

  /// 全文搜索消息（分页）。
  Future<MessageSearchPage> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
    int offset = 0,
  });

  /// 读取消息流式分段（segment_index 升序）；无分段实现返回空列表。
  Future<List<Map<String, Object?>>> getMessageSegments(String messageId);

  /// 删除单条消息（软删除语义由实现决定）。
  Future<void> deleteMessage(String messageId);

  /// 清空会话消息。
  Future<void> clearMessages(String conversationId);
}
