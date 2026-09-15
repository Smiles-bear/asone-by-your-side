library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../../models/message.dart';
import '../../services/debug_logger.dart';
import '../assistant_execution_context.dart';
import '../core_database.dart';
import '../local_job.dart';
import '../local_job_handler.dart';
import '../chat/local_chat_service.dart';
import 'group_generation_events.dart';
import 'group_message_repository.dart';
import 'group_models.dart';
import 'group_round_repository.dart';
import 'group_round_task.dart';
import 'group_upstream_revision_hasher.dart';

class GroupTurnRequest {
  const GroupTurnRequest({
    required this.roomId,
    required this.roundId,
    required this.step,
    required this.totalSteps,
    required this.message,
    required this.answerVersion,
    required this.triggerMessage,
  });

  final String roomId;
  final String roundId;
  final GroupRoundStep step;
  final int totalSteps;
  final GroupMessage message;
  final GroupAnswerVersion answerVersion;
  final GroupMessage? triggerMessage;
}

class GroupTurnResult {
  const GroupTurnResult({
    required this.content,
    this.reasoning,
    this.segments = const [],
    this.inputTokens,
    this.outputTokens,
    this.toolUsed = false,
  });

  final String content;
  final String? reasoning;
  final List<String> segments;
  final int? inputTokens;
  final int? outputTokens;
  final bool toolUsed;
}

typedef GroupTurnCommitter = Future<void> Function(GroupTurnResult result);

/// 私有宿主可在群消息提交后生成语音回复；社区版不装配时为 no-op。
typedef GroupVoiceReplyHook = Future<void> Function({
  required String assistantId,
  required String roomId,
  required String messageId,
});

abstract class GroupAssistantTurnRunner {
  Future<void> run({
    required GroupTurnRequest request,
    required void Function(String delta) onDelta,
    required void Function() onSegmentBoundary,
    required GroupTurnCommitter commit,
  });

  Future<void> cancelRoom(String roomId);
}

class GroupTurnExecutionContext {
  const GroupTurnExecutionContext({
    required this.conversationId,
    required this.frozenContext,
    required this.modelSnapshot,
  });

  final String conversationId;
  final Map<String, Object?> frozenContext;
  final ModelBindingSnapshot modelSnapshot;
}

typedef GroupTurnExecutionContextBuilder =
    Future<GroupTurnExecutionContext> Function(GroupTurnRequest request);

class LocalChatGroupTurnRunner implements GroupAssistantTurnRunner {
  LocalChatGroupTurnRunner({
    required LocalChatService chatService,
    required GroupTurnExecutionContextBuilder contextBuilder,
  }) : _chatService = chatService,
       _contextBuilder = contextBuilder;

  final LocalChatService _chatService;
  final GroupTurnExecutionContextBuilder _contextBuilder;
  final Map<String, CancelToken> _cancelTokens = {};

  @override
  Future<void> run({
    required GroupTurnRequest request,
    required void Function(String delta) onDelta,
    required void Function() onSegmentBoundary,
    required GroupTurnCommitter commit,
  }) async {
    final execution = await _contextBuilder(request);
    final cancelToken = CancelToken();
    _cancelTokens[request.roomId] = cancelToken;
    String? doneError;
    var committed = false;
    try {
      await _chatService.send(
        conversationId: execution.conversationId,
        content: request.triggerMessage?.content ?? '',
        userAlreadyPersisted: true,
        frozenContext: execution.frozenContext,
        frozenModelSnapshot: execution.modelSnapshot,
        cancelToken: cancelToken,
        onDelta: onDelta,
        onSegmentBoundary: onSegmentBoundary,
        onDone: ({String? error}) => doneError = error,
        replyCommitter: (reply) async {
          await commit(
            GroupTurnResult(
              content: reply.content,
              reasoning: reply.reasoning,
              segments: reply.segments,
              inputTokens: reply.inputTokens,
              outputTokens: reply.outputTokens,
              toolUsed: reply.toolIds.isNotEmpty,
            ),
          );
          committed = true;
          return Message(
            id: request.message.messageId,
            role: 'assistant',
            content: reply.content,
            createdAt: DateTime.now(),
            reasoning: reply.reasoning,
            answerStatus: 'completed',
            toolUsed: reply.toolIds.isNotEmpty,
          );
        },
      );
      if (doneError != null) throw StateError(doneError!);
      if (!committed) throw StateError('群聊回复未提交');
    } finally {
      if (identical(_cancelTokens[request.roomId], cancelToken)) {
        _cancelTokens.remove(request.roomId);
      }
    }
  }

