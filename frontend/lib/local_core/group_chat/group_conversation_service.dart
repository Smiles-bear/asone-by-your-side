library;

import '../core_database.dart';
import '../local_job_service.dart';
import 'group_message_repository.dart';
import 'group_models.dart';
import 'group_round_repository.dart';
import 'group_round_task.dart';
import 'group_room_repository.dart';

class GroupRoundLaunch {
  const GroupRoundLaunch({
    required this.round,
    required this.jobId,
    this.userMessage,
  });

  final GroupRound round;
  final String jobId;
  final GroupMessage? userMessage;
}

class GroupConversationService {
  GroupConversationService({
    CoreDatabase? coreDatabase,
    required GroupRoomRepository roomRepository,
    required GroupMessageRepository messageRepository,
    required GroupRoundRepository roundRepository,
    required LocalJobService jobService,
    Future<GroupRoundLaunch> Function(String messageId)? branchRegenerator,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _rooms = roomRepository,
       _messages = messageRepository,
       _rounds = roundRepository,
       _jobs = jobService,
       _branchRegenerator = branchRegenerator;

  final CoreDatabase _coreDatabase;
  final GroupRoomRepository _rooms;
  final GroupMessageRepository _messages;
  final GroupRoundRepository _rounds;
  final LocalJobService _jobs;
  final Future<GroupRoundLaunch> Function(String messageId)? _branchRegenerator;

  Future<GroupMessage> postUserMessage({
    required String roomId,
    required String content,
    bool allowEmpty = false,
  }) async {
    final room = await _rooms.getRoom(roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (await _rounds.activeRoundForRoom(roomId) != null) {
      throw StateError('当前回复尚未结束，请稍后再发送。');
    }
    return _messages.createUserMessage(
      roomId: roomId,
      content: content,
      requestType: 'manual_mention',
      allowEmpty: allowEmpty,
    );
  }

  Future<GroupRoundLaunch> startSequentialRoundForUserMessage({
    required String roomId,
    required String messageId,
  }) async {
    final room = await _rooms.getRoom(roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (!room.sequentialEnabled) throw StateError('当前群聊未开启顺序发言');
    if (await _rounds.activeRoundForRoom(roomId) != null) {
      throw StateError('当前回复尚未结束，请稍后再发送。');
    }
    final message = await _messages.getMessage(messageId);
    if (message == null ||
        message.roomId != roomId ||
        message.speakerType != 'user' ||
        message.isDeleted) {
      throw StateError('触发消息不存在');
    }
    final participants = await _rooms.getParticipants(roomId);
    final round = await _rounds.createRound(
      roomId: roomId,
      requestType: 'sequential',
      participantOrder: participants
          .map((participant) => participant.assistantId)
          .toList(growable: false),
      rootTriggerMessageId: message.messageId,
      triggerMessageVersionId: message.currentMessageVersionId,
    );
    final jobId = await _createAndStartJob(round);
    return GroupRoundLaunch(round: round, jobId: jobId, userMessage: message);
  }

  Future<GroupRoundLaunch> sendUserMessageAndStartSequentialRound({
    required String roomId,
    required String content,
  }) async {
    final room = await _rooms.getRoom(roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (!room.sequentialEnabled) throw StateError('当前群聊未开启顺序发言');
    if (await _rounds.activeRoundForRoom(roomId) != null) {
      throw StateError('当前回复尚未结束，请稍后再发送。');
    }
    final participants = await _rooms.getParticipants(roomId);
    late GroupMessage userMessage;
    late GroupRound round;
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      userMessage = await _messages.createUserMessage(
        roomId: roomId,
        content: content,
        requestType: 'sequential',
        transaction: txn,
      );
      round = await _rounds.createRound(
        roomId: roomId,
        requestType: 'sequential',
        participantOrder: participants
            .map((participant) => participant.assistantId)
            .toList(growable: false),
        rootTriggerMessageId: userMessage.messageId,
        triggerMessageVersionId: userMessage.currentMessageVersionId,
        transaction: txn,
      );
    });
    final jobId = await _createAndStartJob(round);
    return GroupRoundLaunch(
      round: round,
      jobId: jobId,
      userMessage: userMessage,
    );
  }

  Future<GroupRoundLaunch> sendUserMessageToAssistant({
    required String roomId,
    required String assistantId,
    required String content,
  }) async {
    final room = await _rooms.getRoom(roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (!room.manualMentionEnabled) throw StateError('当前群聊未开启手动点名');
    if (!await _rooms.isParticipant(roomId, assistantId)) {
      throw StateError('只能点名当前群成员');
    }
    if (await _rounds.activeRoundForRoom(roomId) != null) {
      throw StateError('当前回复尚未结束，请稍后再发送。');
    }
    late GroupMessage userMessage;
    late GroupRound round;
    final database = await _coreDatabase.open();
    await database.transaction((txn) async {
      userMessage = await _messages.createUserMessage(
        roomId: roomId,
        content: content,
        requestType: 'manual_mention',
        transaction: txn,
      );
      round = await _rounds.createRound(
        roomId: roomId,
        requestType: 'manual_mention',
        participantOrder: [assistantId],
        rootTriggerMessageId: userMessage.messageId,
        triggerMessageVersionId: userMessage.currentMessageVersionId,
        transaction: txn,
      );
    });
    final jobId = await _createAndStartJob(round);
    return GroupRoundLaunch(
      round: round,
      jobId: jobId,
      userMessage: userMessage,
    );
  }

  Future<GroupRoundLaunch> startAssistantTurn({
    required String roomId,
    required String assistantId,
  }) async {
    final room = await _rooms.getRoom(roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (!await _rooms.isParticipant(roomId, assistantId)) {
      throw StateError('只能点名当前群成员');
    }
    final round = await _rounds.createRound(
      roomId: roomId,
      requestType: 'manual_mention',
      participantOrder: [assistantId],
    );
    final jobId = await _createAndStartJob(round);
    return GroupRoundLaunch(round: round, jobId: jobId);
  }

  Future<GroupRoundLaunch> startAssistantTurnForUserMessage({
    required String roomId,
    required String assistantId,
    required String messageId,
  }) async {
    final room = await _rooms.getRoom(roomId);
    if (room == null || room.status != 'active') throw StateError('群聊不存在');
    if (!await _rooms.isParticipant(roomId, assistantId)) {
      throw StateError('只能点名当前群成员');
    }
    if (await _rounds.activeRoundForRoom(roomId) != null) {
      throw StateError('当前回复尚未结束，请稍后再发送。');
    }
    final message = await _messages.getMessage(messageId);
    if (message == null ||
        message.roomId != roomId ||
        message.speakerType != 'user' ||
        message.isDeleted) {
      throw StateError('触发消息不存在');
    }
    final round = await _rounds.createRound(
      roomId: roomId,
      requestType: 'manual_mention',
      participantOrder: <String>[assistantId],
      rootTriggerMessageId: message.messageId,
      triggerMessageVersionId: message.currentMessageVersionId,
    );
    final jobId = await _createAndStartJob(round);
    return GroupRoundLaunch(round: round, jobId: jobId, userMessage: message);
  }

  @Deprecated('Use sendUserMessageAndStartSequentialRound')
  Future<GroupRoundLaunch> sendUserMessage({
    required String roomId,
    required String content,
  }) =>
      sendUserMessageAndStartSequentialRound(roomId: roomId, content: content);

  @Deprecated('Use startAssistantTurn')
  Future<GroupRoundLaunch> mentionAssistant({
    required String roomId,
    required String assistantId,
  }) => startAssistantTurn(roomId: roomId, assistantId: assistantId);

  Future<void> stopRoom(String roomId) async {
    final active = await _rounds.activeRoundForRoom(roomId);
    if (active == null) return;
    await _rounds.requestCancel(active.roundId);
    await _jobs.cancelActiveByScope(
      taskType: kGroupRoundTaskType,
      scopeType: 'group_room',
      scopeId: roomId,
    );
  }

  Future<bool> hasActiveRound(String roomId) async =>
      await _rounds.activeRoundForRoom(roomId) != null;

  Future<GroupRoundLaunch> regenerateFromAssistantMessage(
    String messageId,
  ) async {
    final regenerate = _branchRegenerator;
    if (regenerate == null) {
      throw UnsupportedError('当前构建未开放群聊分支重新生成');
    }
    return regenerate(messageId);
  }

  Future<String> _createAndStartJob(GroupRound round) async {
    final job = await createGroupRoundJob(
      jobService: _jobs,
      roomId: round.roomId,
      roundId: round.roundId,
      totalSteps: round.participantOrder.length,
    );
    await _rounds.attachJob(round.roundId, job.jobId);
    await _jobs.start(job.jobId);
    return job.jobId;
  }
}
