import 'package:asone_contracts/asone_contracts.dart';
import 'local_core/assistant_execution_context.dart';
import 'local_core/chat/chat_engine_strategies.dart';
import 'local_core/core_repository.dart';

/// 社区版共享聊天引擎的最小上下文实现。
///
/// 它只冻结当前对话绑定的模型服务和基础文本历史；不读取记忆、关系状态、
/// 设备、活动或工具配置。私有版仍由其独立绑定提供增强上下文。
class CommunityChatContextCompiler implements ChatContextCompiler {
  CommunityChatContextCompiler({required CoreRepository repository})
    : _repository = repository;

  final CoreRepository _repository;

  Future<String> primaryConversationId(String assistantId) async =>
      (await _repository.getOrCreatePrimaryConversation(assistantId)).id;

  @override
  Future<ChatEngineTurnContext> compileTurnContext({
    required String conversationId,
    required String query,
    String? excludedMessageId,
    String? currentMessageId,
  }) async {
    final conversation = await _repository.getConversation(conversationId);
    if (conversation == null) throw StateError('对话不存在：$conversationId');
    final assistantId = conversation.assistantId;
    if (assistantId == null || assistantId.isEmpty) {
      throw StateError('对话未绑定助手：$conversationId');
    }
    final assistant = await _repository.getAssistant(assistantId);
    if (assistant == null) throw StateError('助手不存在：$assistantId');
    final modelServiceId = assistant.modelServiceId;
    if (modelServiceId.isEmpty) throw StateError('助手未配置模型服务：$assistantId');

    final services = await _repository.getModelServices();
    final matching = services.where((service) => service.id == modelServiceId);
    if (matching.isEmpty) throw StateError('模型服务不存在：$modelServiceId');
    final service = matching.first;
    // 检测结果一旦保存，允许旧的 `auto` 配置在不重新联网探测的前提下恢复。
    // 没有本地检测记录时才要求用户先完成能力检测。
    final protocol = service.protocolType == ProtocolType.auto
        ? await _repository.recoverDetectedModelProtocol(service.id)
        : service.protocolType;
    if (protocol == null || protocol == ProtocolType.auto) {
      throw StateError('模型服务协议尚未确定，请先完成模型能力检测');
    }
    if (service.baseUrl.trim().isEmpty ||
        service.apiKey.trim().isEmpty ||
        service.model.trim().isEmpty) {
      throw StateError('模型服务配置不完整，请检查地址、密钥和模型名称');
    }

    final messages = await _repository.getMessages(conversationId);
    final history = messages
        .where((message) => message.id != excludedMessageId)
        .map(
          (message) => <String, Object?>{
            'id': message.id,
            'role': message.role,
            'content': message.content,
            'answer_status': message.answerStatus,
            'created_at': message.createdAt?.toUtc().toIso8601String(),
          },
        )
        .toList(growable: false);

    return ChatEngineTurnContext(
      assistantId: assistantId,
      modelSnapshot: ModelBindingSnapshot(
        modelServiceId: service.id,
        baseUrl: service.baseUrl,
        apiKey: service.apiKey,
        model: service.model,
        protocolType: protocol,
        providerId: service.providerId,
        providerAdapterVersion: service.providerAdapterVersion,
      ),
      context: <String, Object?>{
        'assistantId': assistantId,
        'current_message_id': currentMessageId,
        'max_output_tokens': 2048,
        'timestamps_enabled': 1,
        'tools_enabled': false,
        'context_window': 100000,
        'retrieval_context': '{}',
        'all_system_parts': const <Map<String, String>>[],
        'all_recent_messages': history,
      },
    );
  }
}
