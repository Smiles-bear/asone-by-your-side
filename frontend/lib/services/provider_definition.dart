import 'provider_adapters/protocol_types.dart';

/// 官方服务商声明式配置。
///
/// 精简原则（2026-08-16 姐姐拍板）：官方十家全走 OpenAI Chat 单协议；
/// 冷门协议（Anthropic/Gemini）留给「自定义」auto 识别；不维护静态模型清单；
/// 能力靠真实验证 + `official_model_capability_catalog.dart` 里的硬编码
/// 「官方明确不支持」白名单兜底。
class ProviderDefinition {
  const ProviderDefinition({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    this.hosts = const [],
    this.hostSuffixes = const [],
    this.protocol = ProtocolType.openaiChat,
    this.modelsPath = '',
    this.official = true,
  });

  /// 稳定内部 ID，不做显示名判断。`custom` 为自定义服务。
  final String id;

  /// 面向用户的中文名称。
  final String displayName;

  /// 官方默认 API Base URL；`custom` 为空字符串。
  final String baseUrl;

  /// 官方域名白名单（精确 host）。
  final List<String> hosts;

  /// 官方域名后缀白名单（如 Qwen 区域 Workspace 域名 `*.maas.aliyuncs.com`）。
  final List<String> hostSuffixes;

  /// 默认协议。
  final String protocol;

  /// 相对 `baseUrl` 的模型列表路径（如 `/models`）；空 = 官方无文档化 `/models`，
  /// 需手填模型 ID + 真实验证。
  final String modelsPath;

  /// 是否官方预置（`custom` 为 false）。
  final bool official;

  bool get hasModelDiscovery => modelsPath.isNotEmpty;

  bool get isCustom => id == 'custom';

  /// 精确 host 匹配（含后缀匹配）。
  bool matchesHost(String host) {
    final h = host.toLowerCase();
    if (hosts.any((item) => item.toLowerCase() == h)) return true;
    return hostSuffixes.any((suffix) => h.endsWith(suffix.toLowerCase()));
  }
}
