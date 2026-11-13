part of 'local_chat_service.dart';

typedef _AttemptUsage = ({int input, int output, bool estimated});

extension on LocalChatService {
  Future<
    ({
      String text,
      String reasoning,
      List<ProviderToolCall> toolCalls,
      _AttemptUsage usage,
      int requestCount,
    })
  >
  _executeModelCallWithRetry({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String model,
    String providerId = '',
    required List<Map<String, Object?>> messages,
    required int maxTokens,
    required List<Map<String, Object?>>? tools,
    required void Function(String delta) onDelta,
    void Function(String reasoningDelta)? onReasoningDelta,
    CancelToken? cancelToken,
  }) async {
    Map<String, Object?> payloadOverrides = const {};
    _AttemptUsage? recoveryUsage;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _executeModelCall(
          adapter: adapter,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          maxTokens: maxTokens,
          tools: tools,
          onDelta: onDelta,
          onReasoningDelta: onReasoningDelta,
          cancelToken: cancelToken,
          payloadOverrides: payloadOverrides,
        );
        final reasoningOnly =
            result.text.trim().isEmpty &&
            result.toolCalls.isEmpty &&
            result.reasoning.trim().isNotEmpty;
        final recoveryPayload = reasoningOnlyRecoveryPayload(
          providerId: providerId,
          modelId: model,
          protocolType: adapter.protocolType,
        );
        final usage = _accountAttempt(
          reported: result.usage,
          messages: messages,
          tools: tools,
          output: '${result.reasoning}\n${result.text}',
        );
        if (reasoningOnly &&
            attempt == 0 &&
            !(cancelToken?.isCancelled ?? false) &&
            result.terminationReason == 'finish_reason:stop' &&
            recoveryPayload.isNotEmpty) {
          payloadOverrides = recoveryPayload;
          recoveryUsage = usage;
          continue;
        }
        return (
          text: result.text,
          reasoning: result.reasoning,
          toolCalls: result.toolCalls,
          usage: recoveryUsage == null
              ? usage
              : (
                  input: recoveryUsage.input + usage.input,
                  output: recoveryUsage.output + usage.output,
                  estimated: recoveryUsage.estimated || usage.estimated,
                ),
          requestCount: attempt + 1,
        );
      } catch (error) {
        final retry =
            attempt == 0 &&
            UpstreamFailurePolicy.canRetry(
              error,
              cancelled: cancelToken?.isCancelled ?? false,
            );
        if (!retry) rethrow;
        DebugLogger.instance.warning('上游服务暂时不可用，正在重试一次', tag: 'LocalChat');
        await _retryDelay(const Duration(milliseconds: 350));
      }
    }
    throw StateError('模型请求未完成');
  }

  // Estimate each missing side per received response, before summing retries.
  _AttemptUsage _accountAttempt({
    required Map<String, int>? reported,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>>? tools,
    required String output,
  }) {
    final input = reported?['input_tokens'];
    final completion = reported?['output_tokens'];
    final planner = ChatContextWindowPlanner();
    return (
      input:
          input ??
          planner.estimateTextTokens(
            jsonEncode({
              'messages': messages,
              if (tools?.isNotEmpty == true) 'tools': tools,
            }),
          ),
      output: completion ?? planner.estimateTextTokens(output),
      estimated: input == null || completion == null,
    );
  }

  // Preserve structured codes for classification; callers never log this body.
  Future<String> _readProviderError(ResponseBody? body) async {
    if (body == null) return '';
    final bytes = BytesBuilder(copy: false);
    const maximumBytes = 8 * 1024;
    await for (final chunk in body.stream) {
      final remaining = maximumBytes - bytes.length;
      if (remaining <= 0) break;
      bytes.add(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
      if (bytes.length >= maximumBytes) break;
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true).trim();
  }
}
