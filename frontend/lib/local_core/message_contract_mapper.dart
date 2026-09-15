import 'package:asone_contracts/asone_contracts.dart';

import '../models/message.dart';

/// 私有 [Message] → 公开 [MessageContract] 的单向映射器。
///
/// 白名单式逐字段拷贝：语音、导演脚本、工具确认卡、配置帮助卡、
/// 流式分段等闭源语义在映射时整体丢弃；附件剥离本地存储路径。
class MessageContractMapper {
  MessageContractMapper._();

  /// id 缺失的行返回 null（调用方过滤）。
  static MessageContract? toPublic(
    Message message, {
    required String conversationId,
  }) {
    final id = message.id;
    if (id == null || id.isEmpty) return null;
    return MessageContract(
      id: id,
      conversationId: conversationId,
      role: _roleOf(message.role),
      content: message.content,
      createdAt: message.createdAt ?? DateTime.now(),
      answerStatus: MessageContract.parseAnswerStatus(message.answerStatus),
      failureHint: message.failureHint,
      elapsedMs: message.elapsedMs,
      hasToolTrace: message.toolUsed,
      reasoning: message.reasoning,
      attachments: [
        for (final attachment in message.attachments)
          attachmentToPublic(attachment),
      ],
    );
  }

  /// 附件白名单映射：本地存储路径（storagePath）在此剥离。
  static MessageAttachmentContract attachmentToPublic(
    MessageAttachment attachment,
  ) => MessageAttachmentContract(
    id: attachment.id,
    name: attachment.name,
    status: attachment.status,
    mimeType: attachment.mimeType,
    sourceUrl: attachment.sourceUrl,
    byteSize: attachment.byteSize,
  );

  static MessageRole _roleOf(String raw) => switch (raw) {
    'user' => MessageRole.user,
    'assistant' => MessageRole.assistant,
    _ => MessageRole.system,
  };
}
