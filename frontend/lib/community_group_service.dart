import 'package:asone_contracts/asone_contracts.dart';
import 'local_core/group_chat/group_message_repository.dart';
import 'local_core/group_chat/group_models.dart';
import 'local_core/group_chat/group_room_repository.dart';
import 'services/provider_adapters/adapter_registry.dart';
import 'services/provider_adapters/protocol_client.dart';

import 'community_group_round_engine.dart';
/// 社区版群聊的基础回复结果。
class CommunityGroupReply {
  const CommunityGroupReply.success(this.content)
    : failureHint = null,
      isSuccess = true;

  const CommunityGroupReply.failure(this.failureHint)
    : content = '',
      isSuccess = false;

  final String content;
  final String? failureHint;
  final bool isSuccess;
}

typedef CommunityGroupReplyGenerator =
    Future<CommunityGroupReply> Function({
      required ModelService service,
      required String assistantName,
      required List<Map<String, Object?>> history,
    });

/// 不依赖记忆、工具、语音或后台任务的社区版群聊编排。
///
/// 每个已选 API 服务对应一个本地助手，并按房间成员顺序依次回复。房间和
/// 消息持久化在 SQLite；模型请求仅发送当前群聊的基础文本历史。
class CommunityGroupService {
  CommunityGroupService({
    required AssistantRepositoryApi assistants,
    required ModelServiceRepositoryApi modelServices,
    required GroupRoomRepository rooms,
    required GroupMessageRepository messages,
    ProtocolClient? client,
    CommunityGroupRoundEngine? roundEngine,
  }) : _assistants = assistants,
       _modelServices = modelServices,
       _rooms = rooms,
       _messages = messages,
       _client = client ?? ProtocolClient(),
       _roundEngine = roundEngine;

  final AssistantRepositoryApi _assistants;
  final ModelServiceRepositoryApi _modelServices;
  final GroupRoomRepository _rooms;
  final GroupMessageRepository _messages;
  final ProtocolClient _client;
  final CommunityGroupRoundEngine? _roundEngine;

  Future<GroupRoom> createRoom({
    required String title,
    required List<String> serviceIds,
  }) async {
    final uniqueIds = serviceIds.toSet().toList(growable: false);
    if (uniqueIds.length < 2) {
      throw ArgumentError('群聊至少需要选择两个不同的模型服务');
    }
    final services = await _modelServices.getModelServices();
    final selected = <ModelService>[];
    for (final id in uniqueIds) {
      final matches = services.where((service) => service.id == id);
      if (matches.isEmpty) throw StateError('所选模型服务不存在');
      final service = matches.first;
      if (service.baseUrl.trim().isEmpty || service.model.trim().isEmpty) {
        throw StateError('模型服务“${service.name}”尚未完成配置');
      }
      selected.add(service);
    }
    final participantIds = <String>[];
    for (final service in selected) {
      participantIds.add((await _assistantForService(service)).id);
    }
    final normalizedTitle = title.trim();
    return _rooms.createRoom(
      title: normalizedTitle.isEmpty
          ? selected.map((service) => service.name).join('、')
          : normalizedTitle,
      participantAssistantIds: participantIds,
    );
  }

  Future<List<GroupMessage>> messagesForRoom(String roomId) =>
      _messages.listMessages(roomId, limit: 200);

  Future<List<GroupParticipant>> participantsForRoom(String roomId) =>
      _rooms.getParticipants(roomId);

  Future<List<GroupRoom>> listRooms() => _rooms.listRooms();

