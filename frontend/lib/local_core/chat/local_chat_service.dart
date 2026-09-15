import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/message.dart';
import '../../services/provider_adapters/adapter_helpers.dart';
import '../../services/provider_adapters/adapter_registry.dart';
import '../../services/provider_adapters/adapter_types.dart';
import '../../services/provider_adapters/gemini_adapter.dart';
import '../../services/provider_adapters/incremental_sse_decoder.dart';
import '../../services/provider_adapters/model_protocol_adapter.dart';
import '../../services/provider_adapters/protocol_context_recorder.dart';
import '../../services/provider_adapters/protocol_types.dart';
import '../../services/provider_adapters/upstream_failure_policy.dart';
import '../../services/debug_logger.dart';
import '../../services/official_model_token_limits.dart';
import '../../services/user_facing_error_policy.dart';
import '../../tool_runtime/sources/browser_tool_ids.dart';
import '../../tool_runtime/tool_executor.dart';
import '../../tool_runtime/tool_result.dart';
import '../assistant_execution_context.dart';
import '../continuous_message_constants.dart';
import '../chat_context_window_planner.dart';
import '../chat_retrieval_context.dart';
import '../core_database.dart';
import '../core_repository.dart';
import '../message_version_service.dart';
import '../token_usage_service.dart';
import 'browser_tool_turn_coordinator.dart';
import 'browser_search_continuation.dart';
import 'chat_engine_strategies.dart';
import 'local_chat_request_message_builder.dart';
import 'local_chat_stream_state.dart';

part 'local_chat_game_offer_state.dart';
part 'local_chat_browser_synthesis.dart';
part 'local_chat_upstream_retry.dart';

class LocalChatGeneratedReply {
  const LocalChatGeneratedReply({
    required this.content,
    required this.segments,
    required this.inputTokens,
    required this.outputTokens,
    required this.toolIds,
    this.reasoning,
  });

  final String content;
  final String? reasoning;
  final List<String> segments;
  final int inputTokens;
  final int outputTokens;
  final List<String> toolIds;
}

typedef LocalChatReplyCommitter =
    Future<Message> Function(LocalChatGeneratedReply reply);

typedef LocalChatReplyPrecommitValidator =
    Future<void> Function(LocalChatGeneratedReply reply);

enum LocalChatTurnOrigin { user, togetherListenAutomaticTrack }

class LocalChatService {
  LocalChatService({
    CoreDatabase? coreDatabase,
    CoreRepository? coreRepository,
    Dio? dio,
    ChatContextCompiler? contextCompiler,
    ChatToolRuntime? toolRuntimeService,
    ChatToolSchemaStrategy? toolSchemaStrategy,
    ChatGameStrategy? gameStrategy,
    ChatSharedActivityStrategy? sharedActivityStrategy,
    ChatDeferredActionHandler? deferredActionHandler,
    ChatAutoDiaryHook? autoDiaryHook,
    Future<void> Function(Duration delay)? retryDelay,
  }) : _coreDatabase = coreDatabase ?? CoreDatabase.instance,
       _coreRepository = coreRepository ?? CoreRepository(),
       _dio = dio ?? Dio(),
       _contextCompiler =
           contextCompiler ??
           ChatEngineBindings.createContextCompiler?.call(
             coreDatabase: coreDatabase,
           ),
       _toolRuntime =
           toolRuntimeService ?? ChatEngineBindings.createToolRuntime?.call(),
       _toolSchema =
           toolSchemaStrategy ??
           ChatEngineBindings.createToolSchemaStrategy?.call(
             coreDatabase: coreDatabase,
           ),
       _gameStrategy =
           gameStrategy ??
           ChatEngineBindings.createGameStrategy?.call(
             coreDatabase: coreDatabase,
           ),
       _sharedActivity =
           sharedActivityStrategy ??
           ChatEngineBindings.createSharedActivityStrategy?.call(
             coreDatabase: coreDatabase,
           ),
       _deferredActions =
           deferredActionHandler ??
           ChatEngineBindings.createDeferredActionHandler?.call(
             coreDatabase: coreDatabase,
           ),
       _autoDiary =
           autoDiaryHook ?? ChatEngineBindings.createAutoDiaryHook?.call(),
       _tokenUsage = TokenUsageService(coreDatabase: coreDatabase),
       _retryDelay = retryDelay ?? Future<void>.delayed;

  final CoreDatabase _coreDatabase;
  final CoreRepository _coreRepository;
  final Dio _dio;
  final ChatContextCompiler? _contextCompiler;
  final ChatToolRuntime? _toolRuntime;
  final ChatToolSchemaStrategy? _toolSchema;
  final ChatGameStrategy? _gameStrategy;
  final ChatSharedActivityStrategy? _sharedActivity;
  final ChatDeferredActionHandler? _deferredActions;
  final ChatAutoDiaryHook? _autoDiary;
  final TokenUsageService _tokenUsage;
  final Future<void> Function(Duration delay) _retryDelay;

  ChatContextCompiler _requiredContextCompiler() {
    final compiler = _contextCompiler;
    if (compiler == null) {
      throw StateError('聊天上下文编译器未装配');
    }
    return compiler;
  }

  ChatToolRuntime _requiredToolRuntime() {
    final runtime = _toolRuntime;
    if (runtime == null) {
      throw StateError('产生工具调用但工具运行时未装配');
    }
    return runtime;
  }

