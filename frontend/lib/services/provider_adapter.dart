import 'package:dio/dio.dart';

import 'model_capability_probe.dart';
import 'model_discovery_result.dart';
import 'model_endpoint.dart';
import 'provider_definition.dart';
import 'provider_adapters/adapter_helpers.dart';
import 'provider_adapters/adapter_registry.dart';

/// 明显非聊天的模型 ID 关键词（黑名单，命中即过滤）。
///
/// 覆盖：向量（embedding）、重排（rerank）、语音合成/识别（tts/asr/whisper）、
/// 图像生成、视频生成、内容审核、相似度。谨慎起见不放 `image`/`vision`/`audio`
/// 这类可能误伤视觉/多模态理解模型的关键词。
const List<String> nonChatModelKeywords = [
  'embedding',
  'rerank',
  're-rank',
  'tts',
  'text-to-speech',
  'speech-to-text',
  'asr',
  'whisper',
  'dall-e',
  'dall.e',
  'imagen',
  'image-generation',
  'text-to-image',
  'text2image',
  'video-generation',
  'text-to-video',
  'sora',
  'moderation',
  'similarity',
];

/// 过滤非聊天模型，返回新的列表。
List<String> filterNonChatModels(Iterable<String> ids) => ids.where((id) {
  final lower = id.toLowerCase();
  return !nonChatModelKeywords.any(lower.contains);
}).toList();

/// 官方服务商适配器：接管模型发现、非聊天模型过滤与 Key 验证。
///
/// 精简原则：官方十家全走 OpenAI Chat 单协议。有 `/models` 的 provider
/// 动态发现，无 `/models` 的返回空列表由 UI 引导手填模型 ID。
class ProviderAdapter {
  ProviderAdapter(this.definition, {Dio? dio}) : _dio = dio ?? Dio();

  final ProviderDefinition definition;
  final Dio _dio;

  /// 拉取当前 provider 的模型列表并过滤非聊天模型，按 id 排序。
  ///
  /// - 返回 ModelDiscoveryResult，包含模型 ID 和可选的官方能力元数据。
  /// - 无 `/models` 的官方 provider 返回空列表（UI 引导手填）。
  /// - 401/403 → 认证失败；429 → 额度不足或请求受限；网络/DNS/TLS → 连接失败。
  Future<List<ModelDiscoveryResult>> discoverModels(String apiKey) async {
    if (!definition.hasModelDiscovery) return const [];
    final protocolAdapter = AdapterRegistry.instance.get(definition.protocol);
    final endpoint = joinEndpoint(definition.baseUrl, definition.modelsPath);
    try {
      final response = await _dio.get<dynamic>(
        endpoint,
        options: Options(
          headers: protocolAdapter.headers(definition.baseUrl, apiKey),
        ),
      );
      final payload = response.data;
      if (payload is! Map) return const [];
      final raw = payload['data'] as List? ?? const [];
      final results = <ModelDiscoveryResult>[];

      for (final item in raw.whereType<Map>()) {
        final id = item['id'];
        if (id is! String || id.isEmpty) continue;

        // 过滤非聊天模型
        final lower = id.toLowerCase();
        if (nonChatModelKeywords.any(lower.contains)) continue;

        // 解析官方能力元数据（Kimi 特殊处理）
        Map<String, ModelCapabilityVerdict>? capabilities;
        if (definition.id == 'kimi') {
          capabilities = _parseKimiCapabilities(item);
        }

        results.add(ModelDiscoveryResult(id: id, capabilities: capabilities));
      }

      results.sort((a, b) => a.id.compareTo(b.id));
      return results;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == null) {
        throw const ModelEndpointException('无法连接模型服务，请检查 API 地址和手机网络');
      }
      final normalized = normalizeHttpError(
        statusCode,
        error.response?.data,
        '模型服务请求失败',
      );
      if (normalized.code == 'RATE_LIMITED') {
        throw const ModelEndpointException('额度不足或请求受限，请检查账户额度');
      }
      throw ModelEndpointException(normalized.message);
    }
  }

  /// 解析 Kimi 官方模型列表响应中的能力元数据。
  Map<String, ModelCapabilityVerdict>? _parseKimiCapabilities(Map item) {
    final capabilities = <String, ModelCapabilityVerdict>{};

    // Kimi 官方文档：supports_image_in, supports_reasoning 等
    if (item['supports_image_in'] == true) {
      capabilities['vision_input'] = ModelCapabilityVerdict.supported;
    }
    if (item['supports_function_call'] == true) {
      capabilities['client_tool_calling'] = ModelCapabilityVerdict.supported;
    }
    // Kimi 不返回 streaming/text/structured 元数据，留给下游判断

    return capabilities.isEmpty ? null : capabilities;
  }
}
