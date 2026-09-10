import 'package:asone_contracts/asone_contracts.dart';

/// In-memory [TokenUsageApi] implementation (read-only statistics).
///
/// 演示版无记忆域：taskType 'memory_rebuild' 返回零值/空列表。
class DemoTokenUsageStore implements TokenUsageApi {
  DemoTokenUsageStore({List<Map<String, dynamic>>? seed}) : _rows = [...?seed];

  final List<Map<String, dynamic>> _rows;

  Iterable<Map<String, dynamic>> _filter({
    String? taskType,
    bool excludeMemoryRebuild = false,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) sync* {
    for (final row in _rows) {
      if (taskType != null && row['task_type'] != taskType) continue;
      if (excludeMemoryRebuild && row['task_type'] == 'memory_rebuild') {
        continue;
      }
      if (assistantId != null && row['assistant_id'] != assistantId) continue;
      final createdAt = DateTime.parse(row['created_at'] as String);
      if (startTime != null && createdAt.isBefore(startTime)) continue;
      if (endTime != null && createdAt.isAfter(endTime)) continue;
      yield row;
    }
  }

  TokenUsageSummary _sum(Iterable<Map<String, dynamic>> rows) {
    var input = 0;
    var output = 0;
    var total = 0;
    for (final row in rows) {
      input += (row['input_tokens'] as num?)?.toInt() ?? 0;
      output += (row['output_tokens'] as num?)?.toInt() ?? 0;
      total += (row['total_tokens'] as num?)?.toInt() ?? 0;
    }
    return TokenUsageSummary(
      inputTokens: input,
      outputTokens: output,
      totalTokens: total,
    );
  }

  @override
  Future<Map<String, dynamic>> getUsageOverview() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final all = _rows.toList();
    final todayRows = _filter(startTime: todayStart).toList();

    int requestsOf(List<Map<String, dynamic>> rows) {
      var sum = 0;
      for (final row in rows) {
        sum += (row['request_count'] as num?)?.toInt() ?? 0;
      }
      return sum;
    }

    int tokensOf(List<Map<String, dynamic>> rows) {
      var sum = 0;
      for (final row in rows) {
        sum += (row['total_tokens'] as num?)?.toInt() ?? 0;
      }
      return sum;
    }

    bool estimatedOf(List<Map<String, dynamic>> rows) =>
        rows.any((row) => row['is_estimated'] == 1);

    final byModel = <String, Map<String, Object?>>{};
    for (final row in all) {
      final rawModel = (row['model'] as String? ?? '').trim();
      final model = rawModel.isEmpty ? '未知模型' : rawModel;
      final entry = byModel.putIfAbsent(
        model,
        () => <String, Object?>{
          'model': model,
          'requests': 0,
          'tokens': 0,
          'estimated': false,
        },
      );
      entry['requests'] =
          (entry['requests']! as int) +
          ((row['request_count'] as num?)?.toInt() ?? 0);
      entry['tokens'] =
          (entry['tokens']! as int) +
          ((row['total_tokens'] as num?)?.toInt() ?? 0);
      entry['estimated'] =
          (entry['estimated']! as bool) || row['is_estimated'] == 1;
    }
    final modelList = byModel.values.toList()
      ..sort((a, b) {
        final byTokens = (b['tokens']! as int).compareTo(a['tokens']! as int);
        if (byTokens != 0) return byTokens;
        return (a['model']! as String).compareTo(b['model']! as String);
      });

    return <String, dynamic>{
      'total_requests': requestsOf(all),
      'total_tokens': tokensOf(all),
      'today_requests': requestsOf(todayRows),
      'today_tokens': tokensOf(todayRows),
      'has_estimated': estimatedOf(all),
      'today_has_estimated': estimatedOf(todayRows),
      'by_model': modelList,
    };
  }

  @override
  Future<TokenUsageSummary> getSummaryByType({
    required String taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (taskType == 'memory_rebuild') {
      return TokenUsageSummary(inputTokens: 0, outputTokens: 0, totalTokens: 0);
    }
    return _sum(
      _filter(
        taskType: taskType,
        assistantId: assistantId,
        startTime: startTime,
        endTime: endTime,
      ),
    );
  }

  @override
  Future<TokenUsageSummary> getTotalSummary({
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) async => _sum(
    _filter(
      excludeMemoryRebuild: true,
      assistantId: assistantId,
      startTime: startTime,
      endTime: endTime,
    ),
  );

  @override
  Future<List<DailyTokenUsage>> getDailyUsageByType({
    required String taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (taskType == 'memory_rebuild') return const [];
    final byDate = <DateTime, List<int>>{};
    for (final row in _filter(
      taskType: taskType,
      assistantId: assistantId,
      startTime: startTime,
      endTime: endTime,
    )) {
      final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final bucket = byDate.putIfAbsent(day, () => <int>[0, 0, 0]);
      bucket[0] += (row['input_tokens'] as num?)?.toInt() ?? 0;
      bucket[1] += (row['output_tokens'] as num?)?.toInt() ?? 0;
      bucket[2] += (row['total_tokens'] as num?)?.toInt() ?? 0;
    }
    final days = byDate.keys.toList()..sort();
    return [
      for (final day in days)
        DailyTokenUsage(
          date: day,
          inputTokens: byDate[day]![0],
          outputTokens: byDate[day]![1],
          totalTokens: byDate[day]![2],
        ),
    ];
  }

  @override
  Future<List<TokenUsageRecord>> getDetailedRecords({
    String? taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows =
        _filter(
          taskType: taskType,
          assistantId: assistantId,
          startTime: startTime,
          endTime: endTime,
        ).toList()..sort(
          (a, b) => DateTime.parse(
            b['created_at'] as String,
          ).compareTo(DateTime.parse(a['created_at'] as String)),
        );
    return rows
        .skip(offset)
        .take(limit)
        .map((row) => TokenUsageRecord.fromMap(row))
        .toList();
  }
}
