import 'dart:async';
import 'dart:math';

import '../services/task_protection_manager.dart';
import 'core_database.dart';
import 'local_job.dart';
import 'local_job_handler.dart';
import 'local_job_registry.dart';

class LocalJobCreationResult {
  const LocalJobCreationResult({required this.job, required this.created});

  final LocalJob job;
  final bool created;
}

class LocalJobService {
  LocalJobService({CoreDatabase? coreDatabase, LocalJobRegistry? registry})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
      _registry = registry ?? LocalJobRegistry.instance;

  final CoreDatabase _coreDatabase;
  final LocalJobRegistry _registry;
  final Random _random = Random.secure();
  final Set<String> _running = {};
  final Map<String, Future<void>> _runningFutures = {};

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${_random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0')}';

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<LocalJob> create({
    int totalItems = 40,
    String? taskType,
    String? payload,
    String? scopeType,
    String? scopeId,
  }) async {
    if (totalItems <= 0) throw ArgumentError.value(totalItems, 'totalItems');
    final database = await _coreDatabase.open();
    final job = _newJobMap(
      totalItems: totalItems,
      taskType: taskType,
      payload: payload,
      scopeType: scopeType,
      scopeId: scopeId,
    );
    await database.insert('local_jobs', job);
    return LocalJob.fromMap(job);
  }

  /// 在同一个 SQLite 事务内检查并创建作用域任务，避免连续点击或并发入口
  /// 在同一业务作用域内创建多个互相冲突的任务。
  Future<LocalJobCreationResult> createExclusiveForScope({
    int totalItems = 40,
    required String taskType,
    required String payload,
    required String scopeType,
    required String scopeId,
  }) async {
    if (totalItems <= 0) throw ArgumentError.value(totalItems, 'totalItems');
    final database = await _coreDatabase.open();
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'local_jobs',
        where:
            "task_type = ? AND scope_type = ? AND scope_id = ? "
            "AND status NOT IN ('completed', 'cancelled')",
        whereArgs: [taskType, scopeType, scopeId],
        orderBy: 'updated_at DESC',
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return LocalJobCreationResult(
          job: LocalJob.fromMap(existing.single),
          created: false,
        );
      }
      final job = _newJobMap(
        totalItems: totalItems,
        taskType: taskType,
        payload: payload,
        scopeType: scopeType,
        scopeId: scopeId,
      );
      await transaction.insert('local_jobs', job);
      return LocalJobCreationResult(job: LocalJob.fromMap(job), created: true);
    });
  }

  Map<String, Object?> _newJobMap({
    required int totalItems,
    required String? taskType,
    required String? payload,
    required String? scopeType,
    required String? scopeId,
  }) {
    final now = _now();
    return <String, Object?>{
      'job_id': _id(),
      'status': 'created',
      'stage': 'waiting',
      'total_items': totalItems,
      'processed_items': 0,
      'cancel_requested': 0,
      'checkpoint': 0,
      'created_at': now,
      'updated_at': now,
      'task_type': taskType,
      'payload': payload,
      'scope_type': scopeType,
      'scope_id': scopeId,
      'retry_count': 0,
    };
  }

  Future<LocalJob?> get(String jobId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'local_jobs',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
    return rows.isEmpty ? null : LocalJob.fromMap(rows.single);
  }

  Future<LocalJob?> latest() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'local_jobs',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalJob.fromMap(rows.single);
  }

  Future<List<LocalJob>> unfinished() async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'local_jobs',
      where: 'status NOT IN (?, ?, ?)',
      whereArgs: ['completed', 'cancelled', 'failed'],
      orderBy: 'updated_at ASC',
    );
    return rows.map(LocalJob.fromMap).toList();
  }

  /// 用户任务中心可见任务：完成或由用户取消后消失，失败任务保留。
  Future<List<LocalJob>> visibleTasks({Set<String>? taskTypes}) async {
    final database = await _coreDatabase.open();
    final types =
        taskTypes?.where((type) => type.isNotEmpty).toList() ?? const [];
    final typeClause = types.isEmpty
        ? ''
        : ' AND task_type IN (${List.filled(types.length, '?').join(',')})';
    final rows = await database.query(
      'local_jobs',
      where: "status NOT IN ('completed', 'cancelled')$typeClause",
      whereArgs: types,
      orderBy: 'updated_at DESC',
    );
    return rows.map(LocalJob.fromMap).toList(growable: false);
  }

  Future<void> start(String jobId) => resume(jobId);

  Future<void> retry(String jobId) async {
    final database = await _coreDatabase.open();
    final job = await get(jobId);
    if (job == null) throw StateError('任务不存在');
    if (job.status != 'failed') return;
    await database.update(
      'local_jobs',
      {
        'status': 'created',
        'stage': 'waiting',
        'cancel_requested': 0,
        'last_error': null,
        'retry_count': job.retryCount + 1,
        'updated_at': _now(),
      },
      where: "job_id = ? AND status = 'failed'",
      whereArgs: [jobId],
    );
    await resume(jobId);
  }

  Future<void> pause(String jobId) async {
    final database = await _coreDatabase.open();
    await database.update(
      'local_jobs',
      {'status': 'pause_requested', 'updated_at': _now()},
      where: "job_id = ? AND status IN ('created', 'running')",
      whereArgs: [jobId],
    );
  }

  /// 幂等启动。进程被系统杀死后内存锁消失，重开 App 会从持久化 checkpoint 续跑。
  Future<void> resume(String jobId) async {
    if (_running.contains(jobId)) return;
    var job = await get(jobId);
    if (job == null) throw StateError('任务不存在');
    if (job.isTerminal) return;
    if (job.isPaused) {
      final database = await _coreDatabase.open();
      await database.update(
        'local_jobs',
        {'status': 'created', 'stage': 'waiting', 'updated_at': _now()},
        where: "job_id = ? AND status = 'paused'",
        whereArgs: [jobId],
      );
      job = await get(jobId);
      if (job == null || job.isTerminal || job.isPaused) return;
    }
    if (job.isPauseRequested) return;
    _running.add(jobId);
    final running = _run(jobId);
    _runningFutures[jobId] = running;
    unawaited(
      running.whenComplete(() {
        _runningFutures.remove(jobId);
      }),
    );
  }

  /// 启动任务并等待其落到终态，供 WorkManager 等有执行租期的入口使用。
  Future<void> runToCompletion(String jobId) async {
    await resume(jobId);
    final running = _runningFutures[jobId];
    if (running != null) await running;
  }

  Future<void> updateError(String jobId, String errorMessage) async {
    final database = await _coreDatabase.open();
    final job = await get(jobId);
    if (job == null) throw StateError('任务不存在');

    await database.update(
      'local_jobs',
      {
        'last_error': errorMessage,
        'retry_count': job.retryCount + 1,
        'updated_at': _now(),
      },
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  Future<void> cancel(String jobId) async {
    final database = await _coreDatabase.open();
    final job = await get(jobId);
    if (job?.status == 'failed' || job?.status == 'paused') {
      await database.update(
        'local_jobs',
        {
          'status': 'cancelled',
          'stage': 'cancelled',
          'cancel_requested': 1,
          'updated_at': _now(),
        },
        where: "job_id = ? AND status IN ('failed', 'paused')",
        whereArgs: [jobId],
      );
      return;
    }
    await database.update(
      'local_jobs',
      {'cancel_requested': 1, 'updated_at': _now()},
      where: 'job_id = ? AND status NOT IN (?, ?, ?)',
      whereArgs: [jobId, 'completed', 'cancelled', 'failed'],
    );
  }

  /// App 进程重建时，把已失去执行者的指定任务落到稳定状态。
  /// 用户主动暂停的任务保持暂停；其余执行中的任务标记为可重试中断。
  Future<void> interruptOrphanedTasks({required Set<String> taskTypes}) async {
    if (taskTypes.isEmpty) return;
    final database = await _coreDatabase.open();
    final placeholders = List.filled(taskTypes.length, '?').join(',');
    final args = taskTypes.toList(growable: false);
    final now = _now();
    await database.transaction((transaction) async {
      await transaction.update(
        'local_jobs',
        {'status': 'paused', 'stage': 'paused', 'updated_at': now},
        where: "task_type IN ($placeholders) AND status = 'pause_requested'",
        whereArgs: args,
      );
      await transaction.update(
        'local_jobs',
        {
          'status': 'failed',
          'stage': 'interrupted',
          'last_error': '任务运行被中断，请重试',
          'updated_at': now,
        },
        where:
            "task_type IN ($placeholders) AND status IN ('created', 'running')",
        whereArgs: args,
      );
    });
  }

  /// 升级或异常退出可能遗留同一作用域的多个旧任务，只保留最近的一项供用户恢复。
  Future<void> reconcileExclusiveScopes({
    required Set<String> taskTypes,
  }) async {
    if (taskTypes.isEmpty) return;
    final database = await _coreDatabase.open();
    final placeholders = List.filled(taskTypes.length, '?').join(',');
    final args = taskTypes.toList(growable: false);
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'local_jobs',
        where:
            "task_type IN ($placeholders) "
            "AND scope_type IS NOT NULL AND scope_id IS NOT NULL "
            "AND status NOT IN ('completed', 'cancelled')",
        whereArgs: args,
        orderBy: 'updated_at DESC, created_at DESC',
      );
      final retainedScopes = <String>{};
      final staleIds = <String>[];
      for (final row in rows) {
        final key =
            '${row['task_type']}\u0000${row['scope_type']}\u0000${row['scope_id']}';
        if (!retainedScopes.add(key)) staleIds.add(row['job_id']! as String);
      }
      if (staleIds.isEmpty) return;
      final now = _now();
      for (final jobId in staleIds) {
        await transaction.update(
          'local_jobs',
          {
            'status': 'cancelled',
            'stage': 'superseded',
            'cancel_requested': 1,
            'updated_at': now,
          },
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
      }
    });
  }

  Future<int> cancelActiveByScope({
    required String taskType,
    required String scopeType,
    required String scopeId,
  }) async {
    final database = await _coreDatabase.open();
    return database.update(
      'local_jobs',
      {'cancel_requested': 1, 'updated_at': _now()},
      where:
          'task_type = ? AND scope_type = ? AND scope_id = ? AND status NOT IN (?, ?, ?)',
      whereArgs: [
        taskType,
        scopeType,
        scopeId,
        'completed',
        'cancelled',
        'failed',
      ],
    );
  }

  Future<void> _run(String jobId) async {
    LocalJob? job;
    try {
      job = await get(jobId);
      if (job == null) return;

      // 如果任务有 taskType，使用 Handler 执行
      if (job.taskType != null) {
        await _runWithHandler(jobId, job);
        return;
      }

      // 兼容旧的计数任务（taskType = null）
      await _runLegacyCountingTask(jobId);
    } catch (e) {
      // 标记任务失败
      await _markAsFailed(jobId, e.toString());
      // 通知任务保护管理器：任务失败
      if (job?.taskType != null) {
        await TaskProtectionManager.instance.onTaskEnded(job!.taskType!);
      }
    } finally {
      _running.remove(jobId);
    }
  }

  Future<void> _runWithHandler(String jobId, LocalJob job) async {
    final handler = _registry.getHandler(job.taskType!);
    if (handler == null) {
      await _markAsFailed(
        jobId,
        'No handler registered for task type: ${job.taskType}',
      );
      return;
    }

    try {
      final database = await _coreDatabase.open();
      final beforeStart = await get(jobId);
      if (beforeStart == null) return;
      if (beforeStart.isPauseRequested || beforeStart.isPaused) {
        await _settlePaused(jobId);
        return;
      }
      await database.update(
        'local_jobs',
        {'status': 'running', 'updated_at': _now()},
        where: 'job_id = ?',
        whereArgs: [jobId],
      );

      // 通知任务保护管理器：任务开始运行
      await TaskProtectionManager.instance.onTaskStarted(job.taskType!);

      final context = _LocalJobContextImpl(
        jobId: jobId,
        service: this,
        initialJob: job,
      );

      await handler.execute(job, context);

      // 检查是否被暂停或取消。
      final finalJob = await get(jobId);
      if (finalJob != null && finalJob.cancelRequested) {
        await database.update(
          'local_jobs',
          {'status': 'cancelled', 'stage': 'cancelled', 'updated_at': _now()},
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        // 通知任务保护管理器：任务被取消
        await TaskProtectionManager.instance.onTaskEnded(job.taskType!);
        return;
      }
      if (finalJob?.isPauseRequested == true || finalJob?.isPaused == true) {
        await _settlePaused(jobId);
        await TaskProtectionManager.instance.onTaskEnded(job.taskType!);
        return;
      }

      // 正常完成
      await database.update(
        'local_jobs',
        {'status': 'completed', 'stage': 'completed', 'updated_at': _now()},
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
      // 通知任务保护管理器：任务完成
      await TaskProtectionManager.instance.onTaskEnded(job.taskType!);
    } catch (e) {
      final latest = await get(jobId);
      if (latest?.cancelRequested == true) {
        final database = await _coreDatabase.open();
        await database.update(
          'local_jobs',
          {'status': 'cancelled', 'stage': 'cancelled', 'updated_at': _now()},
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
      } else if (latest?.isPauseRequested == true || latest?.isPaused == true) {
        await _settlePaused(jobId);
      } else {
        await _markAsFailed(jobId, e.toString());
      }
      // 无论失败或取消，都释放任务保护状态。
      await TaskProtectionManager.instance.onTaskEnded(job.taskType!);
      // 不再 rethrow，避免外层 catch 重复处理
    }
  }

  Future<void> _settlePaused(String jobId) async {
    final database = await _coreDatabase.open();
    await database.update(
      'local_jobs',
      {'status': 'paused', 'stage': 'paused', 'updated_at': _now()},
      where:
          "job_id = ? AND status IN ('created', 'running', 'pause_requested')",
      whereArgs: [jobId],
    );
  }

  Future<void> _markAsFailed(String jobId, String error) async {
    final database = await _coreDatabase.open();
    final current = await database.query(
      'local_jobs',
      columns: ['task_type', 'stage'],
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    final preserveStage =
        current.isNotEmpty && current.single['task_type'] == 'world_task';
    await database.update(
      'local_jobs',
      {
        'status': 'failed',
        'stage': preserveStage
            ? current.single['stage'] as String? ?? 'failed'
            : 'failed',
        'last_error': error,
        'updated_at': _now(),
      },
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  Future<void> _runLegacyCountingTask(String jobId) async {
    while (true) {
      final database = await _coreDatabase.open();
      final shouldContinue = await database.transaction((transaction) async {
        final rows = await transaction.query(
          'local_jobs',
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        if (rows.isEmpty) return false;
        final job = LocalJob.fromMap(rows.single);
        if (job.isTerminal) return false;
        if (job.cancelRequested) {
          await transaction.update(
            'local_jobs',
            {'status': 'cancelled', 'stage': 'cancelled', 'updated_at': _now()},
            where: 'job_id = ?',
            whereArgs: [jobId],
          );
          return false;
        }

        final next = (job.checkpoint + 1).clamp(0, job.totalItems);
        final completed = next >= job.totalItems;
        await transaction.update(
          'local_jobs',
          {
            'status': completed ? 'completed' : 'running',
            'stage': completed ? 'completed' : 'counting',
            'processed_items': next,
            'checkpoint': next,
            'updated_at': _now(),
          },
          where: 'job_id = ?',
          whereArgs: [jobId],
        );
        return !completed;
      });
      if (!shouldContinue) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

class _LocalJobContextImpl implements LocalJobContext {
  _LocalJobContextImpl({
    required this.jobId,
    required this.service,
    required LocalJob initialJob,
  }) : _payload = initialJob.payload,
       _scopeType = initialJob.scopeType,
       _scopeId = initialJob.scopeId;

  final String jobId;
  final LocalJobService service;
  final String? _payload;
  final String? _scopeType;
  final String? _scopeId;

  @override
  Future<bool> get isCancelRequested async {
    final job = await service.get(jobId);
    return job?.cancelRequested ?? false;
  }

  @override
  Future<bool> get isPauseRequested async {
    final job = await service.get(jobId);
    return job?.isPauseRequested ?? false;
  }

  @override
  Future<bool> get shouldStopRequested async {
    final job = await service.get(jobId);
    return job == null || job.cancelRequested || job.isPauseRequested;
  }

  @override
  Future<void> updateProgress({
    required int checkpoint,
    int? processedItems,
    String? stage,
  }) async {
    final database = await service._coreDatabase.open();
    final updates = <String, Object?>{
      'checkpoint': checkpoint,
      'updated_at': service._now(),
    };
    if (processedItems != null) updates['processed_items'] = processedItems;
    if (stage != null) updates['stage'] = stage;

    await database.update(
      'local_jobs',
      updates,
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  @override
  String? get payload => _payload;

  @override
  ({String? type, String? id})? get scope {
    if (_scopeType == null && _scopeId == null) return null;
    return (type: _scopeType, id: _scopeId);
  }
}
