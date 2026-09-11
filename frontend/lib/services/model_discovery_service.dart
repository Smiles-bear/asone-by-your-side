import 'package:asone_contracts/asone_contracts.dart'
    show ModelDiscoveryApi, ProtocolType;
import 'package:dio/dio.dart';

import 'model_endpoint.dart';
import 'provider_adapter.dart';
import 'provider_registry.dart';
import 'provider_adapters/adapter_registry.dart';

/// 模型发现服务：按提供商或凭据发起真实网络探测，返回可用模型列表。
///
/// 零闭源依赖的公开子集实现（实现公开契约 [ModelDiscoveryApi]），
/// 方法体自 ApiService 逐字提取；ApiService 对应方法委托本类。
class ModelDiscoveryService implements ModelDiscoveryApi {
  ModelDiscoveryService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
            ),
          );

  final Dio _dio;

  /// 按 provider_id 发现模型列表（官方预置走 ProviderAdapter，返回模型及能力元数据）。
  @override
  Future<List<Map<String, dynamic>>> discoverProviderModels(
    String providerId,
    String apiKey,
  ) async {
    final definition = ProviderRegistry.instance.get(providerId);
    final results = await ProviderAdapter(
      definition,
      dio: _dio,
    ).discoverModels(apiKey);
    return results
        .map(
          (r) => {
            'id': r.id,
            if (r.capabilities != null)
              'capabilities': r.capabilities!.map(
                (k, v) => MapEntry(k, v.name),
              ),
          },
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> discoverModelsWithCredentials({
    required String baseUrl,
    required String apiKey,
    String protocolType = ProtocolType.auto,
  }) async {
    final protocols = protocolType == ProtocolType.auto
        ? ProtocolType.autoCandidates
        : [protocolType];
    DioException? lastError;
    var receivedReadablePayload = false;

    for (final protocol in protocols) {
      final adapter = AdapterRegistry.instance.get(protocol);
      final endpoints = protocol == ProtocolType.anthropicMessages
          ? {
              modelEndpointUri(baseUrl, 'v1/models').toString(),
              modelEndpointUri(baseUrl, 'models').toString(),
            }
          : {modelEndpointUri(baseUrl, 'models').toString()};
      for (final endpoint in endpoints) {
        try {
          final response = await _dio.get<dynamic>(
            endpoint,
            options: Options(headers: adapter.headers(baseUrl, apiKey)),
          );
          final payload = response.data;
          if (payload is! Map) continue;
          receivedReadablePayload = true;
          final rawModels = protocol == ProtocolType.gemini
              ? (payload['models'] as List? ?? const [])
              : (payload['data'] as List? ?? const []);
          final models = rawModels
              .whereType<Map>()
              .where((raw) {
                if (protocol != ProtocolType.gemini) return true;
                final methods = raw['supportedGenerationMethods'];
                return methods is! List || methods.contains('generateContent');
              })
              .map((raw) {
                final item = raw.cast<String, dynamic>();
                final rawId = item['id'] ?? item['name'];
                final id = rawId?.toString().replaceFirst(
                  RegExp(r'^models/'),
                  '',
                );
                return {...item, if (id != null && id.isNotEmpty) 'id': id};
              })
              .where((item) => (item['id'] as String?)?.isNotEmpty == true)
              .toList();
          if (models.isNotEmpty) {
            models.sort(
              (a, b) => (a['id'] as String).compareTo(b['id'] as String),
            );
            return models;
          }
        } on DioException catch (error) {
          lastError = error;
        }
      }
    }

    if (receivedReadablePayload) return const [];
    final statusCode = lastError?.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      throw const ModelEndpointException('认证失败，请检查 API Key');
    }
    if (statusCode != null) {
      throw ModelEndpointException('模型服务请求失败（HTTP $statusCode）');
    }
    throw const ModelEndpointException('无法连接模型服务，请检查 API 地址和手机网络');
  }
}
