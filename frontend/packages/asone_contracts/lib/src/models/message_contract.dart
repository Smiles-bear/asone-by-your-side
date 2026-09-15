// 聊天消息公开契约：基础文字消息 + 附件展示 + 分页包装 + 搜索页。
//
// 闭源语义（语音、导演脚本、工具确认卡、配置帮助卡）不进入本契约；
// 宿主侧私有 Message 经适配器单向映射为 MessageContract。

import 'search_result.dart';

/// 消息角色（与私有 messages 表 CHECK 约束一致）。
enum MessageRole { user, assistant, system }

/// 助手回复状态；用户消息为 null。
enum MessageAnswerStatus { streaming, completed, failed, cancelled }

/// 消息附件（公开子集：不含本地存储路径）。
class MessageAttachmentContract {
  const MessageAttachmentContract({
    required this.id,
    required this.name,
    required this.status,
    this.mimeType,
    this.sourceUrl,
    this.byteSize,
  });

  factory MessageAttachmentContract.fromJson(Map<String, Object?> json) =>
      MessageAttachmentContract(
        id: json['attachment_id'] as String? ?? '',
        name: json['original_name'] as String? ?? '',
        status: json['status'] as String? ?? 'available',
        mimeType: json['mime_type'] as String?,
        sourceUrl: json['source_url'] as String?,
        byteSize: json['byte_size'] as int?,
      );

  final String id;
  final String name;
  final String status;
  final String? mimeType;
  final String? sourceUrl;
  final int? byteSize;

  bool get isLink => sourceUrl != null && sourceUrl!.isNotEmpty;
  bool get isImage => (mimeType ?? '').startsWith('image/');
  bool get isAvailable => status == 'available';

  Map<String, Object?> toJson() => {
    'attachment_id': id,
    'original_name': name,
    'status': status,
    if (mimeType != null) 'mime_type': mimeType,
    if (sourceUrl != null) 'source_url': sourceUrl,
    if (byteSize != null) 'byte_size': byteSize,
  };
}

/// 单条聊天消息的公开契约。
class MessageContract {
  const MessageContract({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.answerStatus,
    this.failureHint,
    this.elapsedMs,
    this.hasToolTrace = false,
    this.reasoning,
    this.attachments = const [],
  });

  factory MessageContract.fromJson(Map<String, Object?> json) =>
      MessageContract(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String? ?? '',
        role: MessageRole.values.byName(json['role'] as String? ?? 'system'),
        content: json['content'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        answerStatus: parseAnswerStatus(json['answer_status'] as String?),
        failureHint: json['failure_hint'] as String?,
        elapsedMs: json['elapsed_ms'] as int?,
        hasToolTrace: json['tool_used'] as bool? ?? false,
        reasoning: json['reasoning'] as String?,
        attachments: (json['attachments'] as List? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (raw) => MessageAttachmentContract.fromJson(
                raw.cast<String, Object?>(),
              ),
            )
            .toList(),
      );

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageAnswerStatus? answerStatus;
  final String? failureHint;
  final int? elapsedMs;

  /// 工具使用痕迹角标（不暴露工具执行细节）。
  final bool hasToolTrace;

  /// 单次回复的思考过程文本（非持续心智语义）。
  final String? reasoning;

  final List<MessageAttachmentContract> attachments;

  /// 流式光标展示（派生自 answerStatus，不序列化）。
  bool get streaming => answerStatus == MessageAnswerStatus.streaming;

  /// 容错解析回复状态；未知值归为 null。
  static MessageAnswerStatus? parseAnswerStatus(String? raw) {
    if (raw == null) return null;
    for (final value in MessageAnswerStatus.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    if (answerStatus != null) 'answer_status': answerStatus!.name,
    if (failureHint != null) 'failure_hint': failureHint,
    if (elapsedMs != null) 'elapsed_ms': elapsedMs,
    'tool_used': hasToolTrace,
    if (reasoning != null) 'reasoning': reasoning,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((item) => item.toJson()).toList(),
  };
}

/// 消息分页包装（游标以 [items] 首尾 id + 接口 before/after 参数表达）。
class MessagePageContract {
  const MessagePageContract({
    required this.items,
    required this.hasOlder,
    required this.hasNewer,
  });

  final List<MessageContract> items;
  final bool hasOlder;
  final bool hasNewer;
}

/// 消息全文搜索结果页。
class MessageSearchPage {
  const MessageSearchPage({required this.items, required this.total});

  final List<SearchResult> items;
  final int total;
}
