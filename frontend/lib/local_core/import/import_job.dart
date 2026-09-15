import 'dart:convert';

class ImportJob {
  const ImportJob({
    required this.jobId,
    required this.status,
    required this.stage,
    required this.progress,
    required this.totalItems,
    required this.processedItems,
    required this.warnings,
    required this.errors,
    required this.cancelRequested,
    required this.checkpoint,
    required this.targetAssistantId,
    required this.targetConversationId,
    required this.hidden,
    required this.createdAt,
    required this.updatedAt,
    this.targetCount = 0,
    this.warningCount = 0,
    this.errorCount = 0,
    this.retryable = false,
    this.errorCode = '',
    this.stageTotalItems = 0,
    this.stageProcessedItems = 0,
  });

  final String jobId;
  final String status;
  final String stage;
  final double progress;
  final int totalItems;
  final int processedItems;
  final List<String> warnings;
  final List<String> errors;
  final bool cancelRequested;
  final int checkpoint;
  final String? targetAssistantId;
  final String? targetConversationId;
  final bool hidden;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int targetCount;
  final int warningCount;
  final int errorCount;
  final bool retryable;
  final String errorCode;
  final int stageTotalItems;
  final int stageProcessedItems;

  bool get isTerminal =>
      const {'completed', 'cancelled', 'failed'}.contains(status);

  /// Actions are part of the Local App Core contract. Flutter renders these
  /// values and never guesses what a stage is allowed to do.
  Set<String> get allowedActions {
    if (status == 'created') return const {'preview', 'cancel'};
    if (status == 'ready') return const {'preview', 'start', 'cancel'};
    if (status == 'running') return const {'status', 'cancel'};
    if (status == 'paused') return const {'status', 'resume', 'cancel'};
    if (status == 'failed') return const {'status', 'resume', 'cancel'};
    if (status == 'cancelled') return const {'status', 'resume'};
    if (status == 'completed') return const {'status', 'finish'};
    return const {'status'};
  }

  Map<String, Object?> toJson() => {
    'job_id': jobId,
    'status': status,
    'stage': stage,
    'progress': progress,
    'total_items': totalItems,
    'processed_items': processedItems,
    'stage_total_items': stageTotalItems,
    'stage_processed_items': stageProcessedItems,
    'warnings': warnings,
    'errors': errors,
    'warning_count': warningCount,
    'error_count': errorCount,
    'retryable': retryable,
    'error_code': errorCode,
    'cancel_requested': cancelRequested,
    'checkpoint': checkpoint,
    'target_assistant_id': targetAssistantId,
    'target_conversation_id': targetConversationId,
    'target_count': targetCount,
    'hidden': hidden,
    'allowed_actions': allowedActions.toList()..sort(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory ImportJob.fromMap(Map<String, Object?> row) => ImportJob(
    jobId: row['job_id']! as String,
    status: row['status']! as String,
    stage: row['stage']! as String,
    progress: (row['progress']! as num).toDouble(),
    totalItems: row['total_items']! as int,
    processedItems: row['processed_items']! as int,
    warnings: _strings(row['warnings']),
    errors: _strings(row['errors']),
    cancelRequested: row['cancel_requested'] == 1,
    checkpoint: row['checkpoint']! as int,
    targetAssistantId: row['target_assistant_id'] as String?,
    targetConversationId: row['target_conversation_id'] as String?,
    hidden: row['hidden'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    targetCount: row['target_count'] as int? ?? 0,
    warningCount:
        row['warning_count'] as int? ?? _strings(row['warnings']).length,
    errorCount: row['error_count'] as int? ?? _strings(row['errors']).length,
    retryable: row['retryable'] == 1,
    errorCode: row['error_code'] as String? ?? '',
    stageTotalItems: row['stage_total_items'] as int? ?? 0,
    stageProcessedItems: row['stage_processed_items'] as int? ?? 0,
  );
}

class ImportPreview {
  const ImportPreview({
    required this.jobId,
    required this.conversationCount,
    required this.messageCount,
    required this.roles,
    required this.timestampExactCount,
    required this.timestampPartialCount,
    required this.timestampUnknownCount,
    required this.imageCount,
    required this.fileCount,
    required this.uncertainRoles,
    required this.warnings,
    required this.errors,
    required this.sampleMessages,
    required this.parserSummary,
    required this.canStart,
    required this.planFrozen,
    this.sourceConversations = const [],
    this.attachmentAvailableCount = 0,
    this.attachmentMissingCount = 0,
    this.attachmentDamagedCount = 0,
    this.duplicateConfirmedCount = 0,
    this.duplicatePossibleCount = 0,
    this.duplicateNewCount = 0,
    this.needsConversationOrder = false,
  });

  final String jobId;
  final int conversationCount;
  final int messageCount;
  final Map<String, int> roles;
  final int timestampExactCount;
  final int timestampPartialCount;
  final int timestampUnknownCount;
  final int imageCount;
  final int fileCount;
  final List<UncertainRole> uncertainRoles;
  final List<String> warnings;
  final List<String> errors;
  final List<ImportSampleMessage> sampleMessages;
  final ImportParserSummary? parserSummary;
  final bool canStart;
  final bool planFrozen;
  final List<ImportSourceConversation> sourceConversations;
  final int attachmentAvailableCount;
  final int attachmentMissingCount;
  final int attachmentDamagedCount;
  final int duplicateConfirmedCount;
  final int duplicatePossibleCount;
  final int duplicateNewCount;
  final bool needsConversationOrder;

  int get missingTimestampCount => timestampUnknownCount;
}

class ImportSourceConversation {
  const ImportSourceConversation({
    required this.id,
    required this.title,
    required this.order,
    required this.messageCount,
    required this.timestampUnknownCount,
  });

  final String id;
  final String title;
  final int order;
  final int messageCount;
  final int timestampUnknownCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'order': order,
    'message_count': messageCount,
    'timestamp_unknown_count': timestampUnknownCount,
  };
}

class UncertainRole {
  const UncertainRole({required this.sourceRole, required this.messageCount});

  final String sourceRole;
  final int messageCount;
}

class ImportSampleMessage {
  const ImportSampleMessage({
    required this.sourceConversationId,
    required this.sourceMessageId,
    required this.role,
    required this.sourceRole,
    required this.roleStatus,
    required this.content,
    required this.sourceCreatedAt,
    required this.timestampStatus,
    this.imageCount = 0,
    this.fileCount = 0,
  });

  final String sourceConversationId;
  final String sourceMessageId;
  final String role;
  final String? sourceRole;
  final String roleStatus;
  final String content;
  final DateTime? sourceCreatedAt;
  final String timestampStatus;
  final int imageCount;
  final int fileCount;
}

class ImportParserSummary {
  const ImportParserSummary({
    required this.parserId,
    required this.parserVersion,
    required this.containerFormat,
    required this.confidence,
    required this.capabilities,
    required this.sourceName,
  });

  final String parserId;
  final String parserVersion;
  final String containerFormat;
  final double confidence;
  final List<String> capabilities;
  final String sourceName;
}

class FileImportCreation {
  const FileImportCreation({required this.job, required this.preview});

  final ImportJob job;
  final ImportPreview preview;
}

List<String> _strings(Object? value) {
  if (value is! String) return const [];
  final decoded = jsonDecode(value);
  return decoded is List ? decoded.cast<String>() : const [];
}
