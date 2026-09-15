class LocalJob {
  final String jobId;
  final String status;
  final String stage;
  final int totalItems;
  final int processedItems;
  final bool cancelRequested;
  final int checkpoint;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? taskType;
  final String? payload;
  final String? scopeType;
  final String? scopeId;
  final String? lastError;
  final int retryCount;

  const LocalJob({
    required this.jobId,
    required this.status,
    required this.stage,
    required this.totalItems,
    required this.processedItems,
    required this.cancelRequested,
    required this.checkpoint,
    required this.createdAt,
    required this.updatedAt,
    this.taskType,
    this.payload,
    this.scopeType,
    this.scopeId,
    this.lastError,
    this.retryCount = 0,
  });

  bool get isTerminal =>
      const {'completed', 'cancelled', 'failed'}.contains(status);
  bool get isPauseRequested => status == 'pause_requested';
  bool get isPaused => status == 'paused';
  bool get isRunning => const {'created', 'running'}.contains(status);
  double get progress => totalItems == 0 ? 0 : processedItems / totalItems;

  factory LocalJob.fromMap(Map<String, Object?> row) => LocalJob(
    jobId: row['job_id']! as String,
    status: row['status']! as String,
    stage: row['stage']! as String,
    totalItems: row['total_items']! as int,
    processedItems: row['processed_items']! as int,
    cancelRequested: row['cancel_requested'] == 1,
    checkpoint: row['checkpoint']! as int,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    taskType: row['task_type'] as String?,
    payload: row['payload'] as String?,
    scopeType: row['scope_type'] as String?,
    scopeId: row['scope_id'] as String?,
    lastError: row['last_error'] as String?,
    retryCount: (row['retry_count'] as int?) ?? 0,
  );
}