  Future<void> send({
    required String conversationId,
    required String content,
    String? assistantMessageId,
    String? answerVersionId,
    String? cutoffMessageId,
    required bool userAlreadyPersisted,
    required void Function(String delta) onDelta,
    required void Function({String? error}) onDone,
    CancelToken? cancelToken,
    // 可选的预编译上下文，用于 chat_generation 任务快照
    Map<String, Object?>? frozenContext,
    ModelBindingSnapshot? frozenModelSnapshot,
    // Continuous 模式段落边界回调（UI-C3）
    void Function()? onSegmentBoundary,
    // reasoning 流式回调
    void Function(String reasoning)? onReasoningDelta,
    void Function(String toolName)? onToolUse,
    // 主动消息等需要提交前复核的调用可接管最终持久化。
    LocalChatReplyCommitter? replyCommitter,
    LocalChatReplyPrecommitValidator? replyPrecommitValidator,
    LocalChatTurnOrigin origin = LocalChatTurnOrigin.user,
    bool bypassTogetherListenCoordinator = false,
    List<Map<String, Object?>>? recentMessagesOverride,
    Set<String>? systemPartKindsAllowlist,
  }) async {
    if (!bypassTogetherListenCoordinator &&
        origin == LocalChatTurnOrigin.user) {
      final turnCoordinator = ChatEngineBindings.tryRunViaTurnCoordinator;
      if (turnCoordinator != null) {
        final handled = await turnCoordinator(conversationId, () async {
          await send(
            conversationId: conversationId,
            content: content,
            assistantMessageId: assistantMessageId,
            answerVersionId: answerVersionId,
            cutoffMessageId: cutoffMessageId,
            userAlreadyPersisted: userAlreadyPersisted,
            onDelta: onDelta,
            onDone: onDone,
            cancelToken: cancelToken,
            frozenContext: frozenContext,
            frozenModelSnapshot: frozenModelSnapshot,
            onSegmentBoundary: onSegmentBoundary,
            onReasoningDelta: onReasoningDelta,
            onToolUse: onToolUse,
            replyCommitter: replyCommitter,
            replyPrecommitValidator: replyPrecommitValidator,
            origin: origin,
            bypassTogetherListenCoordinator: true,
            recentMessagesOverride: recentMessagesOverride,
            systemPartKindsAllowlist: systemPartKindsAllowlist,
          );
        });
        if (handled) return;
      }
    }
    final hasAnswerVersion =
        assistantMessageId != null &&
        assistantMessageId.isNotEmpty &&
        answerVersionId != null &&
        answerVersionId.isNotEmpty;
    final messageVersionService = hasAnswerVersion
        ? MessageVersionService(coreDatabase: _coreDatabase)
        : null;
    LocalChatStreamState? streamState;
    bool answerVersionFailureFinalized = false;
    final gameOffer = origin == LocalChatTurnOrigin.user
        ? _gameStrategy?.detectOffer(content)
        : null;
    final gameOfferState = _GameOfferState(_gameStrategy);
    bool browserFailureFinalized = false;
    String? deferredActionId;
    bool holdVisibleReply = false;

    Future<void> cancelPreparedAction() async {
      final actionId = deferredActionId;
      if (actionId == null) return;
      await _deferredActions?.cancelPrepared(actionId);
    }

    String? persistedUserMessageId;

    String visibleStreamedContent() {
      return streamState?.visibleContent ?? '';
    }

    Future<void> finalizeAnswerVersionFailure({
      required Object error,
      String? finalContent,
      String? finishReason,
    }) async {
      if (!hasAnswerVersion || answerVersionFailureFinalized) return;
      try {
        final cancelled = finishReason?.trim().toLowerCase() == 'cancelled';
        final resolvedContent = cancelled && (finalContent ?? '').trim().isEmpty
            ? '回复已中断'
            : (finalContent ?? '');
        await messageVersionService!.failStreamingAnswer(
          answerVersionId: answerVersionId,
          messageId: assistantMessageId!,
          finalContent: resolvedContent,
          error: error,
          finishReason: finishReason,
        );
        await _coreRepository.updateMessageContent(
          assistantMessageId!,
          resolvedContent,
          answerStatus: cancelled ? 'cancelled' : 'failed',
          failureHint: cancelled
              ? null
              : UserFacingErrorPolicy.failureHintFor(
                  error,
                  hasPartialContent: resolvedContent.trim().isNotEmpty,
                ),
        );
        answerVersionFailureFinalized = true;
      } catch (finalizeError) {
        DebugLogger.instance.error(
          'Failed to finalize answer version failure state',
          tag: 'LocalChat',
          details: finalizeError.toString(),
        );
      }
    }

    Future<void> finalizeInitialCancellation() async {
      if (hasAnswerVersion || replyCommitter != null) return;
      final streamed = visibleStreamedContent();
      final content = streamed.trim().isEmpty ? '回复已中断' : streamed;
      final messageCreationFuture = streamState?.messageCreationFuture;
      if (messageCreationFuture != null) {
        final created = await messageCreationFuture;
        await _coreRepository.updateMessageContent(
          created.id!,
          content,
          answerStatus: 'cancelled',
        );
      } else {
        await _coreRepository.saveMessage(
          conversationId,
          'assistant',
          content,
          answerStatus: 'cancelled',
        );
      }
    }

    final isContinuousMode =
        frozenContext != null &&
        (frozenContext['reply_mode'] as String? ?? kReplyModeComplete) ==
            kReplyModeContinuous;

    try {
      if (origin == LocalChatTurnOrigin.user && !userAlreadyPersisted) {
        persistedUserMessageId = (await _coreRepository.saveMessage(
          conversationId,
          'user',
          content,
        )).id;
      }
      // 使用冻结上下文或动态解析
      final ModelBindingSnapshot modelSnapshot;
      final String assistantId;
      final Map<String, Object?> context;
      String? requestId;

      if (frozenContext != null && frozenModelSnapshot != null) {
        // 使用预编译的冻结上下文（chat_generation 任务）
        modelSnapshot = frozenModelSnapshot;
        assistantId = frozenContext['assistantId']! as String;
        context = frozenContext;
        requestId = null; // 冻结上下文不需要 requestId
      } else {
        // 动态解析（普通聊天）：上下文编译器为接缝——私有版由绑定挂载
        // （执行上下文解析 + 上下文冻结编译），公开版装配基础实现。
        final turnContext = await _requiredContextCompiler().compileTurnContext(
          conversationId: conversationId,
          query: origin == LocalChatTurnOrigin.user ? content : '',
          excludedMessageId: hasAnswerVersion ? assistantMessageId : null,
          currentMessageId: cutoffMessageId,
        );

        assistantId = turnContext.assistantId;
        modelSnapshot = turnContext.modelSnapshot;
        requestId = turnContext.requestId;
        context = turnContext.context;
      }

      final externalReplyLifecycle =
          context['external_reply_lifecycle'] == true;
      if (externalReplyLifecycle && replyCommitter == null) {
        throw StateError('外部回复生命周期必须提供回复提交器');
      }
      final toolContextMetadata = _toolContextMetadata(
        context: context,
        assistantId: assistantId,
        conversationId: conversationId,
      );
      final toolIdDenylist =
          ((context['tool_id_denylist'] as List?) ?? const [])
              .whereType<String>()
              .toSet();

      final baseUrl = modelSnapshot.baseUrl;
      final apiKey = modelSnapshot.apiKey;
      final model = modelSnapshot.model;
      final protocolType = modelSnapshot.protocolType;

      // 记录对话开始
      DebugLogger.instance.info(
        '开始本地聊天',
        tag: 'LocalChat',
        details:
            'ConversationId: $conversationId\nAssistantId: $assistantId\nModel: $model',
      );

      // 解析协议适配器
      if (protocolType == ProtocolType.auto) {
        const message = '模型服务协议尚未确定，请先完成模型能力检测';
        DebugLogger.instance.error(message, tag: 'LocalChat');
        await finalizeAnswerVersionFailure(error: message, finalContent: '');
        onDone(error: message);
        return;
      }
      final ModelProtocolAdapter adapter = AdapterRegistry.instance.get(
        protocolType,
      );

      var maxOutputTokens = context['max_output_tokens'] as int;
      final timestampsEnabled = (context['timestamps_enabled'] as int) == 1;
      final activeListen = externalReplyLifecycle
          ? null
          : await _sharedActivity?.resolveActiveListen(
              assistantId: assistantId,
              conversationId: conversationId,
            );
      final activityId = activeListen?.activityId;
      final currentMessageId =
          context['current_message_id'] as String? ?? persistedUserMessageId;
      if (activityId != null && currentMessageId != null) {
        await _linkTogetherListenMessage(
          activityId: activityId,
          assistantId: assistantId,
          conversationId: conversationId,
          chatMessageId: currentMessageId,
          origin: ChatSharedActivityOrigins.userInput,
        );
      }

      final toolsEnabled = context['tools_enabled'] as bool? ?? true;
      final browserContinuation = await _resolveBrowserContinuation((
        origin: origin,
        assistantId: assistantId,
        conversationId: conversationId,
        content: content,
        currentMessageId: currentMessageId,
      ));
      // 工具 schema 为接缝：公开版未装配 → 空 schema（Q3：工具循环保留但禁用）。
      final toolSetup =
          await _toolSchema?.prepareToolSchema(
            ChatToolSchemaRequest(
              assistantId: assistantId,
              conversationId: conversationId,
              modelServiceId: modelSnapshot.modelServiceId,
              timestampsEnabled: timestampsEnabled,
              toolsEnabled: toolsEnabled,
              queryText: content,
              previousText: _previousTopicText(
                context,
                currentMessageId: currentMessageId,
              ),
              hasAnswerVersion: hasAnswerVersion,
              automaticTogetherListenTurn:
                  origin == LocalChatTurnOrigin.togetherListenAutomaticTrack,
              forceGameOffer: gameOffer != null,
              forcedRelevantToolIds: _browserForcedToolIds(browserContinuation),
              toolIdDenylist: toolIdDenylist,
              sessionId: activeListen?.sessionId,
              allowedToolIds: (context['allowed_tool_ids'] as List?)
                  ?.whereType<String>()
                  .toSet(),
            ),
          ) ??
          const ChatToolSchemaSetup.empty();
      final tools = toolSetup.tools;
      final aliasToToolId = toolSetup.aliasToToolId;
      final candidateToolIds = toolSetup.candidateToolIds;
      final excludedToolReasons = toolSetup.excludedToolReasons;
      final executedToolIds = <String>[];
      var successfulToolUsed = false;
      final browserTurn = browserToolTurn(aliasToToolId.values);
      holdVisibleReply = browserTurn.hold(toolSetup.holdVisibleReply);
      final canOfferGame =
          gameOffer != null &&
          aliasToToolId.containsKey(_gameStrategy!.offerToolName);
      if (canOfferGame) holdVisibleReply = true;
      final activeStreamState = LocalChatStreamState(
        continuous: isContinuousMode,
        holdVisibleReply: holdVisibleReply,
        onDelta: onDelta,
        onSegmentBoundary: onSegmentBoundary,
        createStreamingMessage: !hasAnswerVersion && replyCommitter == null
            ? (initialContent) => _coreRepository.saveMessage(
                conversationId,
                'assistant',
                initialContent,
                answerStatus: 'streaming',
              )
            : null,
        onMessageCreated: (savedMessage) {
          assistantMessageId = savedMessage.id;
        },
      );
      streamState = activeStreamState;

      var sourceSystemParts =
          ((context['all_system_parts'] ?? context['system_parts']) as List)
              .map((item) => (item as Map).cast<String, Object?>())
              .toList(growable: true);
      if (systemPartKindsAllowlist != null) {
        sourceSystemParts = sourceSystemParts
            .where(
              (part) =>
                  systemPartKindsAllowlist.contains(part['kind'] as String?),
            )
            .toList(growable: true);
      }
      if (canOfferGame) {
        sourceSystemParts.add({
          'kind': 'system_hint',
          'content': _gameStrategy.suspectedInvitationHint(gameOffer.gameName),
        });
      }
      _appendBrowserContinuationHint(sourceSystemParts, browserContinuation);
      if (activeListen != null) {
        sourceSystemParts.add({
          'kind': 'together_listen_state',
          'content': activeListen.systemContextBody,
        });
      }
      if (origin == LocalChatTurnOrigin.togetherListenAutomaticTrack &&
          _sharedActivity != null) {
        sourceSystemParts.add({
          'kind': 'together_listen_event',
          'content': _sharedActivity.automaticTrackEventText.trim(),
        });
      }
      final sourceRecentMessages =
          (recentMessagesOverride ??
                  ((context['all_recent_messages'] ??
                              context['recent_messages'])
                          as List)
                      .map((item) => (item as Map).cast<String, Object?>())
                      .toList(growable: false))
              .map((item) => (item as Map).cast<String, Object?>())
              .map(
                (item) => activeListen == null
                    ? item
                    : _markTogetherListenSource(
                        item,
                        sessionStartedAt: activeListen.sessionCreatedAt,
                      ),
              )
              .toList(growable: false);
      final retrievalContext = gameOffer == null
          ? ChatRetrievalContext.fromJsonString(
              context['retrieval_context'] as String? ?? '{}',
            )
          : const ChatRetrievalContext([]);
      final contextWindow = context['context_window'] as int? ?? 100000;
      final catalogLimits = OfficialModelTokenLimitCatalog.match(
        baseUrl: modelSnapshot.baseUrl,
        model: modelSnapshot.model,
        protocolType: modelSnapshot.protocolType,
      );
      final knownModelContextWindow =
          context['model_context_window'] as int? ??
          catalogLimits?.contextWindow;
      final knownModelMaxOutputTokens =
          context['model_max_output_tokens'] as int? ??
          catalogLimits?.maxOutputTokens;
      final knownModelMaxInputTokens =
          context['model_max_input_tokens'] as int? ??
          catalogLimits?.maxInputTokens;
      final toolRequestId =
          requestId ??
          currentMessageId ??
          'chat:$conversationId:${DateTime.now().microsecondsSinceEpoch}';
      final planner = ChatContextWindowPlanner();
      final toolChainMessages = <Map<String, Object?>>[];
      var plan = planner.plan(
        contextWindow: contextWindow,
        maxOutputTokens: maxOutputTokens,
        systemParts: sourceSystemParts,
        recentMessages: sourceRecentMessages,
        currentMessageId: currentMessageId,
        knownModelContextWindow: knownModelContextWindow,
        knownModelMaxOutputTokens: knownModelMaxOutputTokens,
        knownModelMaxInputTokens: knownModelMaxInputTokens,
        retrievalContext: retrievalContext,
        tools: tools,
      );
      maxOutputTokens = plan.maxOutputTokens;
      const maxToolRounds = 4;
      int round = 0;
      final requestMessageBuilder = LocalChatRequestMessageBuilder(
        readAttachmentBytes: _coreRepository.readAttachmentBytes,
      );
      var conversationMessages = await requestMessageBuilder.build(plan);
      String finalAssistantText = '';
      String finalAssistantReasoning = ''; // 累积所有轮次的 reasoning
      int totalInputTokens = 0;
      int totalOutputTokens = 0;
      int modelRequestCount = 0;
      bool usageEstimated = false;

      // 记录请求上下文，供开发者→上下文检查器查看（接缝：私有侧挂载
      // ProtocolContextRecorder.current，公开版为 null 即不记录）。
      ProtocolContextRecorder.current?.recordRequest(
        modelId: model,
        messages: conversationMessages.cast<Map<String, dynamic>>(),
        baseUrl: baseUrl,
        maxTokens: maxOutputTokens,
        temperature: 0.7,
        protocol: protocolType,
        conversationId: conversationId,
        assistantId: assistantId,
        systemParts: plan.systemParts,
        recentMessages: plan.recentMessages,
        contextMetadata: {
          'max_output_tokens': maxOutputTokens,
          'timestamps_enabled': context['timestamps_enabled'],
          'priority': context['priority'],
          'history_trimmed': plan.historyTrimmed,
          'input_token_ceiling': plan.inputTokenCeiling,
          'estimated_input_tokens': plan.estimatedInputTokens,
          'candidate_tool_ids': candidateToolIds,
          'provided_tool_ids': aliasToToolId.values.toList(growable: false),
          'provided_tool_count': tools.length,
          'excluded_tool_reasons': excludedToolReasons,
          'request_tools': tools,
          if (context['group_context_audit'] != null)
            'group_context_audit': context['group_context_audit'],
          ...toolContextMetadata,
        },
      );

      try {
        while (round < maxToolRounds) {
          round++;

          // 执行模型调用
          final result = await _executeModelCallWithRetry(
            adapter: adapter,
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: conversationMessages,
            maxTokens: maxOutputTokens,
            tools: tools.isNotEmpty ? tools : null,
            onDelta: (delta) {
              activeStreamState.addDelta(delta);
            },
            onReasoningDelta: onReasoningDelta, // 传递 reasoning 回调
            cancelToken: cancelToken,
          );
          modelRequestCount++;

          finalAssistantText = result.text;
          // 累积 reasoning（多轮工具调用情况下可能有多段）
          if (result.reasoning.isNotEmpty) {
            if (finalAssistantReasoning.isNotEmpty) {
              finalAssistantReasoning += '\n\n';
            }
            finalAssistantReasoning += result.reasoning;
          }

          // 累积 token 使用
          if (result.usage != null) {
            totalInputTokens += result.usage!['input_tokens'] ?? 0;
            totalOutputTokens += result.usage!['output_tokens'] ?? 0;
          } else {
            usageEstimated = true;
            totalInputTokens += planner.estimateTextTokens(
              jsonEncode(<String, Object?>{
                'messages': conversationMessages,
                if (tools.isNotEmpty) 'tools': tools,
              }),
            );
            totalOutputTokens += planner.estimateTextTokens(
              '${result.reasoning}\n${result.text}',
            );
          }

          if (result.toolCalls.isEmpty) {
            if (browserTurn.continueAfterNoToolCall(
              round,
              maxToolRounds,
              conversationMessages,
              toolChainMessages,
            )) {
              continue;
            }
            break;
          }
          browserTurn.markToolCallsPresent();

          final assistantToolMessage = <String, Object?>{
            'role': 'assistant',
            'content': finalAssistantText,
            'tool_calls': result.toolCalls
                .map(
                  (call) => {
                    'id': call.id,
                    'type': 'function',
                    'function': {
                      'name': call.name,
                      'arguments': jsonEncode(call.arguments),
                    },
                  },
                )
                .toList(),
          };
          conversationMessages.add(assistantToolMessage);
          toolChainMessages.add(assistantToolMessage);

          // 执行每个工具并添加结果（静默，不通过 onDelta 回显）
          // 统一走 Tool Runtime（§8：策略/预算/审计生效，§57 统一错误码）
          // 接缝：公开版工具 schema 为空，正常不会产生 tool_calls，此为防御分支。
          final toolRuntime = _requiredToolRuntime();
          for (final toolCall in result.toolCalls) {
            final toolId = toolRuntime.resolveToolId(
              toolCall.name,
              aliasToToolId,
            );
            browserTurn.markToolCall(
              toolId: toolId,
              arguments: toolCall.arguments.cast<String, dynamic>(),
            );
            assistantMessageId = await _markBrowserToolStarted((
              toolId: toolId,
              hasAnswerVersion: hasAnswerVersion,
              messageVersionService: messageVersionService,
              answerVersionId: answerVersionId,
              assistantMessageId: assistantMessageId,
              replyCommitter: replyCommitter,
              streamState: activeStreamState,
            ));
            onToolUse?.call(toolCall.name);
            executedToolIds.add(toolId);
            final callMetadata = _buildToolCallMetadata((
              base: toolContextMetadata,
              requestId: toolRequestId,
              assistantMessageId: assistantMessageId,
              userMessageId: currentMessageId,
              deferredActionAllowed: deferredActionId == null,
              timestampsEnabled: timestampsEnabled,
              allowedToolIds: aliasToToolId.values,
              sessionId: activeListen?.sessionId,
            ));
            ChatEngineBindings.decorateToolCallMetadata?.call(
              callMetadata,
              plan,
              cancelToken,
              toolChainMessages,
            );
            var toolResult = await toolRuntime.executeTool(
              call: ToolCall(
                toolId: toolId,
                callId: toolCall.id,
                arguments: toolCall.arguments.cast<String, dynamic>(),
              ),
              context: ToolContext(
                assistantId: assistantId,
                conversationId: conversationId,
                metadata: callMetadata,
              ),
            );
            toolResult = await toolRuntime.awaitUserConfirmation(
              call: ToolCall(
                toolId: toolId,
                callId: toolCall.id,
                arguments: toolCall.arguments.cast<String, dynamic>(),
              ),
              context: ToolContext(
                assistantId: assistantId,
                conversationId: conversationId,
                metadata: callMetadata,
              ),
              initialResult: toolResult,
            );
            if (toolResult.isSuccess) successfulToolUsed = true;
            browserTurn.recordResult(toolId: toolId, result: toolResult);

            final preparedActionId = toolResult.isSuccess
                ? (toolResult.data?['deferredActionId'] as String?)
                : null;
            if (preparedActionId != null && preparedActionId.isNotEmpty) {
              deferredActionId = preparedActionId;
            }

            final recallMedia = await _gameStrategy?.buildRecallMedia(
              toolName: toolCall.name,
              toolResult: toolResult,
              modelServiceId: modelSnapshot.modelServiceId,
              assistantId: assistantId,
              conversationId: conversationId,
            );
            final toolMessage = <String, Object?>{
              'role': 'tool',
              'tool_call_id': toolCall.id,
              'content': recallMedia == null
                  ? _toolResultToContent(toolResult)
                  : recallMedia.toolContent,
            };
            conversationMessages.add(toolMessage);
            toolChainMessages.add(toolMessage);
            if (recallMedia?.mediaMessage case final mediaMessage?) {
              conversationMessages.add(mediaMessage);
              toolChainMessages.add(mediaMessage);
            }
            gameOfferState.record(toolName: toolCall.name, result: toolResult);
          }

          // A successful game offer is already represented by the structured
          // card. Finish with product-owned copy instead of asking the model
          // for a second, potentially text-board-oriented response.
          if (gameOfferState.attempted) break;

          plan = planner.plan(
            contextWindow: contextWindow,
            maxOutputTokens: maxOutputTokens,
            systemParts: sourceSystemParts,
            recentMessages: sourceRecentMessages,
            currentMessageId: currentMessageId,
            knownModelContextWindow: knownModelContextWindow,
            knownModelMaxOutputTokens: knownModelMaxOutputTokens,
            knownModelMaxInputTokens: knownModelMaxInputTokens,
            retrievalContext: retrievalContext,
            tools: tools,
            toolMessages: toolChainMessages,
          );
          maxOutputTokens = plan.maxOutputTokens;
          conversationMessages = [
            ...await requestMessageBuilder.build(plan),
            ...toolChainMessages,
          ];

          // 如果达到最大轮数，退出
          if (browserTurn.shouldStopToolLoop(round, maxToolRounds)) {
            break;
          }
        }

        final synthesis = await _completeBrowserFinalSynthesis((
          turn: browserTurn,
          gameOfferAttempted: gameOfferState.attempted,
          messages: conversationMessages,
          adapter: adapter,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          maxTokens: maxOutputTokens,
          streamState: activeStreamState,
          onReasoningDelta: onReasoningDelta,
          cancelToken: cancelToken,
          planner: planner,
          current: BrowserFinalSynthesisOutcome(
            text: finalAssistantText,
            reasoning: finalAssistantReasoning,
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            modelRequestCount: modelRequestCount,
            usageEstimated: usageEstimated,
          ),
        ));
        finalAssistantText = synthesis.text;
        finalAssistantReasoning = synthesis.reasoning;
        totalInputTokens = synthesis.inputTokens;
        totalOutputTokens = synthesis.outputTokens;
        modelRequestCount = synthesis.modelRequestCount;
        usageEstimated = synthesis.usageEstimated;
        _ensureBrowserFinalText(browserTurn, finalAssistantText);
      } catch (e) {
        // 流式生成过程中发生中断（取消、网络错误等）
        activeStreamState.finish();

        // 使用安全正文更新 message
        final interrupted = cancelToken?.isCancelled == true;
        final browserFallback = browserTurn.localFailureText(
          e,
          cancelled: interrupted,
        );
        final browserFailure = _browserFailureOutcome(
          browserFallback,
          activeStreamState.finalText,
        );
        final finalText = browserFailure.text;
        browserFailureFinalized = browserFailure.finalized;
        if (hasAnswerVersion) {
          await finalizeAnswerVersionFailure(
            error: e,
            finalContent: finalText,
            finishReason: interrupted ? 'cancelled' : null,
          );
        } else if (activeStreamState.messageCreationFuture != null &&
            finalText.isNotEmpty) {
          final createdMessage = await activeStreamState.messageCreationFuture!;
          final messageId = createdMessage.id!;

          DebugLogger.instance.info(
            '请求中断，更新已生成内容',
            tag: 'LocalChat',
            details: 'MessageId: $messageId\n已生成长度: ${finalText.length}',
          );

          await _coreRepository.updateMessageContent(
            messageId,
            finalText,
            reasoning: finalAssistantReasoning.isNotEmpty
                ? finalAssistantReasoning
                : null,
            answerStatus: interrupted ? 'cancelled' : 'failed',
            failureHint: interrupted
                ? null
                : UserFacingErrorPolicy.failureHintFor(
                    e,
                    hasPartialContent: finalText.trim().isNotEmpty,
                  ),
            toolUsed: _browserToolUsedValue(browserTurn),
          );

          await _persistInterruptedSegments((
            messageId: messageId,
            streamState: activeStreamState,
            browserFallback: browserFallback,
          ));
        }
        _emitHeldBrowserFallback((
          browserFallback: browserFallback,
          holdVisibleReply: holdVisibleReply,
          onDelta: onDelta,
        ));
        await cancelPreparedAction();
        rethrow;
      }

      activeStreamState.finish();

      successfulToolUsed = executedToolIds.isNotEmpty;

      final browserFinalText = browserTurn.selectFinalText(
        activeStreamState.isContinuous,
        activeStreamState.finalText,
        finalAssistantText,
      );
      final finalText = gameOfferState.succeeded
          ? gameOffer!.direction == ChatGameOfferDirection.assistantInvitesUser
                ? '邀请已发出，点击卡片回应。'
                : '邀请已接受，点击卡片开始。'
          : browserFinalText;

      if (gameOfferState.attempted &&
          (!gameOfferState.succeeded || gameOfferState.failed)) {
        final error = StateError('游戏邀请工具调用失败');
        if (hasAnswerVersion) {
          await finalizeAnswerVersionFailure(
            error: error,
            finalContent: finalText,
          );
        } else if (activeStreamState.messageCreationFuture != null &&
            finalText.isNotEmpty) {
          final createdMessage = await activeStreamState.messageCreationFuture!;
          await _coreRepository.updateMessageContent(
            createdMessage.id!,
            finalText,
            reasoning: finalAssistantReasoning.isNotEmpty
                ? finalAssistantReasoning
                : null,
            answerStatus: 'failed',
            failureHint: UserFacingErrorPolicy.failureHintFor(error),
          );
          if (activeStreamState.isContinuous) {
            for (
              var index = 0;
              index < activeStreamState.completedSegments.length;
              index++
            ) {
              await _coreRepository.upsertMessageSegment(
                messageId: createdMessage.id!,
                segmentIndex: index,
                content: activeStreamState.completedSegments[index],
              );
            }
          }
        }
        throw error;
      }

      // 正常完成：如果有可见正文才保存
      if (finalText.trim().isEmpty) {
        DebugLogger.instance.error(
          '模型响应为空',
          tag: 'LocalChat',
          details: 'ConversationId: $conversationId',
        );
        throw StateError('模型没有返回内容');
      }

      // 如果已创建 message 则更新，否则创建。用户可见动作走两阶段协调器：
      // 原生动作核验成功（或明确转入系统确认页）后，才提交并展示正文。
      final Message savedMessage;
      var committedText = finalText;
      var committedSegments = gameOfferState.succeeded || browserTurn.enabled
          ? <String>[finalText]
          : List<String>.from(activeStreamState.completedSegments);
      final generatedReply = LocalChatGeneratedReply(
        content: finalText,
        reasoning: finalAssistantReasoning.isEmpty
            ? null
            : finalAssistantReasoning,
        segments: List.unmodifiable(committedSegments),
        inputTokens: totalInputTokens,
        outputTokens: totalOutputTokens,
        toolIds: List.unmodifiable(executedToolIds.toSet()),
      );
      await replyPrecommitValidator?.call(generatedReply);
      if (cancelToken?.isCancelled == true) {
        await cancelPreparedAction();
        throw StateError('生成已取消');
      }
      final actionHandler = _deferredActions;
      if (deferredActionId != null && actionHandler != null) {
        final actionResult = await actionHandler.executeAndCommit(
          actionId: deferredActionId,
          draftMessage: finalText,
          commitMessage: (text) async {
            if (replyCommitter != null) {
              final usesModelDraft = text == finalText;
              return replyCommitter(
                LocalChatGeneratedReply(
                  content: text,
                  reasoning:
                      usesModelDraft && finalAssistantReasoning.isNotEmpty
                      ? finalAssistantReasoning
                      : null,
                  segments: usesModelDraft
                      ? List.unmodifiable(activeStreamState.completedSegments)
                      : List.unmodifiable([text]),
                  inputTokens: totalInputTokens,
                  outputTokens: totalOutputTokens,
                  toolIds: generatedReply.toolIds,
                ),
              );
            }
            if (hasAnswerVersion) {
              await _coreRepository.updateMessageContent(
                assistantMessageId!,
                text,
                reasoning:
                    text == finalText && finalAssistantReasoning.isNotEmpty
                    ? finalAssistantReasoning
                    : null,
                toolUsed: successfulToolUsed,
              );
              return Message(
                id: assistantMessageId,
                role: 'assistant',
                content: text,
                reasoning:
                    text == finalText && finalAssistantReasoning.isNotEmpty
                    ? finalAssistantReasoning
                    : null,
                toolUsed: successfulToolUsed,
              );
            }
            return _coreRepository.saveMessage(
              conversationId,
              'assistant',
              text,
              reasoning: text == finalText && finalAssistantReasoning.isNotEmpty
                  ? finalAssistantReasoning
                  : null,
              toolUsed: successfulToolUsed,
            );
          },
        );
        final committedMessage = actionResult.message;
        if (committedMessage == null) {
          throw StateError(actionResult.failureMessage ?? '动作失败且没有可提交的说明');
        }
        savedMessage = committedMessage;
        committedText = committedMessage.content;
        if (committedText != finalText || committedSegments.isEmpty) {
          committedSegments = [committedText];
        }
        if (hasAnswerVersion) {
          await messageVersionService!.completeStreamingAnswer(
            answerVersionId: answerVersionId,
            messageId: assistantMessageId!,
            finalContent: committedText,
            promptTokens: totalInputTokens > 0 ? totalInputTokens : null,
            completionTokens: totalOutputTokens > 0 ? totalOutputTokens : null,
            reasoning: savedMessage.reasoning,
            toolUsed: successfulToolUsed,
          );
        }
      } else if (replyCommitter != null) {
        savedMessage = await replyCommitter(generatedReply);
        if (hasAnswerVersion) {
          await messageVersionService!.completeStreamingAnswer(
            answerVersionId: answerVersionId,
            messageId: assistantMessageId!,
            finalContent: savedMessage.content,
            promptTokens: totalInputTokens > 0 ? totalInputTokens : null,
            completionTokens: totalOutputTokens > 0 ? totalOutputTokens : null,
            reasoning: savedMessage.reasoning,
            toolUsed: successfulToolUsed,
          );
        }
      } else if (hasAnswerVersion) {
        await messageVersionService!.completeStreamingAnswer(
          answerVersionId: answerVersionId,
          messageId: assistantMessageId!,
          finalContent: finalText,
          promptTokens: totalInputTokens > 0 ? totalInputTokens : null,
          completionTokens: totalOutputTokens > 0 ? totalOutputTokens : null,
          reasoning: finalAssistantReasoning.isEmpty
              ? null
              : finalAssistantReasoning,
          toolUsed: successfulToolUsed,
        );
        savedMessage = Message(
          id: assistantMessageId,
          role: 'assistant',
          content: finalText,
          createdAt: DateTime.now(),
          reasoning: finalAssistantReasoning.isNotEmpty
              ? finalAssistantReasoning
              : null,
          toolUsed: successfulToolUsed,
        );
      } else if (activeStreamState.messageCreationFuture != null) {
        // 等待首次创建完成
        final createdMessage = await activeStreamState.messageCreationFuture!;
        final messageId = createdMessage.id!;

        await _coreRepository.updateMessageContent(
          messageId,
          finalText,
          reasoning: finalAssistantReasoning.isNotEmpty
              ? finalAssistantReasoning
              : null,
          answerStatus: 'completed',
          toolUsed: successfulToolUsed,
        );
        savedMessage = Message(
          id: messageId,
          role: 'assistant',
          content: finalText,
          createdAt: DateTime.now(),
          reasoning: finalAssistantReasoning.isNotEmpty
              ? finalAssistantReasoning
              : null,
          answerStatus: 'completed',
          toolUsed: successfulToolUsed,
        );
      } else {
        final dbMessage = await _coreRepository.saveMessage(
          conversationId,
          'assistant',
          finalText,
          reasoning: finalAssistantReasoning.isNotEmpty
              ? finalAssistantReasoning
              : null,
          answerStatus: 'completed',
          toolUsed: successfulToolUsed,
        );
        savedMessage = dbMessage;
      }
      if (!externalReplyLifecycle &&
          successfulToolUsed &&
          savedMessage.id != null) {
        await _coreRepository.markMessageToolUsed(savedMessage.id!);
      }

      if (holdVisibleReply) {
        if (!activeStreamState.isContinuous) {
          onDelta(committedText);
        } else {
          for (var index = 0; index < committedSegments.length; index++) {
            onDelta(committedSegments[index]);
            if (index < committedSegments.length - 1) {
              onSegmentBoundary?.call();
            }
          }
        }
      }

      if (!externalReplyLifecycle &&
          activityId != null &&
          savedMessage.id != null) {
        await _linkTogetherListenMessage(
          activityId: activityId,
          assistantId: assistantId,
          conversationId: conversationId,
          chatMessageId: savedMessage.id!,
          origin: origin == LocalChatTurnOrigin.togetherListenAutomaticTrack
              ? ChatSharedActivityOrigins.automaticTrackEvent
              : ChatSharedActivityOrigins.userInput,
        );
      }

      // 记录 Token 使用
      if (totalInputTokens > 0 || totalOutputTokens > 0) {
        try {
          await _tokenUsage.recordUsage(
            assistantId: assistantId,
            taskType: context['task_type'] as String? ?? 'chat',
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            requestCount: modelRequestCount,
            modelServiceId: modelSnapshot.modelServiceId,
            model: model,
            protocolType: protocolType,
            isEstimated: usageEstimated,
            requestId: context['request_id'] as String? ?? requestId,
            conversationId: conversationId,
            messageId: savedMessage.id,
          );
        } catch (e) {
          // Token 记录失败不影响聊天功能
          DebugLogger.instance.error(
            'Token 使用记录失败',
            tag: 'LocalChat',
            details: e.toString(),
          );
        }
      }

      // Continuous 模式：写入 message_segments
      if (activeStreamState.isContinuous &&
          replyCommitter == null &&
          savedMessage.id != null) {
        for (int i = 0; i < committedSegments.length; i++) {
          await _coreRepository.upsertMessageSegment(
            messageId: savedMessage.id!,
            segmentIndex: i,
            content: committedSegments[i],
          );
        }

        DebugLogger.instance.info(
          '聊天完成 (Continuous)',
          tag: 'LocalChat',
          details:
              'ConversationId: $conversationId\nMessage ID: ${savedMessage.id}\nSegments: ${committedSegments.length}\nResponse length: ${committedText.length}\nRounds: $round\nTokens: $totalInputTokens in, $totalOutputTokens out',
        );
      } else {
        DebugLogger.instance.info(
          '聊天完成',
          tag: 'LocalChat',
          details:
              'ConversationId: $conversationId\nResponse length: ${committedText.length}\nRounds: $round\nTokens: $totalInputTokens in, $totalOutputTokens out',
        );
      }

      final gameSummarySessionId = externalReplyLifecycle
          ? null
          : context['game_summary_session_id'] as String?;
      if (gameSummarySessionId != null && gameSummarySessionId.isNotEmpty) {
        try {
          await _gameStrategy?.consumeTurn(
            sessionId: gameSummarySessionId,
            assistantId: assistantId,
            conversationId: conversationId,
          );
        } catch (error) {
          DebugLogger.instance.error(
            '游戏摘要上下文计数更新失败',
            tag: 'LocalChat',
            details: error.toString(),
          );
        }
      }
      final sharedActivitySummaryId = externalReplyLifecycle
          ? null
          : context['shared_activity_summary_id'] as String?;
      if (sharedActivitySummaryId != null &&
          sharedActivitySummaryId.isNotEmpty) {
        try {
          await _sharedActivity?.consumeTurn(
            activityId: sharedActivitySummaryId,
            assistantId: assistantId,
            conversationId: conversationId,
          );
        } catch (error) {
          DebugLogger.instance.error(
            '共同活动摘要上下文计数更新失败',
            tag: 'LocalChat',
            details: error.toString(),
          );
        }
      }

      // 聊天完成后检查自动日记资格并触发（接缝：公开版为 null，
      // 降级日记由公开侧另行接线，不走本钩子）
      if (!externalReplyLifecycle) {
        _autoDiary?.onChatCompleted(assistantId, conversationId);
      }

      onDone();
    } on DioException catch (error) {
      await cancelPreparedAction();
      if (browserFailureFinalized) {
        onDone(error: error.toString());
        return;
      }
      if (CancelToken.isCancel(error)) {
        await finalizeInitialCancellation();
        await finalizeAnswerVersionFailure(
          error: error,
          finalContent: visibleStreamedContent(),
          finishReason: 'cancelled',
        );
        DebugLogger.instance.info('请求已取消', tag: 'LocalChat');
        onDone(error: '已取消');
      } else {
        await finalizeAnswerVersionFailure(
          error: error,
          finalContent: streamState?.finalText ?? '',
        );
        DebugLogger.instance.error(
          '网络错误',
          tag: 'LocalChat',
          details: error.message ?? error.toString(),
        );
        onDone(error: '网络错误: ${error.message ?? error}');
      }
    } catch (error) {
      await cancelPreparedAction();
      if (browserFailureFinalized) {
        onDone(error: error.toString());
        return;
      }
      final cancelled =
          error is StateError &&
          (error.message == '已取消' || error.message == '生成已取消');
      if (cancelled) {
        await finalizeInitialCancellation();
        await finalizeAnswerVersionFailure(
          error: error,
          finalContent: visibleStreamedContent(),
          finishReason: 'cancelled',
        );
        DebugLogger.instance.info('请求已取消', tag: 'LocalChat');
        onDone(error: '已取消');
        return;
      }
      await finalizeAnswerVersionFailure(
        error: error,
        finalContent: streamState?.finalText ?? '',
      );
      DebugLogger.instance.error(
        error is HttpException || error is SocketException ? '连接中断' : '生成失败',
        tag: 'LocalChat',
        details: error.toString(),
      );
      onDone(error: error.toString());
    }
  }

