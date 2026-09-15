import 'provider_registry.dart';
import 'provider_adapters/protocol_types.dart';

class OfficialModelTokenLimits {
  const OfficialModelTokenLimits({
    required this.providerId,
    required this.modelId,
    required this.contextWindow,
    this.maxOutputTokens,
    this.maxInputTokens,
  });

  final String providerId;
  final String modelId;
  final int contextWindow;

  /// null 表示官方未公开独立固定上限，或输出只受剩余上下文约束。
  final int? maxOutputTokens;

  /// 部分厂商在总上下文之外另设最大输入限制。
  final int? maxInputTokens;
}

/// 官方域名与精确模型 ID 同时命中时，提供可核实的 Token 限额。
/// 未知型号、别名、中转站和自定义地址一律返回 null。
abstract final class OfficialModelTokenLimitCatalog {
  static const int _k = 1024;

  static const Map<String, Map<String, OfficialModelTokenLimits>> _catalog = {
    'deepseek': {
      'deepseek-v4-pro': OfficialModelTokenLimits(
        providerId: 'deepseek',
        modelId: 'deepseek-v4-pro',
        contextWindow: 1000000,
        maxOutputTokens: 384 * _k,
      ),
      'deepseek-v4-flash': OfficialModelTokenLimits(
        providerId: 'deepseek',
        modelId: 'deepseek-v4-flash',
        contextWindow: 1000000,
        maxOutputTokens: 384 * _k,
      ),
    },
    'kimi': {
      'kimi-k3': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'kimi-k3',
        contextWindow: 1048576,
      ),
      'kimi-k2.7-code': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'kimi-k2.7-code',
        contextWindow: 262144,
      ),
      'kimi-k2.7-code-highspeed': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'kimi-k2.7-code-highspeed',
        contextWindow: 262144,
      ),
      'kimi-k2.6': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'kimi-k2.6',
        contextWindow: 256 * _k,
      ),
      'kimi-k2.5': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'kimi-k2.5',
        contextWindow: 256 * _k,
      ),
      'moonshot-v1-128k': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'moonshot-v1-128k',
        contextWindow: 128 * _k,
      ),
      'moonshot-v1-32k': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'moonshot-v1-32k',
        contextWindow: 32 * _k,
      ),
      'moonshot-v1-8k': OfficialModelTokenLimits(
        providerId: 'kimi',
        modelId: 'moonshot-v1-8k',
        contextWindow: 8 * _k,
      ),
    },
    'glm': {
      'glm-5.2': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-5.2',
        contextWindow: 1000000,
        maxOutputTokens: 128 * _k,
      ),
      'glm-5.1': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-5.1',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-5': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-5',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-5-turbo': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-5-Turbo',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-4.7': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4.7',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-4.7-flashx': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4.7-FlashX',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-4.7-flash': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4.7-Flash',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-4.6': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4.6',
        contextWindow: 200 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'glm-4.5-air': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4.5-Air',
        contextWindow: 128 * _k,
        maxOutputTokens: 96 * _k,
      ),
      'glm-4.5-airx': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4.5-AirX',
        contextWindow: 128 * _k,
        maxOutputTokens: 96 * _k,
      ),
      'glm-4-long': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4-Long',
        contextWindow: 1000000,
        maxOutputTokens: 4 * _k,
      ),
      'glm-4-flashx-250414': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4-FlashX-250414',
        contextWindow: 128 * _k,
        maxOutputTokens: 16 * _k,
      ),
      'glm-4-flash-250414': OfficialModelTokenLimits(
        providerId: 'glm',
        modelId: 'GLM-4-Flash-250414',
        contextWindow: 128 * _k,
        maxOutputTokens: 16 * _k,
      ),
    },
    'qwen': {
      'qwen3.8-max': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3.8-max',
        contextWindow: 1000000,
        maxOutputTokens: 131072,
      ),
      'qwen3.8-2.4t-a95b': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3.8-2.4t-a95b',
        contextWindow: 1000000,
        maxOutputTokens: 131072,
      ),
      'qwen3.8-27b': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3.8-27b',
        contextWindow: 1000000,
        maxOutputTokens: 131072,
      ),
      'qwen3.7-max': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3.7-max',
        contextWindow: 1000000,
        maxOutputTokens: 131072,
      ),
      'qwen3.7-plus': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3.7-plus',
        contextWindow: 1000000,
        maxOutputTokens: 131072,
      ),
      'qwen3.7-flash': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3.7-flash',
        contextWindow: 1000000,
        maxOutputTokens: 131072,
      ),
      'qwen3-max': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen3-max',
        contextWindow: 262144,
        maxOutputTokens: 32768,
      ),
      'qwen-plus': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen-plus',
        contextWindow: 1000000,
        maxOutputTokens: 32768,
      ),
      'qwen-flash': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen-flash',
        contextWindow: 1000000,
        maxOutputTokens: 32768,
      ),
      'qwen-plus-character': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen-plus-character',
        contextWindow: 32768,
        maxOutputTokens: 4096,
      ),
      'qwen-flash-character': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen-flash-character',
        contextWindow: 8192,
        maxOutputTokens: 4096,
      ),
      'qwen-flash-character-2026-02-26': OfficialModelTokenLimits(
        providerId: 'qwen',
        modelId: 'qwen-flash-character-2026-02-26',
        contextWindow: 262144,
        maxOutputTokens: 32768,
      ),
    },
    'doubao': {
      'doubao-seed-2.0-pro': OfficialModelTokenLimits(
        providerId: 'doubao',
        modelId: 'doubao-seed-2.0-pro',
        contextWindow: 256 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'doubao-seed-2.0-lite': OfficialModelTokenLimits(
        providerId: 'doubao',
        modelId: 'doubao-seed-2.0-lite',
        contextWindow: 256 * _k,
        maxOutputTokens: 128 * _k,
      ),
      'doubao-seed-2.0-code': OfficialModelTokenLimits(
        providerId: 'doubao',
        modelId: 'doubao-seed-2.0-code',
        contextWindow: 256 * _k,
        maxOutputTokens: 128 * _k,
      ),
    },
    'minimax': {
      'minimax-m3': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M3',
        contextWindow: 1000000,
        maxOutputTokens: 524288,
      ),
      'minimax-m2.7': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2.7',
        contextWindow: 204800,
        maxOutputTokens: 204800,
      ),
      'minimax-m2.7-highspeed': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2.7-highspeed',
        contextWindow: 204800,
        maxOutputTokens: 204800,
      ),
      'minimax-m2.5': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2.5',
        contextWindow: 204800,
        maxOutputTokens: 204800,
      ),
      'minimax-m2.5-highspeed': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2.5-highspeed',
        contextWindow: 204800,
        maxOutputTokens: 204800,
      ),
      'minimax-m2.1': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2.1',
        contextWindow: 204800,
        maxOutputTokens: 204800,
      ),
      'minimax-m2.1-highspeed': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2.1-highspeed',
        contextWindow: 204800,
        maxOutputTokens: 204800,
      ),
      'minimax-m2': OfficialModelTokenLimits(
        providerId: 'minimax',
        modelId: 'MiniMax-M2',
        contextWindow: 204800,
        maxOutputTokens: 128 * _k,
      ),
    },
    'hunyuan': {
      'hy3': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hy3',
        contextWindow: 256 * _k,
        maxOutputTokens: 128 * _k,
        maxInputTokens: 192 * _k,
      ),
      'hy3-preview': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hy3-preview',
        contextWindow: 256 * _k,
        maxOutputTokens: 128 * _k,
        maxInputTokens: 192 * _k,
      ),
      'hy-mt2-pro': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hy-mt2-pro',
        contextWindow: 8 * _k,
        maxOutputTokens: 4 * _k,
      ),
      'hy-mt2-plus': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hy-mt2-plus',
        contextWindow: 8 * _k,
        maxOutputTokens: 4 * _k,
      ),
      'hy-mt2-lite': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hy-mt2-lite',
        contextWindow: 8 * _k,
        maxOutputTokens: 4 * _k,
      ),
      'hunyuan-role-latest': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hunyuan-role-latest',
        contextWindow: 32 * _k,
        maxOutputTokens: 4 * _k,
        maxInputTokens: 28 * _k,
      ),
      'hy-role': OfficialModelTokenLimits(
        providerId: 'hunyuan',
        modelId: 'hy-role',
        contextWindow: 32 * _k,
        maxOutputTokens: 4 * _k,
        maxInputTokens: 28 * _k,
      ),
    },
    'wenxin': {
      'ernie-5.1': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-5.1',
        contextWindow: 128 * _k,
        maxOutputTokens: 65536,
        maxInputTokens: 119 * _k,
      ),
      'ernie-5.0': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-5.0',
        contextWindow: 128 * _k,
        maxOutputTokens: 65536,
        maxInputTokens: 119 * _k,
      ),
      'ernie-5.0-thinking-preview': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-5.0-thinking-preview',
        contextWindow: 128 * _k,
        maxOutputTokens: 65536,
        maxInputTokens: 119 * _k,
      ),
      'ernie-4.5-turbo-128k-preview': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.5-turbo-128k-preview',
        contextWindow: 128 * _k,
        maxOutputTokens: 12288,
      ),
      'ernie-4.5-21b-a3b': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.5-21b-a3b',
        contextWindow: 128 * _k,
        maxOutputTokens: 12288,
      ),
      'ernie-4.5-21b-a3b-thinking': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.5-21b-a3b-thinking',
        contextWindow: 128 * _k,
        maxOutputTokens: 32768,
      ),
      'ernie-4.5-0.3b': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.5-0.3b',
        contextWindow: 128 * _k,
        maxOutputTokens: 12288,
      ),
      'ernie-x1.1-preview': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-x1.1-preview',
        contextWindow: 64 * _k,
        maxOutputTokens: 65536,
      ),
      'ernie-x1-turbo-32k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-x1-turbo-32k',
        contextWindow: 32 * _k,
        maxOutputTokens: 16384,
      ),
      'ernie-4.0-turbo-128k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.0-turbo-128k',
        contextWindow: 128 * _k,
        maxOutputTokens: 4096,
      ),
      'ernie-4.0-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.0-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
      'ernie-4.0-turbo-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-4.0-turbo-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
      'ernie-3.5-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-3.5-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
      'ernie-char-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-char-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
      'ernie-speed-128k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-speed-128k',
        contextWindow: 128 * _k,
        maxOutputTokens: 4096,
      ),
      'ernie-speed-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-speed-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
      'ernie-tiny-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-tiny-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
      'ernie-lite-8k': OfficialModelTokenLimits(
        providerId: 'wenxin',
        modelId: 'ernie-lite-8k',
        contextWindow: 8 * _k,
        maxOutputTokens: 2048,
      ),
    },
    'spark': {
      'spark-x2-agent': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: 'Spark-X2-Agent',
        contextWindow: 256 * _k,
      ),
      'spark-x2': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: 'Spark-X2',
        contextWindow: 192 * _k,
        maxOutputTokens: 128 * _k,
        maxInputTokens: 64 * _k,
      ),
      'spark-x2-flash': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: 'Spark-X2-Flash',
        contextWindow: 256 * _k,
        maxOutputTokens: 262144,
      ),
      '4.0 ultra': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: '4.0 Ultra',
        contextWindow: 32 * _k,
        maxOutputTokens: 32 * _k,
      ),
      'pro-128k': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: 'Pro-128K',
        contextWindow: 128 * _k,
        maxOutputTokens: 32 * _k,
      ),
      'pro': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: 'Pro',
        contextWindow: 8 * _k,
        maxOutputTokens: 8 * _k,
      ),
      'lite': OfficialModelTokenLimits(
        providerId: 'spark',
        modelId: 'Lite',
        contextWindow: 8 * _k,
        maxOutputTokens: 4 * _k,
      ),
    },
    'step': {
      'step 3.7 flash': OfficialModelTokenLimits(
        providerId: 'step',
        modelId: 'Step 3.7 Flash',
        contextWindow: 256 * _k,
      ),
      'step 3.5 flash 2603': OfficialModelTokenLimits(
        providerId: 'step',
        modelId: 'Step 3.5 Flash 2603',
        contextWindow: 256 * _k,
      ),
      'step 3.5 flash': OfficialModelTokenLimits(
        providerId: 'step',
        modelId: 'Step 3.5 Flash',
        contextWindow: 256 * _k,
      ),
      'step-1o turbo vision': OfficialModelTokenLimits(
        providerId: 'step',
        modelId: 'Step-1o Turbo Vision',
        contextWindow: 32 * _k,
      ),
    },
  };

  static OfficialModelTokenLimits? match({
    required String baseUrl,
    required String model,
    required String protocolType,
  }) {
    if (protocolType != ProtocolType.auto &&
        protocolType != ProtocolType.openaiChat) {
      return null;
    }
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') return null;
    final provider = ProviderRegistry.instance.matchByHost(uri.host);
    if (provider == null || provider.isCustom) return null;
    return _catalog[provider.id]?[_normalizeModelId(model)];
  }

  static String _normalizeModelId(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
