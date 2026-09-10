import '../models/token_usage.dart';

/// Public read-only contract for token usage statistics.
abstract interface class TokenUsageApi {
  Future<Map<String, dynamic>> getUsageOverview();

  Future<TokenUsageSummary> getSummaryByType({
    required String taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  });

  Future<TokenUsageSummary> getTotalSummary({
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  });

  Future<List<DailyTokenUsage>> getDailyUsageByType({
    required String taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
  });

  Future<List<TokenUsageRecord>> getDetailedRecords({
    String? taskType,
    String? assistantId,
    DateTime? startTime,
    DateTime? endTime,
    int limit = 50,
    int offset = 0,
  });
}