  Future<List<GroupMessage>> sendUserMessage({
    required String roomId,
    required String content,
    CommunityGroupReplyGenerator? replyGenerator,
  }) async {
    final engine = _roundEngine;
    if (replyGenerator == null && engine != null) {
      return engine.send(roomId: roomId, content: content);
    }
    final userMessage = await _messages.createUserMessage(
      roomId: roomId,
      content: content,
    );
    final participants = await _rooms.getParticipants(roomId);
    for (var position = 0; position < participants.length; position++) {
      final participant = participants[position];
      final assistant = await _assistants.getAssistant(participant.assistantId);
      if (assistant == null) continue;
      final placeholder = await _messages.createAssistantPlaceholder(
        roomId: roomId,
        assistantId: assistant.id,
        rootTriggerMessageId: userMessage.messageId,
        roundPosition: position,
        requestType: 'sequential',
      );
      final answer = await _messages.startAnswerVersion(
        messageId: placeholder.messageId,
        upstreamRevisionHash:
            'community:${userMessage.messageId}:${assistant.id}:${placeholder.sequence}',
        contextCutoffSequence: placeholder.sequence - 1,
      );
      try {
        final service = await _serviceForAssistant(assistant);
        final history = await _historyForRoom(roomId);
        final reply = await (replyGenerator ?? _requestReply)(
          service: service,
          assistantName: assistant.name,
          history: history,
        );
        if (!reply.isSuccess || reply.content.trim().isEmpty) {
          await _messages.failAssistantReply(
            messageId: placeholder.messageId,
            answerVersionId: answer.answerVersionId,
            failureHint: reply.failureHint ?? '模型服务未返回可用内容',
          );
          continue;
        }
        await _messages.commitAssistantReply(
          messageId: placeholder.messageId,
          answerVersionId: answer.answerVersionId,
          content: reply.content.trim(),
        );
      } catch (_) {
        await _messages.failAssistantReply(
          messageId: placeholder.messageId,
          answerVersionId: answer.answerVersionId,
          failureHint: '调用失败，请检查模型服务配置后重试。',
        );
      }
    }
    return messagesForRoom(roomId);
  }

  /// 点名发言仅在已装配公共轮次引擎时可用，避免轻量测试后备路径绕过状态机。
  Future<List<GroupMessage>> sendUserMessageToAssistant({
    required String roomId,
    required String assistantId,
    required String content,
  }) {
    final engine = _roundEngine;
    if (engine == null) {
      throw UnsupportedError('当前构建未装配群聊点名轮次引擎');
    }
    return engine.sendToAssistant(
      roomId: roomId,
      assistantId: assistantId,
      content: content,
    );
  }

  Future<List<GroupMessage>> regenerateAssistantMessage(String messageId) {
    final engine = _roundEngine;
    if (engine == null) {
      throw UnsupportedError('当前构建未装配群聊重生成引擎');
    }
    return engine.regenerateAssistantMessage(messageId);
  }

  Future<Assistant> _assistantForService(ModelService service) async {
    final assistants = await _assistants.getAssistants();
    final existing = assistants.where(
      (assistant) => assistant.modelServiceId == service.id,
    );
    if (existing.isNotEmpty) return existing.first;
    return _assistants.createAssistant(
      name: service.name,
      mainModel: service.model,
      modelServiceId: service.id,
      memoryAutoOrganizeEnabled: false,
    );
  }

  Future<ModelService> _serviceForAssistant(Assistant assistant) async {
    if (assistant.modelServiceId.isEmpty) {
      throw StateError('群成员未绑定模型服务');
    }
    final services = await _modelServices.getModelServices();
    final matched = services.where(
      (service) => service.id == assistant.modelServiceId,
    );
    if (matched.isEmpty) throw StateError('群成员的模型服务不存在');
    return matched.first;
  }

  Future<List<Map<String, Object?>>> _historyForRoom(String roomId) async {
    final messages = await _messages.listMessages(roomId, limit: 24);
    return messages
        .where((message) => message.answerStatus != 'failed')
        .map(
          (message) => <String, Object?>{
            'role': message.speakerType == 'user' ? 'user' : 'assistant',
            'content': message.content,
          },
        )
        .where((message) => (message['content']! as String).trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<CommunityGroupReply> _requestReply({
    required ModelService service,
    required String assistantName,
    required List<Map<String, Object?>> history,
  }) async {
    final protocol = service.protocolType == ProtocolType.auto
        ? await _resolveProtocol(service)
        : service.protocolType;
    final adapter = AdapterRegistry.instance.get(protocol);
    final result = await _client.streamText(
      adapter: adapter,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      messages: [
        <String, Object?>{
          'role': 'system',
          'content': '你是$assistantName，正在参加多人群聊。请只基于当前对话文本自然回复。',
        },
        ...history,
      ],
      maxTokens: 2048,
      temperature: 0.7,
      onDelta: (_) {},
    );
    if (!result.success || result.text.trim().isEmpty) {
      return CommunityGroupReply.failure(
        result.diagnosis.detail.trim().isEmpty
            ? '模型服务未返回可用内容'
            : result.diagnosis.detail,
      );
    }
    return CommunityGroupReply.success(result.text);
  }

  Future<String> _resolveProtocol(ModelService service) async {
    final resolution = await _client.resolveProtocol(
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
    );
    if (!resolution.success) {
      throw StateError(resolution.diagnosis.detail);
    }
    await _modelServices.persistDetectedModelProtocol(
      service.id,
      resolution.protocol,
    );
    return resolution.protocol;
  }
}
