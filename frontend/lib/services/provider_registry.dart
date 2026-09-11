import 'provider_definition.dart';
import 'provider_adapters/protocol_types.dart';

/// 官方服务商注册表。
///
/// 十家官方服务商 + 自定义，按固定顺序注册。负责按 `provider_id` 取定义、
/// 按官方 host 精确映射 `provider_id`（旧配置迁移与白名单校验共用）。
class ProviderRegistry {
  ProviderRegistry._();

  static final ProviderRegistry instance = ProviderRegistry._();

  /// 自定义服务定义（唯一非官方入口）。
  static const custom = ProviderDefinition(
    id: 'custom',
    displayName: '自定义',
    baseUrl: '',
    protocol: ProtocolType.auto,
    official: false,
  );

  /// 十一家固定顺序（含自定义在末位）。
  static const List<ProviderDefinition> all = [
    ProviderDefinition(
      id: 'deepseek',
      displayName: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      hosts: ['api.deepseek.com'],
      modelsPath: '/models',
    ),
    ProviderDefinition(
      id: 'kimi',
      displayName: 'Kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      hosts: ['api.moonshot.cn'],
      modelsPath: '/models',
    ),
    ProviderDefinition(
      id: 'glm',
      displayName: 'GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      hosts: ['open.bigmodel.cn'],
    ),
    ProviderDefinition(
      id: 'qwen',
      displayName: 'Qwen',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      hosts: ['dashscope.aliyuncs.com', 'dashscope-us.aliyuncs.com'],
      hostSuffixes: ['.maas.aliyuncs.com'],
    ),
    ProviderDefinition(
      id: 'doubao',
      displayName: '豆包',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      hosts: ['ark.cn-beijing.volces.com'],
    ),
    ProviderDefinition(
      id: 'minimax',
      displayName: 'MiniMax',
      baseUrl: 'https://api.minimaxi.com/v1',
      hosts: ['api.minimaxi.com'],
      modelsPath: '/models',
    ),
    ProviderDefinition(
      id: 'hunyuan',
      displayName: '混元',
      baseUrl: 'https://tokenhub.tencentmaas.com/v1',
      hosts: ['tokenhub.tencentmaas.com'],
      modelsPath: '/models',
    ),
    ProviderDefinition(
      id: 'wenxin',
      displayName: '文心',
      baseUrl: 'https://qianfan.baidubce.com/v2',
      hosts: ['qianfan.baidubce.com'],
      modelsPath: '/models',
    ),
    ProviderDefinition(
      id: 'spark',
      displayName: '星火',
      baseUrl: 'https://spark-api-open.xf-yun.com/v1',
      hosts: ['spark-api-open.xf-yun.com'],
    ),
    ProviderDefinition(
      id: 'step',
      displayName: 'Step',
      baseUrl: 'https://api.stepfun.ai/v1',
      hosts: ['api.stepfun.ai'],
      modelsPath: '/models',
    ),
    custom,
  ];

  final Map<String, ProviderDefinition> _byId = {
    for (final provider in all) provider.id: provider,
  };

  /// 按 `provider_id` 取定义；未知 id 回退 custom。
  ProviderDefinition get(String id) => _byId[id] ?? custom;

  /// 按官方 host 精确映射 `provider_id`；无匹配返回 null。
  /// 用于旧配置迁移与官方白名单校验。相似域名、中转域名不得误命中。
  ProviderDefinition? matchByHost(String host) {
    final h = host.toLowerCase().trim();
    if (h.isEmpty) return null;
    for (final provider in all) {
      if (provider.official && provider.matchesHost(h)) return provider;
    }
    return null;
  }
}
