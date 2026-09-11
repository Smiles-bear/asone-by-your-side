import '../models/protocol_type.dart';

/// 模型发现能力契约。
///
/// 真实实现按提供商或凭据发起网络探测；演示实现返回固定演示条目。
abstract interface class ModelDiscoveryApi {
  /// 按 provider_id 发现模型列表（官方预置走提供商适配器，返回模型及能力元数据）。
  ///
  /// 返回条目形如 `{'id': ..., 'capabilities': {...}?}`。
  Future<List<Map<String, dynamic>>> discoverProviderModels(
    String providerId,
    String apiKey,
  );

  /// 按凭据（基础地址 + API Key）发现模型列表；[protocolType] 为
  /// [ProtocolType.auto] 时按候选顺序自动识别协议。
  Future<List<Map<String, dynamic>>> discoverModelsWithCredentials({
    required String baseUrl,
    required String apiKey,
    String protocolType = ProtocolType.auto,
  });
}
