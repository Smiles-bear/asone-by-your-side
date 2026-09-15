import 'package:asone_contracts/asone_contracts.dart'
    show DailyTokenUsage, TokenUsageApi, TokenUsageRecord, TokenUsageSummary;

import 'core_database.dart';
import 'stable_id_factory.dart';

export 'package:asone_contracts/asone_contracts.dart'
    show DailyTokenUsage, TokenUsageRecord, TokenUsageSummary;

/// Token 用量统计服务
class TokenUsageService implements TokenUsageApi {
  TokenUsageService({CoreDatabase? coreDatabase})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance;

  final CoreDatabase _coreDatabase;

  /// 记录 Token 使用
  Future<void> recordUsage({
    required String assistantId,
    required String taskType,
    String? taskSubtype,
    required int inputTokens,
    required int outputTokens,
    int requestCount = 1,
    String? modelServiceId,
    String? model,
    String? protocolType,
    bool isEstimated = false,
    String? requestId,
    String? conversationId,
    String? messageId,
    String? jobId,
  }) async {
    final db = await _coreDatabase.open();
    final recordId = StableIdFactory.generate('token_usage');
    final totalTokens = inputTokens + outputTokens;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('token_usage_records', {
      'record_id': recordId,
      'assistant_id': assistantId,
      'task_type': taskType,
      'task_subtype': taskSubtype,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'total_tokens': totalTokens,
      'request_count': requestCount,
      'model_service_id': modelServiceId,
      'model': model,
      'protocol_type': protocolType,
      'is_estimated': isEstimated ? 1 : 0,
      'request_id': requestId,
      'conversation_id': conversationId,
      'message_id': messageId,
      'job_id': jobId,
      'created_at': now,
    });
  }

