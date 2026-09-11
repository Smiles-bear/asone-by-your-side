import 'package:asone_contracts/asone_contracts.dart';

/// 演示版模型发现：不发起真实网络请求，返回固定演示模型条目。
///
/// 社区演示版不连接真实模型服务；需要真实探测的宿主应挂载
/// [ModelDiscoveryApi] 的真实实现。
class DemoModelDiscovery implements ModelDiscoveryApi {
  const DemoModelDiscovery();

  static const List<Map<String, dynamic>> _demoModels = [
    {'id': 'demo-model-standard'},
    {'id': 'demo-model-lite'},
  ];

  @override
  Future<List<Map<String, dynamic>>> discoverProviderModels(
    String providerId,
    String apiKey,
  ) async => List.of(_demoModels);

  @override
  Future<List<Map<String, dynamic>>> discoverModelsWithCredentials({
    required String baseUrl,
    required String apiKey,
    String protocolType = ProtocolType.auto,
  }) async => List.of(_demoModels);
}
