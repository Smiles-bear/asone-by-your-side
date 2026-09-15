part of 'local_chat_service.dart';

extension _LocalChatBrowserSynthesis on LocalChatService {
  Future<BrowserFinalSynthesisOutcome> _completeBrowserFinalSynthesis(
    ({
      BrowserToolTurnCoordinator turn,
      bool gameOfferAttempted,
      List<Map<String, Object?>> messages,
      ModelProtocolAdapter adapter,
      String baseUrl,
      String apiKey,
      String model,
      int maxTokens,
      LocalChatStreamState streamState,
      void Function(String reasoningDelta)? onReasoningDelta,
      CancelToken? cancelToken,
      ChatContextWindowPlanner planner,
      BrowserFinalSynthesisOutcome current,
    })
    request,
  ) => request.turn.completeFinalSynthesis(
    gameOfferAttempted: request.gameOfferAttempted,
    messages: request.messages,
    execute: () async {
      final result = await _executeModelCall(
        adapter: request.adapter,
        baseUrl: request.baseUrl,
        apiKey: request.apiKey,
        model: request.model,
        messages: request.messages,
        maxTokens: request.maxTokens,
        tools: null,
        onDelta: request.streamState.addDelta,
        onReasoningDelta: request.onReasoningDelta,
        cancelToken: request.cancelToken,
      );
      return (
        text: result.text,
        reasoning: result.reasoning,
        usage: result.usage,
      );
    },
    current: request.current,
    estimateInputTokens: () => request.planner.estimateTextTokens(
      jsonEncode(<String, Object?>{'messages': request.messages}),
    ),
    estimateOutputTokens: request.planner.estimateTextTokens,
  );
}

extension _LocalChatBrowserLifecycle on LocalChatService {
  Future<BrowserSearchContinuation?> _resolveBrowserContinuation(
    ({
      LocalChatTurnOrigin origin,
      String assistantId,
      String conversationId,
      String content,
      String? currentMessageId,
    })
    input,
  ) {
    if (input.origin != LocalChatTurnOrigin.user) {
      return Future.value();
    }
    return BrowserSearchContinuationResolver(
      coreDatabase: _coreDatabase,
    ).resolve(
      assistantId: input.assistantId,
      conversationId: input.conversationId,
      currentText: input.content,
      currentMessageId: input.currentMessageId,
    );
  }

  Set<String> _browserForcedToolIds(BrowserSearchContinuation? continuation) =>
      continuation == null ? const <String>{} : BrowserToolIds.all;

  void _appendBrowserContinuationHint(
    List<Map<String, Object?>> systemParts,
    BrowserSearchContinuation? continuation,
  ) {
    if (continuation == null) return;
    final queryHint = continuation.query == null
        ? ''
        : '\n最近搜索词：${continuation.query}';
    systemParts.add({
      'kind': 'system_hint',
      'content':
          '用户正在继续上一轮未完成的网页搜索。'
          '原请求：${continuation.topic}$queryHint。'
          '请使用本轮提供的网页工具继续，不要要求用户重复完整指令。',
    });
  }

  Future<String?> _markBrowserToolStarted(
    ({
      String toolId,
      bool hasAnswerVersion,
      MessageVersionService? messageVersionService,
      String? answerVersionId,
      String? assistantMessageId,
      LocalChatReplyCommitter? replyCommitter,
      LocalChatStreamState streamState,
    })
    input,
  ) async {
    if (!BrowserToolIds.all.contains(input.toolId)) {
      return input.assistantMessageId;
    }
    if (input.hasAnswerVersion) {
      await input.messageVersionService!.markStreamingAnswerToolUsed(
        answerVersionId: input.answerVersionId!,
        messageId: input.assistantMessageId!,
      );
      return input.assistantMessageId;
    }
    if (input.replyCommitter != null) return input.assistantMessageId;
    final persisted = await input.streamState.ensurePersistentMessage();
    final messageId = persisted?.id;
    if (messageId != null) {
      await _coreRepository.markMessageToolUsed(messageId);
    }
    return messageId ?? input.assistantMessageId;
  }

  Map<String, dynamic> _buildToolCallMetadata(
    ({
      Map<String, dynamic> base,
      String requestId,
      String? assistantMessageId,
      String? userMessageId,
      bool deferredActionAllowed,
      bool timestampsEnabled,
      Iterable<String> allowedToolIds,
      String? sessionId,
    })
    input,
  ) => <String, dynamic>{
    ...input.base,
    'request_id': input.requestId,
    if (input.assistantMessageId?.isNotEmpty == true)
      'assistant_message_id': input.assistantMessageId,
    if (input.userMessageId?.isNotEmpty == true)
      'user_message_id': input.userMessageId,
    'deferred_action_allowed': input.deferredActionAllowed,
    'timestamps_enabled': input.timestampsEnabled,
    'allowed_tool_ids': input.allowedToolIds.toList(growable: false),
    if (input.sessionId != null) 'session_id': input.sessionId,
  };

  void _ensureBrowserFinalText(
    BrowserToolTurnCoordinator browserTurn,
    String finalText,
  ) {
    if (browserTurn.hasActualToolCall && finalText.trim().isEmpty) {
      throw StateError('网页搜索最终收尾为空');
    }
  }

  bool? _browserToolUsedValue(BrowserToolTurnCoordinator browserTurn) =>
      browserTurn.hasActualToolCall ? true : null;

  ({String text, bool finalized}) _browserFailureOutcome(
    String? browserFallback,
    String streamText,
  ) =>
      (text: browserFallback ?? streamText, finalized: browserFallback != null);

  Future<void> _persistInterruptedSegments(
    ({
      String messageId,
      LocalChatStreamState streamState,
      String? browserFallback,
    })
    input,
  ) async {
    if (!input.streamState.isContinuous) return;
    await _coreRepository.deleteMessageSegments(input.messageId);
    if (input.browserFallback != null) {
      await _coreRepository.upsertMessageSegment(
        messageId: input.messageId,
        segmentIndex: 0,
        content: input.browserFallback!,
      );
    } else {
      for (
        var index = 0;
        index < input.streamState.completedSegments.length;
        index++
      ) {
        await _coreRepository.upsertMessageSegment(
          messageId: input.messageId,
          segmentIndex: index,
          content: input.streamState.completedSegments[index],
        );
      }
    }
    DebugLogger.instance.info(
      '请求中断 (Continuous)，已保存 segments',
      tag: 'LocalChat',
      details:
          'MessageId: ${input.messageId}\n'
          'Segments: ${input.streamState.completedSegments.length}',
    );
  }

  void _emitHeldBrowserFallback(
    ({
      String? browserFallback,
      bool holdVisibleReply,
      void Function(String delta) onDelta,
    })
    input,
  ) {
    if (input.browserFallback != null && input.holdVisibleReply) {
      input.onDelta(input.browserFallback!);
    }
  }

  String _previousTopicText(
    Map<String, Object?> context, {
    required String? currentMessageId,
  }) {
    final rawMessages =
        (context['all_recent_messages'] ?? context['recent_messages'])
            as List? ??
        const [];
    final previous = <String>[];
    for (final raw in rawMessages.reversed) {
      if (raw is! Map) continue;
      final messageId = raw['message_id']?.toString();
      if (currentMessageId != null && messageId == currentMessageId) continue;
      final role = raw['role']?.toString();
      if (role != 'user' && role != 'assistant') continue;
      final text = raw['content']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      previous.add(text);
      if (previous.length == 2) break;
    }
    return previous.reversed.join('\n');
  }
}