  @override
  Future<Map<String, dynamic>> getUsageOverview() async {
    final db = await _coreDatabase.open();
    final today = DateTime.now();
    final todayUtc = DateTime(
      today.year,
      today.month,
      today.day,
    ).toUtc().toIso8601String();
    final totals = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(request_count), 0) AS requests,
        COALESCE(SUM(total_tokens), 0) AS tokens,
        COALESCE(MAX(is_estimated), 0) AS has_estimated
      FROM token_usage_records
    ''')).single;
    final todayTotals = (await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(request_count), 0) AS requests,
        COALESCE(SUM(total_tokens), 0) AS tokens,
        COALESCE(MAX(is_estimated), 0) AS has_estimated
      FROM token_usage_records
      WHERE created_at >= ?
    ''',
      <Object?>[todayUtc],
    )).single;
    final models = await db.rawQuery('''
      SELECT
        CASE WHEN TRIM(COALESCE(model, '')) = '' THEN '未知模型' ELSE model END AS model,
        COALESCE(SUM(request_count), 0) AS requests,
        COALESCE(SUM(total_tokens), 0) AS tokens,
        COALESCE(MAX(is_estimated), 0) AS has_estimated
      FROM token_usage_records
      GROUP BY CASE WHEN TRIM(COALESCE(model, '')) = '' THEN '未知模型' ELSE model END
      ORDER BY tokens DESC, model ASC
    ''');
    return <String, dynamic>{
      'total_requests': totals['requests'] as int,
      'total_tokens': totals['tokens'] as int,
      'today_requests': todayTotals['requests'] as int,
      'today_tokens': todayTotals['tokens'] as int,
      'has_estimated': (totals['has_estimated'] as int) == 1,
      'today_has_estimated': (todayTotals['has_estimated'] as int) == 1,
      'by_model': models
          .map(
            (row) => <String, dynamic>{
              'model': row['model'],
              'requests': row['requests'],
              'tokens': row['tokens'],
              'estimated': (row['has_estimated'] as int) == 1,
            },
          )
          .toList(growable: false),
    };
  }

  /// 获取指定类型和时间范围的汇总统计
  @override
  Future<TokenUsageSummary> getSummaryByType({
    required String taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final db = await _coreDatabase.open();

    if (taskType == 'memory_rebuild') {
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];
      _appendMemoryUsageFilters(
        whereConditions: whereConditions,
        whereArgs: whereArgs,
        assistantId: assistantId,
        startTime: startTime,
        endTime: endTime,
      );
      final whereClause = whereConditions.isEmpty
          ? ''
          : 'WHERE ${whereConditions.join(' AND ')}';
      final result = await db.rawQuery('''
        SELECT
          COALESCE(SUM(u.prompt_tokens), 0) AS total_input,
          COALESCE(SUM(u.completion_tokens), 0) AS total_output,
          COALESCE(SUM(u.total_tokens), 0) AS total
        FROM memory_usage_records u
        JOIN memory_rebuild_jobs j ON j.run_id = u.run_id
        $whereClause
      ''', whereArgs);
      return _summaryFromRow(result.single);
    }

    final whereConditions = <String>['task_type = ?'];
    final whereArgs = <dynamic>[taskType];

    if (assistantId != null) {
      whereConditions.add('assistant_id = ?');
      whereArgs.add(assistantId);
    }

    if (startTime != null) {
      whereConditions.add('created_at >= ?');
      whereArgs.add(startTime.toUtc().toIso8601String());
    }

    if (endTime != null) {
      whereConditions.add('created_at <= ?');
      whereArgs.add(endTime.toUtc().toIso8601String());
    }

    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(input_tokens), 0) as total_input,
        COALESCE(SUM(output_tokens), 0) as total_output,
        COALESCE(SUM(total_tokens), 0) as total
      FROM token_usage_records
      WHERE ${whereConditions.join(' AND ')}
    ''', whereArgs);

    return _summaryFromRow(result.single);
  }

  /// 获取所有类型的总汇总统计
  @override
  Future<TokenUsageSummary> getTotalSummary({
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final db = await _coreDatabase.open();

    final whereConditions = <String>["task_type != 'memory_rebuild'"];
    final whereArgs = <dynamic>[];

    if (assistantId != null) {
      whereConditions.add('assistant_id = ?');
      whereArgs.add(assistantId);
    }

    if (startTime != null) {
      whereConditions.add('created_at >= ?');
      whereArgs.add(startTime.toUtc().toIso8601String());
    }

    if (endTime != null) {
      whereConditions.add('created_at <= ?');
      whereArgs.add(endTime.toUtc().toIso8601String());
    }

    final whereClause = whereConditions.isEmpty
        ? ''
        : 'WHERE ${whereConditions.join(' AND ')}';

    final regularResult = await db.rawQuery('''
      SELECT
        COALESCE(SUM(input_tokens), 0) AS total_input,
        COALESCE(SUM(output_tokens), 0) AS total_output,
        COALESCE(SUM(total_tokens), 0) AS total
      FROM token_usage_records
      $whereClause
    ''', whereArgs);
    final memoryConditions = <String>[];
    final memoryArgs = <dynamic>[];
    _appendMemoryUsageFilters(
      whereConditions: memoryConditions,
      whereArgs: memoryArgs,
      assistantId: assistantId,
      startTime: startTime,
      endTime: endTime,
    );
    final memoryWhereClause = memoryConditions.isEmpty
        ? ''
        : 'WHERE ${memoryConditions.join(' AND ')}';
    final memoryResult = await db.rawQuery('''
      SELECT
        COALESCE(SUM(u.prompt_tokens), 0) AS total_input,
        COALESCE(SUM(u.completion_tokens), 0) AS total_output,
        COALESCE(SUM(u.total_tokens), 0) AS total
      FROM memory_usage_records u
      JOIN memory_rebuild_jobs j ON j.run_id = u.run_id
      $memoryWhereClause
    ''', memoryArgs);
    return _combineSummaries(
      _summaryFromRow(regularResult.single),
      _summaryFromRow(memoryResult.single),
    );
  }

  /// 获取按日分组的数据（用于图表）
  @override
  Future<List<DailyTokenUsage>> getDailyUsageByType({
    required String taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final db = await _coreDatabase.open();

    if (taskType == 'memory_rebuild') {
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];
      _appendMemoryUsageFilters(
        whereConditions: whereConditions,
        whereArgs: whereArgs,
        assistantId: assistantId,
        startTime: startTime,
        endTime: endTime,
      );
      final whereClause = whereConditions.isEmpty
          ? ''
          : 'WHERE ${whereConditions.join(' AND ')}';
      final result = await db.rawQuery('''
        SELECT
          DATE(u.created_at) AS date,
          COALESCE(SUM(u.prompt_tokens), 0) AS total_input,
          COALESCE(SUM(u.completion_tokens), 0) AS total_output,
          COALESCE(SUM(u.total_tokens), 0) AS total
        FROM memory_usage_records u
        JOIN memory_rebuild_jobs j ON j.run_id = u.run_id
        $whereClause
        GROUP BY DATE(u.created_at)
        ORDER BY date ASC
      ''', whereArgs);
      return result.map(_dailyUsageFromRow).toList(growable: false);
    }

    final whereConditions = <String>['task_type = ?'];
    final whereArgs = <dynamic>[taskType];

    if (assistantId != null) {
      whereConditions.add('assistant_id = ?');
      whereArgs.add(assistantId);
    }

    if (startTime != null) {
      whereConditions.add('created_at >= ?');
      whereArgs.add(startTime.toUtc().toIso8601String());
    }

    if (endTime != null) {
      whereConditions.add('created_at <= ?');
      whereArgs.add(endTime.toUtc().toIso8601String());
    }

    final result = await db.rawQuery('''
      SELECT
        DATE(created_at) as date,
        COALESCE(SUM(input_tokens), 0) as total_input,
        COALESCE(SUM(output_tokens), 0) as total_output,
        COALESCE(SUM(total_tokens), 0) as total
      FROM token_usage_records
      WHERE ${whereConditions.join(' AND ')}
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    ''', whereArgs);

    return result.map(_dailyUsageFromRow).toList(growable: false);
  }

  /// 获取详细记录列表
  @override
  Future<List<TokenUsageRecord>> getDetailedRecords({
    String? taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _coreDatabase.open();

    if (taskType == 'memory_rebuild') {
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];
      _appendMemoryUsageFilters(
        whereConditions: whereConditions,
        whereArgs: whereArgs,
        assistantId: assistantId,
        startTime: startTime,
        endTime: endTime,
      );
      final whereClause = whereConditions.isEmpty
          ? ''
          : 'WHERE ${whereConditions.join(' AND ')}';
      final result = await db.rawQuery(
        '''
        SELECT
          u.usage_id AS record_id,
          j.assistant_id AS assistant_id,
          'memory_rebuild' AS task_type,
          CASE WHEN j.import_job_id IS NULL
            THEN 'memory_auto' ELSE 'memory_import' END AS task_subtype,
          u.prompt_tokens AS input_tokens,
          u.completion_tokens AS output_tokens,
          u.total_tokens AS total_tokens,
          NULL AS request_id,
          j.conversation_id AS conversation_id,
          NULL AS message_id,
          u.run_id AS job_id,
          u.created_at AS created_at
        FROM memory_usage_records u
        JOIN memory_rebuild_jobs j ON j.run_id = u.run_id
        $whereClause
        ORDER BY u.created_at DESC
        LIMIT ? OFFSET ?
      ''',
        [...whereArgs, limit, offset],
      );
      return result.map(TokenUsageRecord.fromMap).toList(growable: false);
    }

    final whereConditions = <String>[];
    final whereArgs = <dynamic>[];

    if (taskType != null) {
      whereConditions.add('task_type = ?');
      whereArgs.add(taskType);
    }

    if (assistantId != null) {
      whereConditions.add('assistant_id = ?');
      whereArgs.add(assistantId);
    }

    if (startTime != null) {
      whereConditions.add('created_at >= ?');
      whereArgs.add(startTime.toUtc().toIso8601String());
    }

    if (endTime != null) {
      whereConditions.add('created_at <= ?');
      whereArgs.add(endTime.toUtc().toIso8601String());
    }

    final whereClause = whereConditions.isEmpty
        ? ''
        : 'WHERE ${whereConditions.join(' AND ')}';

    final result = await db.rawQuery(
      '''
      SELECT *
      FROM token_usage_records
      $whereClause
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    ''',
      [...whereArgs, limit, offset],
    );

    return result.map((row) => TokenUsageRecord.fromMap(row)).toList();
  }

  static void _appendMemoryUsageFilters({
    required List<String> whereConditions,
    required List<dynamic> whereArgs,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    if (assistantId != null) {
      whereConditions.add('j.assistant_id = ?');
      whereArgs.add(assistantId);
    }
    if (startTime != null) {
      whereConditions.add('u.created_at >= ?');
      whereArgs.add(startTime.toUtc().toIso8601String());
    }
    if (endTime != null) {
      whereConditions.add('u.created_at <= ?');
      whereArgs.add(endTime.toUtc().toIso8601String());
    }
  }

  static TokenUsageSummary _summaryFromRow(Map<String, Object?> row) {
    return TokenUsageSummary(
      inputTokens: row['total_input'] as int,
      outputTokens: row['total_output'] as int,
      totalTokens: row['total'] as int,
    );
  }

  static TokenUsageSummary _combineSummaries(
    TokenUsageSummary first,
    TokenUsageSummary second,
  ) {
    return TokenUsageSummary(
      inputTokens: first.inputTokens + second.inputTokens,
      outputTokens: first.outputTokens + second.outputTokens,
      totalTokens: first.totalTokens + second.totalTokens,
    );
  }

  static DailyTokenUsage _dailyUsageFromRow(Map<String, Object?> row) {
    return DailyTokenUsage(
      date: DateTime.parse(row['date'] as String),
      inputTokens: row['total_input'] as int,
      outputTokens: row['total_output'] as int,
      totalTokens: row['total'] as int,
    );
  }
}
