import 'local_core/chat/local_chat_service.dart';
import 'local_core/core_database.dart';
import 'local_core/group_chat/group_branch_cascade_service.dart';
import 'local_core/group_chat/group_conversation_service.dart';
import 'local_core/group_chat/group_generation_events.dart';
import 'local_core/group_chat/group_message_repository.dart';
import 'local_core/group_chat/group_models.dart';
import 'local_core/group_chat/group_round_handler.dart';
import 'local_core/group_chat/group_round_repository.dart';
import 'local_core/group_chat/group_room_repository.dart';
import 'local_core/local_job_registry.dart';
import 'local_core/local_job_service.dart';

import 'community_group_context_builder.dart';

/// 社区版的持久化群聊轮次执行器。
///
/// 轮次、步骤和回答版本沿用正式状态机；稳定轮次没有私有后处理钩子。
class CommunityGroupRoundEngine {
  CommunityGroupRoundEngine({
    required CoreDatabase database,
    required LocalChatService chat,
    required CommunityGroupContextBuilder contextBuilder,
    required GroupRoomRepository rooms,
    required GroupMessageRepository messages,
    GroupAssistantTurnRunner? turnRunner,
  }) : _messages = messages,
       _rounds = GroupRoundRepository(
         coreDatabase: database,
         messageRepository: messages,
       ),
       _registry = LocalJobRegistry.create(),
       _events = GroupGenerationEventBus() {
    _jobs = LocalJobService(coreDatabase: database, registry: _registry);
    _conversation = GroupConversationService(
      coreDatabase: database,
      roomRepository: rooms,
      messageRepository: messages,
      roundRepository: _rounds,
      jobService: _jobs,
      branchRegenerator: (messageId) async {
        final result = await GroupBranchCascadeService(
          coreDatabase: database,
          roomRepository: rooms,
          messageRepository: messages,
          roundRepository: _rounds,
          jobService: _jobs,
        ).regenerateFromAssistantMessage(messageId);
        final jobId = result.jobId;
        if (jobId == null) throw StateError('重新回答未开始，请重试');
        return GroupRoundLaunch(round: result.round, jobId: jobId);
      },
    );
    _registry.register(
      GroupRoundHandler(
        coreDatabase: database,
        roundRepository: _rounds,
        messageRepository: messages,
        turnRunner:
            turnRunner ??
            LocalChatGroupTurnRunner(
              chatService: chat,
              contextBuilder: contextBuilder.build,
            ),
        eventBus: _events,
        stableRoundHook: null,
      ),
    );
  }

  final GroupMessageRepository _messages;
  final GroupRoundRepository _rounds;
  final LocalJobRegistry _registry;
  final GroupGenerationEventBus _events;
  late final LocalJobService _jobs;
  late final GroupConversationService _conversation;

  Stream<GroupGenerationEvent> get events => _events.events;

  Future<List<GroupMessage>> send({
    required String roomId,
    required String content,
  }) async {
    final launch = await _conversation.sendUserMessageAndStartSequentialRound(
      roomId: roomId,
      content: content,
    );
    await _jobs.runToCompletion(launch.jobId);
    return _messages.listMessages(roomId, limit: 200);
  }

  /// 仅点名一名已加入房间的助手发言，仍使用同一持久化轮次状态机。
  Future<List<GroupMessage>> sendToAssistant({
    required String roomId,
    required String assistantId,
    required String content,
  }) async {
    final launch = await _conversation.sendUserMessageToAssistant(
      roomId: roomId,
      assistantId: assistantId,
      content: content,
    );
    await _jobs.runToCompletion(launch.jobId);
    return _messages.listMessages(roomId, limit: 200);
  }

  /// 从指定助手回答开始重生成后续当前分支；社区版不触发派生数据副作用。
  Future<List<GroupMessage>> regenerateAssistantMessage(String messageId) async {
    final launch = await _conversation.regenerateFromAssistantMessage(messageId);
    await _jobs.runToCompletion(launch.jobId);
    return _messages.listMessages(launch.round.roomId, limit: 200);
  }

  Future<void> dispose() => _events.close();
}
