import 'local_job.dart';

/// 通用任务执行器抽象。
///
/// 每个具体任务类型（chat_generation、memory_rebuild、tool_execution 等）
/// 应实现此接口，处理该类型任务的执行逻辑。
abstract class LocalJobHandler {
  /// 任务类型标识，用于注册到 Registry。
  String get taskType;

  /// 执行任务。
  ///
  /// [job] 当前任务状态
  /// [context] 执行上下文，提供 checkpoint 更新、取消检查等能力
  ///
  /// 正常完成返回 null，失败时抛出异常。
  Future<void> execute(LocalJob job, LocalJobContext context);
}

/// 任务执行上下文，提供给 Handler 使用。
abstract class LocalJobContext {
  /// 检查任务是否被请求取消。
  ///
  /// Handler 应在合适的时机检查此标志，如果为 true 则应尽快停止。
  Future<bool> get isCancelRequested;

  /// 检查任务是否被请求暂停。暂停与取消不同，已经保存的 checkpoint 会保留。
  Future<bool> get isPauseRequested;

  /// 当前执行是否应在安全点停止（取消或暂停）。
  Future<bool> get shouldStopRequested;

  /// 更新任务 checkpoint 和进度。
  ///
  /// [checkpoint] 新的 checkpoint 值
  /// [processedItems] 已处理项数（可选）
  /// [stage] 当前阶段描述（可选）
  Future<void> updateProgress({
    required int checkpoint,
    int? processedItems,
    String? stage,
  });

  /// 读取任务 payload（JSON 字符串）。
  String? get payload;

  /// 读取任务 scope。
  ({String? type, String? id})? get scope;
}
