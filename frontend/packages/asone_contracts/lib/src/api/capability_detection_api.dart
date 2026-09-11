import '../models/model_capability.dart';

/// 一次能力检测会话的公开面：进度回调、执行、取消与结论读取。
///
/// 具体会话（真实探针编排或演示实现）由各版本自行提供。
abstract interface class CapabilityDetectionSessionApi {
  /// 进度回调：(已完成数, 总数, 当前项标签)。
  set onProgress(
    void Function(int completed, int total, String label)? handler,
  );

  /// 执行检测；返回各项结果。取消或基础文本不可用时返回 null。
  Future<List<ModelCapabilityProbeResult>?> run();

  /// 取消会话；迟到响应将被丢弃。
  void cancel();

  bool get isCancelled;
  bool get isCancelledByUser;
  bool get isCompleted;

  /// 未完成原因（面向用户的中文文案）。
  String? get failureMessage;

  /// 未完成时停在的检测项标签。
  String? get failureLabel;

  /// 检测中实际解析出的协议名（未解析时为空字符串）。
  String get resolvedProtocol;
}

/// 模型能力检测契约：创建会话、保存能力快照、单项快速测试。
abstract interface class CapabilityDetectionApi {
  /// 创建一次能力检测会话（渐进式 + 可取消）。
  ///
  /// 支持两种模式：
  /// 1. serviceId 模式（编辑页重新检测）：传入 [serviceId]
  /// 2. configData 模式（新建配置）：传入 [configData]，检测前不写数据库
  Future<CapabilityDetectionSessionApi> createCapabilityDetectionSession({
    String? serviceId,
    Map<String, dynamic>? configData,
    Map<String, String>? discoveryCapabilities,
  });

  /// 保存能力快照：新建模式首次保存配置+能力，编辑模式只保存能力。
  Future<bool> saveCapabilitySnapshot({
    String? serviceId,
    Map<String, dynamic>? configData,
    required List<ModelCapabilityProbeResult> results,
    required String resolvedProtocol,
  });

  /// 单项快速测试：文本/视觉/音频/工具/流式/结构化。
  ///
  /// 只有明确结论才更新对应能力，不清空其他。
  Future<Map<String, dynamic>> quickTestCapability(
    String serviceId,
    String capability,
  );
}