  Map<String, dynamic> _toolContextMetadata({
    required Map<String, Object?> context,
    required String assistantId,
    required String conversationId,
  }) {
    final metadata = <String, dynamic>{};
    final rawMetadata = context['tool_context_metadata'];
    if (rawMetadata is Map) {
      for (final entry in rawMetadata.entries) {
        if (entry.key is String) metadata[entry.key as String] = entry.value;
      }
    }
    metadata['assistant_id'] = assistantId;
    metadata['conversation_id'] = conversationId;
    for (final key in const [
      'channel_type',
      'group_room_id',
      'group_round_id',
      'group_message_id',
    ]) {
      final value = context[key];
      if (value != null) metadata[key] = value;
    }
    return metadata;
  }

  /// 把 ToolResult 转为 role=tool 内容（§9：结果回模型，由模型决定下一步）
  ///
  /// 错误结果同样回传（§21/§22：模型可换方式、告诉用户或放弃），
  /// 不中断工具循环。
  Map<String, Object?> _markTogetherListenSource(
    Map<String, Object?> item, {
    required DateTime sessionStartedAt,
  }) {
    final createdAt = DateTime.tryParse(item['created_at'] as String? ?? '');
    final source = createdAt != null && !createdAt.isBefore(sessionStartedAt)
        ? '当前一起听讨论'
        : '原聊天窗口';
    return {
      ...item,
      'content': '【$source】\n${item['content'] as String? ?? ''}',
      'interaction_source': source,
    };
  }

