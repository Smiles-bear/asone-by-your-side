part of 'local_chat_service.dart';

extension on LocalChatService {
  Future<
    ({
      String text,
      String reasoning,
      List<ProviderToolCall> toolCalls,
      Map<String, int>? usage,
    })
  >
  _executeModelCallWithRetry({
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
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _executeModelCall(
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

  Future<String> _readProviderError(
    ResponseBody? body, {
    required String apiKey,
  }) async {
    if (body == null) return '';
    final bytes = BytesBuilder(copy: false);
    const maximumBytes = 8 * 1024;
    await for (final chunk in body.stream) {
      final remaining = maximumBytes - bytes.length;
      if (remaining <= 0) break;
      bytes.add(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
    }
    final raw = utf8.decode(bytes.takeBytes(), allowMalformed: true).trim();
    if (raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final code = error['code']?.toString().trim() ?? '';
          final message = error['message']?.toString().trim() ?? '';
          return _redactProviderError(
            [code, message].where((part) => part.isNotEmpty).join(' - '),
            apiKey,
          );
        }
        final message = decoded['message']?.toString().trim() ?? '';
        if (message.isNotEmpty) return _redactProviderError(message, apiKey);
      }
    } on FormatException {
      // 非 JSON 错误页只保留短预览，完整 HTML 不进入日志和用户界面。
    }
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    return _redactProviderError(
      normalized.substring(0, math.min(500, normalized.length)),
      apiKey,
    );
  }

  String _redactProviderError(String value, String apiKey) {
    var redacted = value;
    if (apiKey.trim().isNotEmpty) {
      redacted = redacted.replaceAll(apiKey.trim(), '[已隐藏]');
    }
    return redacted.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer [已隐藏]',
    );
  }
}
