import '../services/provider_adapters/model_output_contract.dart';

/// 助手执行上下文：统一的身份与模型路由入口。
///
/// 所有模型调用（聊天、记忆整理、日记等）必须先构造执行上下文，
/// 验证助手与对话归属关系，冻结模型绑定快照，确保写回目标正确。
class AssistantExecutionContext {
  const AssistantExecutionContext({
    required this.requestId,
    required this.taskType,
    required this.assistantId,
    required this.assistantName,
    required this.conversationId,
    required this.modelBindingSnapshot,
    required this.createdAt,
    this.idempotencyKey,
  });

  /// 本次请求唯一标识
  final String requestId;

  /// 任务类型：chat, memory_rebuild, memory_consolidate, diary_auto, diary_manual
  final String taskType;

  /// 助手 ID（永久身份）
  final String assistantId;

  /// 助手名称（用于日志和错误提示）
  final String assistantName;

  /// 对话 ID（必须属于该助手）
  final String conversationId;

  /// 模型绑定快照（创建上下文时冻结，任务期间不变）
  final ModelBindingSnapshot modelBindingSnapshot;

  /// 上下文创建时间
  final DateTime createdAt;

  /// 幂等键（可选）
  final String? idempotencyKey;

  @override
  String toString() =>
      'AssistantExecutionContext('
      'taskType=$taskType, '
      'assistantId=$assistantId, '
      'conversationId=$conversationId, '
      'requestId=$requestId)';
}

/// 模型绑定快照：任务启动时冻结，执行期间不受热切换影响。
class ModelBindingSnapshot {
  const ModelBindingSnapshot({
    required this.modelServiceId,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.protocolType,
    this.providerId = 'custom',
    this.providerAdapterVersion = 1,
    this.configurationFingerprint = '',
    this.capabilityProfile = const ModelCapabilityProfile(),
  });

  /// 模型服务 ID
  final String modelServiceId;

  /// Base URL
  final String baseUrl;

  /// API Key
  final String apiKey;

  /// 模型名称
  final String model;

  /// 协议类型（openai, anthropic, gemini, auto）
  final String protocolType;

  final String providerId;
  final int providerAdapterVersion;
  final String configurationFingerprint;
  final ModelCapabilityProfile capabilityProfile;

  bool get isValid =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  @override
  String toString() =>
      'ModelBindingSnapshot('
      'modelServiceId=$modelServiceId, '
      'model=$model, '
      'providerId=$providerId, '
      'protocolType=$protocolType)';
}
