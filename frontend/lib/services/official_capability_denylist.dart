/// 官方「明确不支持」能力白名单（denylist）。
///
/// 精简原则：官方明确否定的能力直接标「不支持」且不发无意义探针；
/// 其余能力一律真实验证。规则来自《AI模型服务商_API能力官方文档核对报告
/// 2026-08-16》TABLE 24「明确不支持项」，宁可漏判（漏判→真实验证兜底），
/// 不可误判（误判→错误结论）。
class OfficialUnsupportedRule {
  const OfficialUnsupportedRule({
    required this.providerId,
    required this.capability,
    required this.reason,
    this.models = const [],
    this.modelPrefixes = const [],
  });

  final String providerId;
  final String capability;

  /// 面向用户的中文依据。
  final String reason;

  /// 精确模型 ID（规范化小写）。与 `modelPrefixes` 都为空 = 该 provider 全模型。
  final List<String> models;

  /// 模型 ID 前缀（规范化小写）。
  final List<String> modelPrefixes;

  bool matches(String providerId, String modelId) {
    if (this.providerId != providerId) return false;
    // 全模型规则：models 与 modelPrefixes 都为空 = 该 provider 所有模型命中。
    if (models.isEmpty && modelPrefixes.isEmpty) return true;
    final m = modelId.trim().toLowerCase();
    if (m.isEmpty) return false;
    if (models.contains(m)) return true;
    return modelPrefixes.any(m.startsWith);
  }
}

/// 官方明确不支持的能力查询入口。
abstract final class OfficialCapabilityDenylist {
  static const List<OfficialUnsupportedRule> rules = [
    OfficialUnsupportedRule(
      providerId: 'minimax',
      capability: 'vision_input',
      reason: 'MiniMax 官方 Messages 文档明确 M2.x 仅 text/tool blocks，不支持图片/视频输入',
      models: ['minimax-m2'],
      modelPrefixes: ['minimax-m2.7', 'minimax-m2.5', 'minimax-m2.1'],
    ),
    OfficialUnsupportedRule(
      providerId: 'spark',
      capability: 'client_tool_calling',
      reason: '讯飞星火官方明确自定义 Function Call 仅 4.0Ultra / Max 支持',
      models: ['generalv3', 'pro-128k', 'lite'],
    ),
    OfficialUnsupportedRule(
      providerId: 'hunyuan',
      capability: 'vision_input',
      reason: '腾讯混元 TokenHub 兼容文档把 hy3 列为纯文本模型',
      models: ['hy3', 'hy3-preview'],
    ),
    OfficialUnsupportedRule(
      providerId: 'glm',
      capability: 'vision_input',
      reason: '智谱 GLM 官方模型页明确输入模态仅文本',
      models: [
        'glm-5.2',
        'glm-5.1',
        'glm-5',
        'glm-5-turbo',
        'glm-4.7',
        'glm-4.7-flash',
        'glm-4.6',
        'glm-4.5',
      ],
    ),
  ];

  /// 官方是否明确不支持该 provider + 模型 + 能力。
  static bool isUnsupported(
    String providerId,
    String modelId,
    String capability,
  ) => rules.any(
    (rule) =>
        rule.matches(providerId, modelId) && rule.capability == capability,
  );

  /// 查询官方依据文案；无匹配返回 null。
  static String? reasonFor(
    String providerId,
    String modelId,
    String capability,
  ) {
    for (final rule in rules) {
      if (rule.capability == capability && rule.matches(providerId, modelId)) {
        return rule.reason;
      }
    }
    return null;
  }
}