  Future<void> _linkTogetherListenMessage({
    required String activityId,
    required String assistantId,
    required String conversationId,
    required String chatMessageId,
    required String origin,
  }) async {
    try {
      await _sharedActivity?.linkMessage(
        activityId: activityId,
        assistantId: assistantId,
        conversationId: conversationId,
        chatMessageId: chatMessageId,
        origin: origin,
      );
    } catch (error) {
      DebugLogger.instance.error(
        'TogetherListen 消息关联失败',
        tag: 'LocalChat',
        details: error.toString(),
      );
    }
  }

  String _toolResultToContent(ToolResult result) {
    if (result.isSuccess) {
      final text = result.data?['text'];
      if (text is String) {
        return text;
      }
      try {
        return jsonEncode(result.data ?? const {});
      } catch (_) {
        return '${result.data}';
      }
    }
    return '工具调用失败（${result.errorCode ?? 'UNKNOWN'}）：'
        '${result.errorMessage ?? ''}';
  }

  /// 执行单次模型调用（流式），返回 (textContent, reasoning, toolCalls, usage)。
  Future<
    ({
      String text,
      String reasoning,
      List<ProviderToolCall> toolCalls,
      Map<String, int>? usage,
    })
  >
  _executeModelCall({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, Object?>> messages,
    required int maxTokens,
    required List<Map<String, Object?>>? tools,
    required void Function(String delta) onDelta,
    void Function(String reasoningDelta)? onReasoningDelta,
    CancelToken? cancelToken,
  }) async {
    final watch = Stopwatch()..start();
    final base = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final headers = adapter.headers(base, apiKey);
    final payload = adapter.streamPayload(
      model,
      messages,
      maxTokens: maxTokens,
      temperature: 0.7,
      tools: tools,
    );
    applyModelRequestPolicy(
      payload,
      baseUrl: base,
      modelId: model,
      protocolType: adapter.protocolType,
      directResponse: false,
    );

    final endpoints = adapter is GeminiAdapter
        ? [adapter.streamGenerateContentEndpoint(base, model)]
        : adapter.candidateEndpoints(base);

    Response<ResponseBody>? response;
    String? usedEndpoint;
    for (final endpoint in endpoints) {
      try {
        response = await _dio.post<ResponseBody>(
          endpoint,
          data: payload,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            validateStatus: (_) => true,
          ),
          cancelToken: cancelToken,
        );
        usedEndpoint = endpoint;
        final status = response.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          final providerError = await _readProviderError(
            response.data,
            apiKey: apiKey,
          );
          if (status == 404 &&
              endpoints.indexOf(endpoint) < endpoints.length - 1) {
            continue;
          }
          UpstreamFailurePolicy.throwIfTransientHttp(status);
          final detail = providerError.isEmpty ? '' : '：$providerError';
          throw StateError('模型服务返回 HTTP $status$detail');
        }
        break;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          throw StateError('已取消');
        }
        final status = error.response?.statusCode;
        if (status == 404 &&
            endpoints.indexOf(endpoint) < endpoints.length - 1) {
          continue;
        }
        UpstreamFailurePolicy.throwIfTransientHttp(status);
        throw StateError('网络错误: ${error.message ?? error}');
      }
    }

    final stream = response?.data?.stream;
    if (stream == null) throw StateError('响应流为空');

    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    var lastEventType = '';
    late final IncrementalSseResult decoded;
    try {
      decoded = await decodeIncrementalSse(
        stream: stream,
        adapter: adapter,
        checkCancelled: () {
          if (cancelToken?.isCancelled ?? false) {
            throw StateError('已取消');
          }
        },
        onFrame: (frame) {
          lastEventType = frame.eventType.isNotEmpty
              ? frame.eventType
              : frame.data['type']?.toString() ?? lastEventType;
          final text = adapter.streamTextFromFrame(frame);
          if (text.isNotEmpty) {
            buffer.write(text);
            onDelta(text);
          }
          final reasoning = adapter.streamReasoningFromFrame(frame);
          if (reasoning.isNotEmpty) {
            reasoningBuffer.write(reasoning);
            onReasoningDelta?.call(reasoning);
          }
        },
      );
    } catch (error) {
      watch.stop();
      if (cancelToken?.isCancelled ?? false) rethrow;
      DebugLogger.instance.error(
        '模型流传输中断',
        tag: 'LocalChat',
        details:
            'Protocol: ${adapter.protocolType}\n'
            'Endpoint: ${sanitizeEndpoint(usedEndpoint ?? '')}\n'
            'Last event: $lastEventType\n'
            'Error type: ${error.runtimeType}\n'
            'Elapsed: ${watch.elapsedMilliseconds}ms\n'
            'Has content: ${buffer.isNotEmpty}',
      );
      throw StateError('流式传输中断');
    }

    watch.stop();
    final terminationReason = decoded.usedCleanEofFallback
        ? 'clean_eof_fallback'
        : decoded.terminal.reason;
    lastEventType = decoded.lastEventType.isEmpty
        ? lastEventType
        : decoded.lastEventType;
    if (decoded.terminal.isFailure) {
      DebugLogger.instance.error(
        '模型流异常结束',
        tag: 'LocalChat',
        details:
            'Protocol: ${adapter.protocolType}\n'
            'Endpoint: ${sanitizeEndpoint(usedEndpoint ?? '')}\n'
            'Last event: $lastEventType\n'
            'Termination: $terminationReason\n'
            'Elapsed: ${watch.elapsedMilliseconds}ms\n'
            'Has content: ${buffer.isNotEmpty}',
      );
      final toolCalls = adapter.streamExtractToolCalls(decoded.frames);
      UpstreamFailurePolicy.throwIfTransientStream(
        reason: terminationReason,
        hasVisibleText: buffer.toString().trim().isNotEmpty,
        hasVisibleReasoning: reasoningBuffer.toString().trim().isNotEmpty,
        hasToolCalls: toolCalls.isNotEmpty,
      );
      throw StateError('模型流异常: $terminationReason');
    }

    DebugLogger.instance.info(
      '模型流读取完成',
      tag: 'LocalChat',
      details:
          'Protocol: ${adapter.protocolType}\n'
          'Endpoint: ${sanitizeEndpoint(usedEndpoint ?? '')}\n'
          'Last event: $lastEventType\n'
          'Termination: $terminationReason\n'
          'Elapsed: ${watch.elapsedMilliseconds}ms\n'
          'Text length: ${buffer.length}',
    );

    // 从流中提取工具调用
    final toolCalls = adapter.streamExtractToolCalls(decoded.frames);

    final usage = _extractStreamUsage(decoded.frames);

    return (
      text: buffer.toString(),
      reasoning: reasoningBuffer.toString(),
      toolCalls: toolCalls,
      usage: usage,
    );
  }

  Map<String, int>? _extractStreamUsage(List<SseFrame> frames) {
    var input = 0;
    var output = 0;
    var found = false;

    void readUsage(Object? raw) {
      if (raw is! Map) return;
      int number(Object? value) => value is num ? value.toInt() : 0;
      final currentInput = number(
        raw['prompt_tokens'] ??
            raw['input_tokens'] ??
            raw['promptTokenCount'] ??
            raw['inputTokenCount'],
      );
      final currentOutput = number(
        raw['completion_tokens'] ??
            raw['output_tokens'] ??
            raw['candidatesTokenCount'] ??
            raw['outputTokenCount'],
      );
      if (currentInput > 0 ||
          currentOutput > 0 ||
          raw['total_tokens'] != null ||
          raw['totalTokenCount'] != null) {
        found = true;
        input = math.max(input, currentInput);
        output = math.max(output, currentOutput);
      }
    }

    for (final frame in frames) {
      final data = frame.data;
      readUsage(data['usage']);
      readUsage(data['usageMetadata']);
      readUsage(data);
      final response = data['response'];
      if (response is Map) readUsage(response['usage']);
      final message = data['message'];
      if (message is Map) readUsage(message['usage']);
    }
    return found
        ? <String, int>{'input_tokens': input, 'output_tokens': output}
        : null;
  }
}