  @override
  Future<void> cancelRoom(String roomId) async {
    _cancelTokens[roomId]?.cancel('群聊已停止');
  }
}

class GroupRoundHandler implements LocalJobHandler {
  GroupRoundHandler({
    CoreDatabase? coreDatabase,
    required GroupRoundRepository roundRepository,
    required GroupMessageRepository messageRepository,
    required GroupAssistantTurnRunner turnRunner,
    required GroupGenerationEventBus eventBus,
    Future<void> Function(String roomId, String roundId)? stableRoundHook,
    GroupUpstreamRevisionHasher? upstreamRevisionHasher,
    GroupVoiceReplyHook? voiceReplyHook,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _rounds = roundRepository,
       _messages = messageRepository,
       _turnRunner = turnRunner,
       _events = eventBus,
       _stableRoundHook = stableRoundHook,
       _voiceReplyHook = voiceReplyHook,
       _upstreamHasher =
           upstreamRevisionHasher ??
           GroupUpstreamRevisionHasher(coreDatabase: coreDatabase);

  final CoreDatabase _coreDatabase;
  final GroupRoundRepository _rounds;
  final GroupMessageRepository _messages;
  final GroupAssistantTurnRunner _turnRunner;
  final GroupGenerationEventBus _events;
  final Future<void> Function(String roomId, String roundId)? _stableRoundHook;
  final GroupVoiceReplyHook? _voiceReplyHook;
  final GroupUpstreamRevisionHasher _upstreamHasher;

  @override
  String get taskType => kGroupRoundTaskType;

  @override
  Future<void> execute(LocalJob job, LocalJobContext context) async {
    final payload = GroupRoundTaskPayload.fromJsonString(
      context.payload ?? job.payload ?? '',
    );
    final round = await _rounds.getRound(payload.roundId);
    if (round == null || round.roomId != payload.roomId) {
      throw StateError('群轮次不存在');
    }
    final steps = await _rounds.getSteps(payload.roundId);
    _events.emit(
      GroupRoundStarted(roomId: payload.roomId, roundId: payload.roundId),
    );

    while (true) {
      if (await context.isCancelRequested ||
          await _isCancelRequested(round.roundId)) {
        await _turnRunner.cancelRoom(payload.roomId);
        await _rounds.settleCancelled(payload.roundId);
        break;
      }
      final step = await _rounds.claimNextStep(payload.roundId);
      if (step == null) break;
      final message = await _messages.getMessage(step.logicalMessageId);
      if (message == null) {
        await _rounds.failStep(
          payload.roundId,
          step.position,
          errorCode: 'MESSAGE_MISSING',
        );
        continue;
      }
      final upstreamRevisionHash = round.rootTriggerMessageId == null
          ? ''
          : await _upstreamHasher.calculate(
              roomId: payload.roomId,
              rootMessageId: round.rootTriggerMessageId!,
              logicalMessageId: message.messageId,
            );
      final answer = await _messages.startAnswerVersion(
        messageId: message.messageId,
        upstreamRevisionHash: upstreamRevisionHash,
        contextCutoffSequence: message.sequence - 1,
      );
      final assistantExists = await _assistantExists(step.assistantId);
      if (!assistantExists) {
        await _messages.failAssistantReply(
          messageId: message.messageId,
          answerVersionId: answer.answerVersionId,
          failureHint: '这位助手已不可用，请检查助手配置后重试。',
        );
        await _rounds.failRound(
          payload.roundId,
          step.position,
          errorCode: 'ASSISTANT_UNAVAILABLE',
        );
        break;
      }

      _events.emit(
        GroupStepStarted(
          roomId: payload.roomId,
          roundId: payload.roundId,
          messageId: message.messageId,
          assistantId: step.assistantId,
          position: step.position,
          total: steps.length,
        ),
      );
      try {
        final trigger = round.rootTriggerMessageId == null
            ? null
            : await _messages.getMessage(round.rootTriggerMessageId!);
        final request = GroupTurnRequest(
          roomId: payload.roomId,
          roundId: payload.roundId,
          step: step,
          totalSteps: steps.length,
          message: message,
          answerVersion: answer,
          triggerMessage: trigger,
        );
        await _runTurnWithCancellation(
          context: context,
          roomId: payload.roomId,
          request: request,
          onDelta: (delta) => _events.emit(
            GroupReplyDelta(
              roomId: payload.roomId,
              roundId: payload.roundId,
              messageId: message.messageId,
              delta: delta,
            ),
          ),
          onSegmentBoundary: () => _events.emit(
            GroupReplySegmentBoundary(
              roomId: payload.roomId,
              roundId: payload.roundId,
              messageId: message.messageId,
            ),
          ),
          commit: (result) => _messages.commitAssistantReply(
            messageId: message.messageId,
            answerVersionId: answer.answerVersionId,
            content: result.content,
            reasoning: result.reasoning,
            segments: result.segments,
            promptTokens: result.inputTokens,
            completionTokens: result.outputTokens,
            toolUsed: result.toolUsed,
          ),
        );
        try {
          await _voiceReplyHook?.call(
            assistantId: step.assistantId,
            roomId: payload.roomId,
            messageId: message.messageId,
          );
        } catch (error) {
          DebugLogger.instance.error(
            '群聊语音回复生成失败',
            tag: 'GroupChatVoice',
            details: error.toString(),
          );
        }
        await _rounds.completeStep(payload.roundId, step.position);
        _events.emit(
          GroupStepFinished(
            roomId: payload.roomId,
            roundId: payload.roundId,
            messageId: message.messageId,
            status: 'completed',
          ),
        );
      } catch (error) {
        final cancelled =
            await context.isCancelRequested ||
            await _isCancelRequested(payload.roundId);
        if (cancelled) {
          await _turnRunner.cancelRoom(payload.roomId);
          await _messages.failAssistantReply(
            messageId: message.messageId,
            answerVersionId: answer.answerVersionId,
            failureHint: '已停止',
            cancelled: true,
          );
          _events.emit(
            GroupStepFinished(
              roomId: payload.roomId,
              roundId: payload.roundId,
              messageId: message.messageId,
              status: 'cancelled',
            ),
          );
          await _rounds.settleCancelled(payload.roundId);
          break;
        }
        DebugLogger.instance.error(
          '群聊助手回复失败，已终止本轮',
          tag: 'GroupChat',
          details: error.toString(),
        );
        await _messages.failAssistantReply(
          messageId: message.messageId,
          answerVersionId: answer.answerVersionId,
          failureHint: '回复失败，请检查网络或 API 配置后重试。',
        );
        await _rounds.failRound(
          payload.roundId,
          step.position,
          errorCode: 'GENERATION_FAILED',
        );
        _events.emit(
          GroupStepFinished(
            roomId: payload.roomId,
            roundId: payload.roundId,
            messageId: message.messageId,
            status: 'failed',
          ),
        );
        break;
      }
      await context.updateProgress(
        checkpoint: step.position + 1,
        processedItems: step.position + 1,
        stage: 'group_step_${step.position + 1}',
      );
    }
    final settled = await _rounds.getRound(payload.roundId);
    if (settled?.status == 'completed') {
      await _stableRoundHook?.call(payload.roomId, payload.roundId);
    }
    _events.emit(
      GroupRoundFinished(
        roomId: payload.roomId,
        roundId: payload.roundId,
        status: settled?.status ?? 'failed',
      ),
    );
  }

  Future<bool> _assistantExists(String assistantId) async {
    final database = await _coreDatabase.open();
    final rows = await database.query(
      'assistants',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [assistantId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _runTurnWithCancellation({
    required LocalJobContext context,
    required String roomId,
    required GroupTurnRequest request,
    required void Function(String delta) onDelta,
    required void Function() onSegmentBoundary,
    required GroupTurnCommitter commit,
  }) async {
    var finished = false;
    final running = _turnRunner
        .run(
          request: request,
          onDelta: onDelta,
          onSegmentBoundary: onSegmentBoundary,
          commit: commit,
        )
        .whenComplete(() => finished = true);
    while (!finished) {
      await Future.any<void>([
        running,
        Future<void>.delayed(const Duration(milliseconds: 50)),
      ]);
      if (!finished &&
          (await context.isCancelRequested ||
              await _isCancelRequested(request.roundId))) {
        await _turnRunner.cancelRoom(roomId);
      }
    }
    await running;
  }

  Future<bool> _isCancelRequested(String roundId) async {
    final round = await _rounds.getRound(roundId);
    return round?.status == 'cancel_requested' || round?.status == 'cancelled';
  }
}
