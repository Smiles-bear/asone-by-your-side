import 'local_job_handler.dart';

/// 任务类型 → Handler 注册表。
///
/// 避免把各种业务任务写成 LocalJobService 内的大量 if/else。
class LocalJobRegistry {
  LocalJobRegistry._();

  /// 独立核心（如社区版）可持有自己的任务处理器集合，避免污染宿主单例。
  factory LocalJobRegistry.create() => LocalJobRegistry._();

  static final LocalJobRegistry instance = LocalJobRegistry._();

  final Map<String, LocalJobHandler> _handlers = {};

  /// 注册 Handler。
  void register(LocalJobHandler handler) {
    if (_handlers.containsKey(handler.taskType)) {
      throw StateError('Handler for ${handler.taskType} already registered');
    }
    _handlers[handler.taskType] = handler;
  }

  /// 获取 Handler。
  ///
  /// 返回 null 表示未注册该类型。
  LocalJobHandler? getHandler(String taskType) => _handlers[taskType];

  /// 取消注册（主要用于测试）。
  void unregister(String taskType) {
    _handlers.remove(taskType);
  }

  /// 清空所有注册（主要用于测试）。
  void clear() {
    _handlers.clear();
  }
}
