import 'local_core/group_chat/group_context_window_planner.dart';
import 'local_core/group_chat/group_message_repository.dart';
import 'local_core/group_chat/group_models.dart';
import 'local_core/group_chat/group_round_handler.dart';
import 'local_core/group_chat/group_room_repository.dart';

import 'community_chat_context_compiler.dart';

/// 群聊的公共上下文：仅房间规则和当前群的可见基础文本。
class CommunityGroupContextBuilder {
  CommunityGroupContextBuilder({
    required CommunityChatContextCompiler chatContext,
    required GroupRoomRepository rooms,
    required GroupMessageRepository messages,
  }) : _chatContext = chatContext,
       _rooms = rooms,
       _messages = messages;

  final CommunityChatContextCompiler _chatContext;
  final GroupRoomRepository _rooms;
  final GroupMessageRepository _messages;
  final GroupContextWindowPlanner _planner = GroupContextWindowPlanner();

  Future<GroupTurnExecutionContext> build(GroupTurnRequest request) async {
    final room = await _rooms.getRoom(request.roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (!await _rooms.isParticipant(request.roomId, request.step.assistantId)) {
      throw StateError('助手不是当前群成员');
    }
    final conversationId = await _chatContext.primaryConversationId(
      request.step.assistantId,
    );
    final turn = await _chatContext.compileTurnContext(
      conversationId: conversationId,
      query: request.triggerMessage?.content ?? '',
    );
    final history = await _messages.listMessages(
      request.roomId,
      beforeSequence: request.message.sequence,
      limit: 120,
    );
    final groupMessages = history
        .where((message) => message.visible || message.contextVisible)
        .map(_asContextMessage)
        .toList(growable: false);
    final plan = _planner.plan(
      contextWindow: 100000,
      maxOutputTokens: 2048,
      systemParts: [
        {
          'kind': 'group',
          'content':
              '你正在参与一个多人群聊，本次只代表当前助手发言。'
              '只基于本次群聊中的公开文本回复；不要假设拥有记忆、关系、设备、工具或隐藏资料。'
              '其他成员彼此独立，不得冒充或代答。只输出准备发送到群里的自然回复。',
        },
        {
          'kind': 'group_scene',
          'content': _sceneInstruction(room.roomInstruction),
        },
      ],
      privateMessages: const [],
      groupMessages: groupMessages,
    );
    return GroupTurnExecutionContext(
      conversationId: conversationId,
      modelSnapshot: turn.modelSnapshot,
      frozenContext: {
        'assistantId': request.step.assistantId,
        'max_output_tokens': plan.maxOutputTokens,
        'timestamps_enabled': 1,
        'tools_enabled': false,
        'context_window': 100000,
        'retrieval_context': '{}',
        'all_system_parts': plan.systemParts,
        'all_recent_messages': plan.messages,
      },
    );
  }

  Map<String, Object?> _asContextMessage(GroupMessage message) => {
    'message_id': message.messageId,
    'turn_id': message.rootTriggerMessageId ?? message.messageId,
    'role': message.speakerType == 'user' ? 'user' : 'assistant',
    'content': message.content,
    'answer_status': message.answerStatus,
    'created_at': message.createdAt.toUtc().toIso8601String(),
  };

  String _sceneInstruction(String roomInstruction) {
    final rule = roomInstruction.trim().isEmpty
        ? '未设置额外群聊规则。'
        : roomInstruction.trim();
    return '【当前场景：多人群聊】\n'
        '成员：用户、群成员\n\n'
        '【群聊规则】\n$rule\n\n'
        '以下是群聊公开消息记录。';
  }
}
