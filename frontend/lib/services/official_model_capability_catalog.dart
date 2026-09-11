import '../models/model_service.dart';

/// 只有“官方域名 + 明确模型 ID”同时匹配时，才使用官方能力资料。
/// 中转站、自定义域名和未知模型一律不猜，继续执行真实能力探针。
class OfficialModelCapabilityProfile {
  const OfficialModelCapabilityProfile({
    required this.provider,
    required this.protocol,
    required this.verdicts,
    required this.availabilityPayloadOverrides,
    required this.sourceDescription,
  });

  final String provider;
  final String protocol;
  final Map<String, ModelCapabilityVerdict> verdicts;
  final Map<String, Object?> availabilityPayloadOverrides;
  final String sourceDescription;
}

abstract final class OfficialModelCapabilityCatalog {
  static const _deepSeekV4Models = {'deepseek-v4-flash', 'deepseek-v4-pro'};

  static OfficialModelCapabilityProfile? match(ModelService service) {
    final uri = Uri.tryParse(service.baseUrl.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') return null;

    final host = uri.host.toLowerCase();
    final model = service.model.trim().toLowerCase();
    if (host == 'api.deepseek.com' && _deepSeekV4Models.contains(model)) {
      return const OfficialModelCapabilityProfile(
        provider: 'DeepSeek',
        protocol: ProtocolType.openaiChat,
        verdicts: {
          'text_chat': ModelCapabilityVerdict.supported,
          'streaming': ModelCapabilityVerdict.supported,
          'vision_input': ModelCapabilityVerdict.unsupported,
          'audio_input': ModelCapabilityVerdict.unsupported,
          'client_tool_calling': ModelCapabilityVerdict.supported,
          'structured_output': ModelCapabilityVerdict.supported,
        },
        // DeepSeek V4 默认开启思考。可用性检查只需验证流式正文，
        // 显式关闭思考，避免推理 token 吃完 max_tokens 后正文为空。
        availabilityPayloadOverrides: {
          'thinking': {'type': 'disabled'},
        },
        sourceDescription: 'DeepSeek 官方模型能力资料',
      );
    }
    return null;
  }
}
