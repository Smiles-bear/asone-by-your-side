/// Token 使用汇总
class TokenUsageSummary {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  TokenUsageSummary({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });
}

/// 每日 Token 使用
class DailyTokenUsage {
  final DateTime date;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  DailyTokenUsage({
    required this.date,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });
}

/// Token 使用记录
class TokenUsageRecord {
  final String recordId;
  final String assistantId;
  final String taskType;
  final String? taskSubtype;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final String? requestId;
  final String? conversationId;
  final String? messageId;
  final String? jobId;
  final DateTime createdAt;

  TokenUsageRecord({
    required this.recordId,
    required this.assistantId,
    required this.taskType,
    this.taskSubtype,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    this.requestId,
    this.conversationId,
    this.messageId,
    this.jobId,
    required this.createdAt,
  });

  factory TokenUsageRecord.fromMap(Map<String, dynamic> map) {
    return TokenUsageRecord(
      recordId: map['record_id'] as String,
      assistantId: map['assistant_id'] as String,
      taskType: map['task_type'] as String,
      taskSubtype: map['task_subtype'] as String?,
      inputTokens: map['input_tokens'] as int,
      outputTokens: map['output_tokens'] as int,
      totalTokens: map['total_tokens'] as int,
      requestId: map['request_id'] as String?,
      conversationId: map['conversation_id'] as String?,
      messageId: map['message_id'] as String?,
      jobId: map['job_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
