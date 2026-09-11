import 'model_capability_probe.dart';

/// 模型发现结果：模型 ID + 可选的官方能力元数据。
class ModelDiscoveryResult {
  const ModelDiscoveryResult({required this.id, this.capabilities});

  final String id;

  /// 官方模型列表响应中的能力元数据（优先级最高）。
  /// 例如 Kimi 的 supports_image_in、supports_reasoning。
  final Map<String, ModelCapabilityVerdict>? capabilities;

  bool get hasCapabilityMetadata =>
      capabilities != null && capabilities!.isNotEmpty;
}
