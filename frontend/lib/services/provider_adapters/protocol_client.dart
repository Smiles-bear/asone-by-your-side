import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'adapter_registry.dart';
import 'incremental_sse_decoder.dart';
import 'model_protocol_adapter.dart';
import 'model_output_contract.dart';
import 'structured_output_receiver.dart';
import 'protocol_types.dart';
import 'upstream_failure_policy.dart';
import 'gemini_adapter.dart';
import '../debug_logger.dart';
import 'protocol_context_recorder.dart';

part 'structured_protocol_result.dart';
part 'protocol_stream_helpers.dart';
part 'protocol_request_inspection.dart';

/// 流式调用结果（含累积文本、事件类型集合与诊断）。
class ProtocolStreamResult {
  ProtocolStreamResult({
    required this.success,
    required this.text,
    required this.diagnosis,
    this.reasoning = '',
    this.toolCalls = const [],
  });

  final bool success;
  final String text;
  final ProtocolDiagnosis diagnosis;
  final String reasoning;
  final List<ProviderToolCall> toolCalls;
}

/// 协议解析结果（auto 识别后返回确定的协议名与适配器）。
class ProtocolResolution {
  ProtocolResolution({
    required this.success,
    required this.protocol,
    required this.adapter,
    required this.diagnosis,
    this.textResult,
  });

  final bool success;
  final String protocol;
  final ModelProtocolAdapter adapter;
  final ProtocolDiagnosis diagnosis;
  final ProtocolCallResult? textResult;
}

/// 协议调用统一引擎。
///
/// 所有调用方（能力探针、聊天、记忆整理）通过此类发起请求，
/// 内部完成协议自动识别、端点变体、错误归一化与安全诊断收集。
class ProtocolClient {
  ProtocolClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
            ),
          );

  final Dio _dio;

  /// 上下文记录接缝（公开壳未挂载，所有调用点均为 null-aware）。
  ProtocolContextRecorder? get _recorder => ProtocolContextRecorder.current;

  /// auto 识别：依次尝试候选协议，用最小文本请求确认能拿到非空可读文本。
  /// 返回第一个成功的协议与适配器。失败返回 null + 最后一次诊断。
  Future<ProtocolResolution> resolveProtocol({
    required String baseUrl,
    required String apiKey,
    required String modelId,
    String preferredProtocol = ProtocolType.auto,
  }) async {
    final registry = AdapterRegistry.instance;
    final candidates = preferredProtocol == ProtocolType.auto
        ? registry.autoCandidates()
        : [preferredProtocol];

    ProtocolDiagnosis? lastDiagnosis;
    for (final protocol in candidates) {
      final adapter = registry.get(protocol);
      var result = await completeWithPayload(
        adapter: adapter,
        baseUrl: baseUrl,
        apiKey: apiKey,
        modelId: modelId,
        payload: adapter.textPayload(
          modelId,
          const [
            {'role': 'user', 'content': '请只回复：OK'},
          ],
          maxTokens: 128,
          temperature: 0,
        ),
      );
      if (!result.success && result.reasoning.trim().isNotEmpty) {
        result = await completeWithPayload(
          adapter: adapter,
          baseUrl: baseUrl,
          apiKey: apiKey,
          modelId: modelId,
          payload: adapter.textPayload(
            modelId,
            const [
              {'role': 'user', 'content': '请只回复：OK'},
            ],
            maxTokens: 512,
            temperature: 0,
          ),
        );
      }
      if (result.success && result.text.trim().isNotEmpty) {
        return ProtocolResolution(
          success: true,
          protocol: protocol,
          adapter: adapter,
          diagnosis: result.diagnosis,
          textResult: result,
        );
      }
      lastDiagnosis = result.diagnosis;
      // 若错误码不允许换协议（如 RATE_LIMITED / SERVER_ERROR），停止尝试。
      if (result.diagnosis.errorCode.isNotEmpty &&
          !retryableErrorCodes.contains(result.diagnosis.errorCode)) {
        break;
      }
    }
    return ProtocolResolution(
      success: false,
      protocol: candidates.first,
      adapter: registry.get(candidates.first),
      diagnosis:
          lastDiagnosis ??
          ProtocolDiagnosis(
            protocol: candidates.first,
            endpoint: '',
            requestSent: false,
            elapsedMs: 0,
            errorCode: 'PROTOCOL_MISMATCH',
            detail: '无法识别接口协议，或当前模型不可调用',
          ),
    );
  }

  /// 非流式文本调用（用已确定的适配器）。
  Future<ProtocolCallResult> completeText({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required List<Map<String, Object?>> messages,
    int? maxTokens,
    double temperature = 0,
    CancelToken? cancelToken,
    Map<String, Object?>? requestHeaders,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) => completeWithPayload(
    adapter: adapter,
    baseUrl: baseUrl,
    apiKey: apiKey,
    modelId: modelId,
    payload: adapter.textPayload(
      modelId,
      messages,
      maxTokens: maxTokens,
      temperature: temperature,
    ),
    cancelToken: cancelToken,
    requestHeaders: requestHeaders,
    connectTimeout: connectTimeout,
    sendTimeout: sendTimeout,
    receiveTimeout: receiveTimeout,
  );

  /// 按已验证的业务输出契约执行非流式请求，并统一校验结束原因、正文与结构。
  Future<ProtocolCallResult> completeForContract({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String providerId,
    required int adapterVersion,
    required String configurationFingerprint,
    required ModelCapabilityProfile capabilityProfile,
    required List<Map<String, Object?>> messages,
    required ModelOutputContract contract,
    int? maxTokens,
    double temperature = 0,
    CancelToken? cancelToken,
    Map<String, Object?>? requestHeaders,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) async {
    final contractName = contract.kind.name;
    final requiresStructured = contract.requiresStructuredData;
    final profileMatches =
        (capabilityProfile.providerId.isEmpty ||
            capabilityProfile.providerId == providerId) &&
        (capabilityProfile.protocol.isEmpty ||
            capabilityProfile.protocol == adapter.protocolType) &&
        (capabilityProfile.adapterVersion == 0 ||
            capabilityProfile.adapterVersion == adapterVersion) &&
        (capabilityProfile.configurationFingerprint.isEmpty ||
            capabilityProfile.configurationFingerprint ==
                configurationFingerprint);
    if (requiresStructured && !profileMatches) {
      return ProtocolCallResult(
        success: false,
        text: '',
        diagnosis: ProtocolDiagnosis(
          protocol: adapter.protocolType,
          endpoint: '',
          requestSent: false,
          elapsedMs: 0,
          errorCode: 'MODEL_CAPABILITY_STALE',
          detail: '模型配置已变化，请重新检测模型能力',
          outputContract: contractName,
          reasoningPolicy: contract.reasoningPolicy.name,
          stage: 'preflight',
          failureCategory: ModelTaskFailureKind.transport.name,
        ),
        failureKind: ModelTaskFailureKind.transport,
      );
    }
    var transport = requiresStructured
        ? selectStructuredOutputTransport(
            profile: capabilityProfile,
            protocol: adapter.protocolType,
            contract: contract,
          )
        : StructuredOutputTransport.unknown;
    if (requiresStructured && transport == StructuredOutputTransport.unknown) {
      return ProtocolCallResult(
        success: false,
        text: '',
        diagnosis: ProtocolDiagnosis(
          protocol: adapter.protocolType,
          endpoint: '',
          requestSent: false,
          elapsedMs: 0,
          errorCode: capabilityProfile.hasReliableTextOutput
              ? 'OUTPUT_CONTRACT_UNAVAILABLE'
              : 'STRUCTURED_OUTPUT_UNCONFIRMED',
          detail: capabilityProfile.hasReliableTextOutput
              ? '当前协议没有可执行的结构化输出通道'
              : '当前模型文本能力不可用，请检查配置或重新检测',
          outputContract: contractName,
          structuredTransport: transport.name,
          reasoningPolicy: contract.reasoningPolicy.name,
          stage: 'preflight',
          failureCategory: ModelTaskFailureKind.transport.name,
        ),
        failureKind: ModelTaskFailureKind.transport,
      );
    }
    ProtocolCallResult raw;
    var attemptCount = 0;
    while (true) {
      attemptCount++;
      late final Map<String, Object?> payload;
      try {
        payload = adapter.outputContractPayload(
          modelId,
          messagesForStructuredTransport(
            messages,
            contract: contract,
            transport: transport,
          ),
          contract,
          structuredTransport: transport,
          providerId: providerId,
          maxTokens: maxTokens,
          temperature: temperature,
        );
      } catch (error) {
        return ProtocolCallResult(
          success: false,
          text: '',
          diagnosis: ProtocolDiagnosis(
            protocol: adapter.protocolType,
            endpoint: '',
            requestSent: false,
            elapsedMs: 0,
            errorCode: 'OUTPUT_CONTRACT_UNAVAILABLE',
            detail: error.toString().replaceFirst('Bad state: ', ''),
            outputContract: contractName,
            structuredTransport: transport.name,
            reasoningPolicy: contract.reasoningPolicy.name,
            stage: 'preflight',
            attemptCount: attemptCount,
            failureCategory: ModelTaskFailureKind.transport.name,
          ),
          failureKind: ModelTaskFailureKind.transport,
        );
      }
      raw = await completeWithPayload(
        adapter: adapter,
        baseUrl: baseUrl,
        apiKey: apiKey,
        modelId: modelId,
        payload: payload,
        cancelToken: cancelToken,
        requestHeaders: requestHeaders,
        connectTimeout: connectTimeout,
        sendTimeout: sendTimeout,
        receiveTimeout: receiveTimeout,
      );
      if (canFallbackToPromptJson(
        raw,
        transport: transport,
        profile: capabilityProfile,
        contract: contract,
      )) {
        transport = StructuredOutputTransport.promptJson;
        continue;
      }
      break;
    }
    var diagnosis = raw.diagnosis.copyWith(
      outputContract: contractName,
      structuredTransport: requiresStructured ? transport.name : '',
      reasoningPolicy: contract.reasoningPolicy.name,
      textLength: raw.text.length,
      reasoningLength: raw.reasoning.length,
      providerId: providerId,
      adapterVersion: adapterVersion,
      stage: raw.success ? 'receive' : 'request',
      attemptCount: attemptCount,
    );
    if (!raw.success &&
        contract.kind == ModelOutputKind.svgDocument &&
        _containsCompleteSvg(raw.reasoning)) {
      diagnosis = diagnosis.copyWith(
        detail: '已读取并校验模型思考字段中的完整 SVG 内容',
        textLength: raw.reasoning.length,
      );
      return ProtocolCallResult(
        success: true,
        text: raw.reasoning.trim(),
        reasoning: raw.reasoning,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
      );
    }
    if (!raw.success) {
      final failureKind =
          raw.text.trim().isEmpty &&
              raw.diagnosis.statusCode != null &&
              (raw.diagnosis.statusCode! >= 200 &&
                  raw.diagnosis.statusCode! < 300)
          ? ModelTaskFailureKind.noReadableText
          : ModelTaskFailureKind.transport;
      diagnosis = diagnosis.copyWith(failureCategory: failureKind.name);
      return ProtocolCallResult(
        success: false,
        text: raw.text,
        reasoning: raw.reasoning,
        toolCalls: raw.toolCalls,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
        failureKind: failureKind,
      );
    }
    if (_isLengthFinish(diagnosis.finishReason)) {
      diagnosis = diagnosis.copyWith(
        errorCode: 'OUTPUT_TRUNCATED',
        detail: '模型输出达到长度限制，请调整任务后重试',
      );
      return ProtocolCallResult(
        success: false,
        text: raw.text,
        reasoning: raw.reasoning,
        toolCalls: raw.toolCalls,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
      );
    }
    if (!requiresStructured) {
      if (contract.kind == ModelOutputKind.svgDocument &&
          (!_containsCompleteSvg(raw.text))) {
        diagnosis = diagnosis.copyWith(
          errorCode: 'INVALID_CONSTRAINED_OUTPUT',
          detail: '模型没有返回完整的 SVG 内容',
        );
        return ProtocolCallResult(
          success: false,
          text: raw.text,
          reasoning: raw.reasoning,
          usage: raw.usage,
          model: raw.model,
          diagnosis: diagnosis,
          requestId: raw.requestId,
        );
      }
      return ProtocolCallResult(
        success: true,
        text: raw.text.trim(),
        reasoning: raw.reasoning,
        toolCalls: raw.toolCalls,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
      );
    }

    return validateStructuredProtocolResult(
      raw: raw,
      contract: contract,
      transport: transport,
      diagnosis: diagnosis,
    );
  }

  /// 对视觉、音频等已由适配器构造的请求体应用非结构化输出契约。
  Future<ProtocolCallResult> completePayloadForContract({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String providerId,
    required int adapterVersion,
    required Map<String, Object?> payload,
    required ModelOutputContract contract,
    CancelToken? cancelToken,
  }) async {
    if (contract.requiresStructuredData) {
      throw ArgumentError('预构建请求体不支持结构化输出契约');
    }
    applyOutputContractPolicy(
      payload,
      protocol: adapter.protocolType,
      providerId: providerId,
      contract: contract,
    );
    final raw = await completeWithPayload(
      adapter: adapter,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      payload: payload,
      cancelToken: cancelToken,
    );
    var diagnosis = raw.diagnosis.copyWith(
      outputContract: contract.kind.name,
      reasoningPolicy: contract.reasoningPolicy.name,
      providerId: providerId,
      adapterVersion: adapterVersion,
    );
    if (!raw.success) {
      return ProtocolCallResult(
        success: false,
        text: raw.text,
        reasoning: raw.reasoning,
        toolCalls: raw.toolCalls,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
      );
    }
    if (_isLengthFinish(diagnosis.finishReason)) {
      diagnosis = diagnosis.copyWith(
        errorCode: 'OUTPUT_TRUNCATED',
        detail: '模型输出达到长度限制，请调整任务后重试',
      );
      return ProtocolCallResult(
        success: false,
        text: raw.text,
        reasoning: raw.reasoning,
        toolCalls: raw.toolCalls,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
      );
    }
    if (contract.kind == ModelOutputKind.svgDocument &&
        !_containsCompleteSvg(raw.text)) {
      diagnosis = diagnosis.copyWith(
        errorCode: 'INVALID_CONSTRAINED_OUTPUT',
        detail: '模型没有返回完整的 SVG 内容',
      );
      return ProtocolCallResult(
        success: false,
        text: raw.text,
        reasoning: raw.reasoning,
        usage: raw.usage,
        model: raw.model,
        diagnosis: diagnosis,
        requestId: raw.requestId,
      );
    }
    return ProtocolCallResult(
      success: true,
      text: raw.text.trim(),
      reasoning: raw.reasoning,
      toolCalls: raw.toolCalls,
      usage: raw.usage,
      model: raw.model,
      diagnosis: diagnosis,
      requestId: raw.requestId,
    );
  }

  /// 非流式调用（用预构建的请求体，用于图片/工具/结构化探针）。
  Future<ProtocolCallResult> completeWithPayload({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required Map<String, Object?> payload,
    CancelToken? cancelToken,
    Map<String, Object?>? requestHeaders,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) async {
    applyModelRequestPolicy(
      payload,
      baseUrl: baseUrl,
      modelId: modelId,
      protocolType: adapter.protocolType,
      directResponse: true,
    );
    // 记录请求上下文
    final messages = _inspectableMessages(payload);
    final requestId =
        _recorder?.recordRequest(
          modelId: modelId,
          messages: messages,
          baseUrl: baseUrl,
          maxTokens: payload['max_tokens'] as int?,
          temperature: (payload['temperature'] as num?)?.toDouble(),
          protocol: adapter.protocolType,
          contextMetadata: _requestMetadata(payload),
        ) ??
        '';

    DebugLogger.instance.info(
      '发起模型请求',
      tag: 'ProtocolClient',
      details:
          'Model: $modelId\nProtocol: ${adapter.protocolType}\nMessages: ${messages.length}',
    );

    final watch = Stopwatch()..start();
    final headers = <String, Object?>{
      ...adapter.headers(baseUrl, apiKey),
      ...?requestHeaders,
    };
    final endpoints = _nonStreamEndpoints(adapter, baseUrl, modelId);

    Response<dynamic>? response;
    String? usedEndpoint;

    endpointLoop:
    for (final endpoint in endpoints) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          response = await _dio.post<dynamic>(
            endpoint,
            data: payload,
            options: Options(
              headers: headers,
              connectTimeout: connectTimeout,
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
            ),
            cancelToken: cancelToken,
          );
          usedEndpoint = endpoint;
          break endpointLoop;
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if (_isRetryableStatus(status) && attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 600));
            continue;
          }
          if (status == 404 &&
              endpoints.indexOf(endpoint) < endpoints.length - 1) {
            continue endpointLoop;
          }
          watch.stop();
          final normalized = normalizeHttpError(
            status ?? 0,
            error.response?.data,
            error.message ?? '',
          );

          // 记录错误
          final errorDetail = diagnosticErrorDetail(
            normalized,
            secrets: [apiKey],
          );
          DebugLogger.instance.error(
            '模型请求失败',
            tag: 'ProtocolClient',
            details:
                'Endpoint: $endpoint\nStatus: $status\nError: $errorDetail',
          );
          _recorder?.updateResponse(requestId, '', error: errorDetail);

          return ProtocolCallResult(
            success: false,
            text: '',
            diagnosis: ProtocolDiagnosis(
              protocol: adapter.protocolType,
              endpoint: sanitizeEndpoint(endpoint),
              requestSent: true,
              statusCode: status,
              contentType: _contentType(error.response),
              elapsedMs: max(1, watch.elapsedMilliseconds),
              errorCode: normalized.code,
              detail: errorDetail,
            ),
            requestId: requestId,
          );
        }
      }
    }

    watch.stop();
    final payload2 = jsonObject(response!.data);
    if (payload2 == null) {
      final rawResponse = switch (response.data) {
        final String value => value,
        final List<int> value => utf8.decode(value, allowMalformed: true),
        _ => '',
      };
      final directText = _unwrapStringResponse(rawResponse);
      final directLower = directText.toLowerCase();
      final svgStart = directLower.indexOf('<svg');
      final svgEnd = directLower.lastIndexOf('</svg>');
      if (svgStart >= 0 && svgEnd >= svgStart) {
        final svg = directText.substring(svgStart, svgEnd + '</svg>'.length);
        _recorder?.updateResponse(requestId, svg);
        return ProtocolCallResult(
          success: true,
          text: svg,
          diagnosis: ProtocolDiagnosis(
            protocol: adapter.protocolType,
            endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
            requestSent: true,
            statusCode: response.statusCode,
            contentType: _contentType(response),
            elapsedMs: max(1, watch.elapsedMilliseconds),
            detail: '兼容读取服务直接返回的 SVG 文本',
          ),
          requestId: requestId,
        );
      }
      final frames = rawResponse.isEmpty
          ? const <SseFrame>[]
          : parseSseLines(const LineSplitter().convert(rawResponse)).toList();
      final streamedText = frames
          .map(adapter.streamTextFromFrame)
          .where((part) => part.isNotEmpty)
          .join();
      final streamedReasoning = frames
          .map(adapter.streamReasoningFromFrame)
          .where((part) => part.isNotEmpty)
          .join();
      final streamedToolCalls = adapter.streamExtractToolCalls(frames);
      if (streamedText.trim().isNotEmpty || streamedToolCalls.isNotEmpty) {
        _recorder?.updateResponse(
          requestId,
          streamedText,
          toolCalls: _inspectableToolCalls(streamedToolCalls),
        );
        return ProtocolCallResult(
          success: true,
          text: streamedText,
          reasoning: streamedReasoning,
          toolCalls: streamedToolCalls,
          diagnosis: ProtocolDiagnosis(
            protocol: adapter.protocolType,
            endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
            requestSent: true,
            statusCode: response.statusCode,
            contentType: _contentType(response),
            elapsedMs: max(1, watch.elapsedMilliseconds),
            sseEventTypes: frames
                .map((frame) => frame.eventType)
                .where((type) => type.isNotEmpty)
                .toSet()
                .toList(),
            detail: '兼容读取服务返回的 SSE 文本',
          ),
          requestId: requestId,
        );
      }
      DebugLogger.instance.error(
        '响应格式错误',
        tag: 'ProtocolClient',
        details: '服务返回成功，但响应不是可读取的 JSON 对象',
      );
      _recorder?.updateResponse(requestId, '', error: 'INVALID_RESPONSE');

      return ProtocolCallResult(
        success: false,
        text: '',
        diagnosis: ProtocolDiagnosis(
          protocol: adapter.protocolType,
          endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
          requestSent: true,
          statusCode: response.statusCode,
          contentType: _contentType(response),
          elapsedMs: max(1, watch.elapsedMilliseconds),
          errorCode: 'INVALID_RESPONSE',
          detail: '服务返回成功，但响应不是可读取的 JSON 对象',
        ),
        requestId: requestId,
      );
    }
    final text = adapter.extractText(payload2);
    final reasoning = adapter.extractReasoning(payload2);
    final toolCalls = adapter.extractToolCalls(payload2);
    final finishReason = _finishReason(payload2, adapter.protocolType);
    final usage = _normalizedUsage(payload2);
    final responseModel =
        payload2['model'] as String? ??
        payload2['modelVersion'] as String? ??
        modelId;
    final success = text.trim().isNotEmpty || toolCalls.isNotEmpty;
    final emptyDetail = reasoning.trim().isNotEmpty
        ? '模型只返回了思考内容，未生成最终答案'
        : '服务返回成功，但没有可读取的文本内容';

    // 记录响应
    if (success) {
      DebugLogger.instance.info(
        '模型请求成功',
        tag: 'ProtocolClient',
        details:
            'Elapsed: ${watch.elapsedMilliseconds}ms\nText length: ${text.length}',
      );
      _recorder?.updateResponse(
        requestId,
        text,
        toolCalls: _inspectableToolCalls(toolCalls),
      );
    } else {
      DebugLogger.instance.warning(
        '响应为空',
        tag: 'ProtocolClient',
        details: '$emptyDetail\nReasoning length: ${reasoning.length}',
      );
      _recorder?.updateResponse(requestId, '', error: emptyDetail);
    }

    return ProtocolCallResult(
      success: success,
      text: text,
      reasoning: reasoning,
      toolCalls: toolCalls,
      usage: usage,
      model: responseModel,
      diagnosis: ProtocolDiagnosis(
        protocol: adapter.protocolType,
        endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
        requestSent: true,
        statusCode: response.statusCode,
        contentType: _contentType(response),
        elapsedMs: max(1, watch.elapsedMilliseconds),
        topLevelKeys: topLevelKeys(payload2),
        finishReason: finishReason,
        textLength: text.length,
        reasoningLength: reasoning.length,
        detail: success ? '真实调用验证通过' : emptyDetail,
      ),
      requestId: requestId,
    );
  }

  bool _isLengthFinish(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'length' ||
        normalized == 'max_tokens' ||
        normalized == 'max_output_tokens' ||
        normalized == 'max_tokens_reached';
  }

  Map<String, Object?> _normalizedUsage(Map<dynamic, dynamic> payload) {
    final nestedResponse = payload['response'];
    final raw =
        payload['usage'] ??
        payload['usageMetadata'] ??
        (nestedResponse is Map ? nestedResponse['usage'] : null);
    if (raw is! Map) return const {};
    int number(Object? value) => value is num ? value.toInt() : 0;
    final prompt = number(
      raw['prompt_tokens'] ??
          raw['input_tokens'] ??
          raw['promptTokenCount'] ??
          raw['inputTokenCount'],
    );
    final completion = number(
      raw['completion_tokens'] ??
          raw['output_tokens'] ??
          raw['candidatesTokenCount'] ??
          raw['outputTokenCount'],
    );
    if (prompt == 0 && completion == 0) return const {};
    final total = number(raw['total_tokens'] ?? raw['totalTokenCount']);
    return <String, Object?>{
      'prompt_tokens': prompt,
      'completion_tokens': completion,
      'total_tokens': total > 0 ? total : prompt + completion,
    };
  }

  bool _containsCompleteSvg(String value) {
    final lower = value.toLowerCase();
    return lower.contains('<svg') && lower.contains('</svg>');
  }

  String _finishReason(Map<dynamic, dynamic> payload, String protocol) {
    if (protocol == ProtocolType.anthropicMessages) {
      return payload['stop_reason']?.toString() ?? '';
    }
    if (protocol == ProtocolType.gemini) {
      final candidates = payload['candidates'];
      if (candidates is List &&
          candidates.isNotEmpty &&
          candidates.first is Map) {
        return (candidates.first as Map)['finishReason']?.toString() ?? '';
      }
      return '';
    }
    if (protocol == ProtocolType.openaiResponses) {
      final details = payload['incomplete_details'];
      if (details is Map && details['reason'] != null) {
        return details['reason'].toString();
      }
      return payload['status']?.toString() ?? '';
    }
    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      return (choices.first as Map)['finish_reason']?.toString() ?? '';
    }
    return '';
  }

  Future<ProtocolStreamResult> streamText({
    required ModelProtocolAdapter adapter,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required List<Map<String, Object?>> messages,
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
    Map<String, Object?> payloadOverrides = const {},
    CancelToken? cancelToken,
    void Function(String delta)? onDelta,
  }) async {
    final watch = Stopwatch()..start();
    final headers = adapter.headers(baseUrl, apiKey);
    final payload = adapter.streamPayload(
      modelId,
      messages,
      maxTokens: maxTokens,
      temperature: temperature,
      tools: tools,
    )..addAll(payloadOverrides);
    applyModelRequestPolicy(
      payload,
      baseUrl: baseUrl,
      modelId: modelId,
      protocolType: adapter.protocolType,
      directResponse: false,
    );

    final requestId =
        _recorder?.recordRequest(
          modelId: modelId,
          messages: messages.cast<Map<String, dynamic>>(),
          baseUrl: baseUrl,
          maxTokens: maxTokens,
          temperature: temperature,
          protocol: adapter.protocolType,
          contextMetadata: _requestMetadata(payload),
        ) ??
        '';

    final endpoints = _streamEndpoints(adapter, baseUrl, modelId);
    Response<ResponseBody>? response;
    String? usedEndpoint;
    int? statusCode;
    String? contentType;

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
        statusCode = response.statusCode;
        if (statusCode == null || statusCode < 200 || statusCode >= 300) {
          final rawError = await _readStreamErrorBody(response.data);
          if (statusCode == 404 &&
              endpoints.indexOf(endpoint) < endpoints.length - 1) {
            response = null;
            continue;
          }
          watch.stop();
          final normalized = normalizeHttpError(
            statusCode ?? 0,
            rawError,
            'HTTP ${statusCode ?? 0}',
          );
          final detail = diagnosticErrorDetail(normalized, secrets: [apiKey]);
          _recorder?.updateResponse(requestId, '', error: detail);
          return ProtocolStreamResult(
            success: false,
            text: '',
            diagnosis: ProtocolDiagnosis(
              protocol: adapter.protocolType,
              endpoint: sanitizeEndpoint(endpoint),
              requestSent: true,
              statusCode: statusCode,
              contentType: _contentType(response),
              elapsedMs: max(1, watch.elapsedMilliseconds),
              errorCode: UpstreamFailurePolicy.diagnosticCode(
                statusCode: statusCode,
                code: normalized.code,
                fallback: normalized.code,
              ),
              detail: detail,
            ),
          );
        }
        break;
      } on DioException catch (error) {
        statusCode = error.response?.statusCode;
        if (statusCode == 404 &&
            endpoints.indexOf(endpoint) < endpoints.length - 1) {
          continue;
        }
        watch.stop();
        final normalized = normalizeHttpError(
          statusCode ?? 0,
          error.response?.data,
          error.message ?? '',
        );
        final detail = diagnosticErrorDetail(normalized, secrets: [apiKey]);
        _recorder?.updateResponse(requestId, '', error: detail);
        return ProtocolStreamResult(
          success: false,
          text: '',
          diagnosis: ProtocolDiagnosis(
            protocol: adapter.protocolType,
            endpoint: sanitizeEndpoint(endpoint),
            requestSent: true,
            statusCode: statusCode,
            contentType: _contentType(error.response),
            elapsedMs: max(1, watch.elapsedMilliseconds),
            errorCode: UpstreamFailurePolicy.diagnosticCode(
              statusCode: statusCode,
              code: normalized.code,
              fallback: normalized.code,
            ),
            detail: detail,
          ),
        );
      }
    }

    final stream = response?.data?.stream;
    if (stream == null) {
      watch.stop();
      _recorder?.updateResponse(requestId, '', error: '服务没有返回事件流');
      return ProtocolStreamResult(
        success: false,
        text: '',
        diagnosis: ProtocolDiagnosis(
          protocol: adapter.protocolType,
          endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
          requestSent: true,
          statusCode: response?.statusCode,
          elapsedMs: max(1, watch.elapsedMilliseconds),
          errorCode: 'INVALID_RESPONSE',
          detail: '服务没有返回事件流',
        ),
      );
    }

    statusCode = response!.statusCode;
    contentType = _contentType(response);
    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    try {
      final decoded = await decodeIncrementalSse(
        stream: stream,
        adapter: adapter,
        onFrame: (frame) {
          final delta = adapter.streamTextFromFrame(frame);
          final reasoningDelta = adapter.streamReasoningFromFrame(frame);
          if (reasoningDelta.isNotEmpty) {
            reasoningBuffer.write(reasoningDelta);
          }
          if (delta.isNotEmpty) {
            buffer.write(delta);
            onDelta?.call(delta);
          }
        },
      );
      watch.stop();
      final elapsedMs = watch.elapsedMilliseconds;
      final text = buffer.toString();
      final toolCalls = adapter.streamExtractToolCalls(decoded.frames);
      final diagnostic = decoded.diagnostic(
        adapter.protocolType,
        elapsedMs,
        text.length,
      );
      if (decoded.terminal.isFailure) {
        final detail = '流式响应异常（${decoded.terminal.reason}）';
        _recorder?.updateResponse(
          requestId,
          text,
          error: detail,
          toolCalls: _inspectableToolCalls(toolCalls),
        );
        DebugLogger.instance.error(
          '模型流异常结束',
          tag: 'ProtocolClient',
          details: diagnostic,
        );
        return ProtocolStreamResult(
          success: false,
          text: text,
          reasoning: reasoningBuffer.toString(),
          toolCalls: toolCalls,
          diagnosis: ProtocolDiagnosis(
            protocol: adapter.protocolType,
            endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
            requestSent: true,
            statusCode: statusCode,
            contentType: contentType,
            elapsedMs: max(1, elapsedMs),
            sseEventTypes: decoded.eventTypes,
            errorCode: UpstreamFailurePolicy.diagnosticCode(
              reason: decoded.terminal.reason,
              fallback: 'UPSTREAM_ERROR',
            ),
            detail: detail,
            finishReason: decoded.terminal.reason,
          ),
        );
      }
      final success = text.trim().isNotEmpty || toolCalls.isNotEmpty;
      final terminationReason = decoded.usedCleanEofFallback
          ? 'clean_eof_fallback'
          : decoded.terminal.reason;
      _recorder?.updateResponse(
        requestId,
        text,
        error: success ? null : '无可读取内容',
        toolCalls: _inspectableToolCalls(toolCalls),
      );
      DebugLogger.instance.info(
        '模型流读取完成',
        tag: 'ProtocolClient',
        details: diagnostic,
      );
      return ProtocolStreamResult(
        success: success,
        text: text,
        reasoning: reasoningBuffer.toString(),
        toolCalls: toolCalls,
        diagnosis: ProtocolDiagnosis(
          protocol: adapter.protocolType,
          endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
          requestSent: true,
          statusCode: statusCode,
          contentType: contentType,
          elapsedMs: max(1, elapsedMs),
          sseEventTypes: decoded.eventTypes,
          detail: success ? '已收到真实 SSE 响应' : '收到事件流，但没有可读取的文本增量或工具调用',
          finishReason: terminationReason,
        ),
      );
    } catch (e) {
      watch.stop();
      final text = buffer.toString();
      _recorder?.updateResponse(
        requestId,
        text,
        error: '流式响应异常（${e.runtimeType}）',
      );
      return ProtocolStreamResult(
        success: false,
        text: text,
        reasoning: reasoningBuffer.toString(),
        diagnosis: ProtocolDiagnosis(
          protocol: adapter.protocolType,
          endpoint: sanitizeEndpoint(usedEndpoint ?? ''),
          requestSent: true,
          statusCode: statusCode,
          contentType: contentType,
          elapsedMs: max(1, watch.elapsedMilliseconds),
          errorCode: 'INVALID_RESPONSE',
          detail: '流式响应异常',
        ),
      );
    }
  }

  List<String> _nonStreamEndpoints(
    ModelProtocolAdapter adapter,
    String baseUrl,
    String modelId,
  ) {
    if (adapter is GeminiAdapter) {
      return [adapter.generateContentEndpoint(baseUrl, modelId)];
    }
    return adapter.candidateEndpoints(baseUrl);
  }

  List<String> _streamEndpoints(
    ModelProtocolAdapter adapter,
    String baseUrl,
    String modelId,
  ) {
    if (adapter is GeminiAdapter) {
      return [adapter.streamGenerateContentEndpoint(baseUrl, modelId)];
    }
    return adapter.candidateEndpoints(baseUrl);
  }

  String? _contentType(Response? response) {
    final headers = response?.headers;
    if (headers == null) return null;
    return headers.value('content-type');
  }
}

String _unwrapStringResponse(String rawResponse) {
  final directText = rawResponse.trim();
  try {
    final decoded = jsonDecode(directText);
    return decoded is String ? decoded.trim() : directText;
  } catch (_) {
    return directText;
  }
}

bool _isRetryableStatus(int? statusCode) =>
    statusCode == 502 || statusCode == 503 || statusCode == 504;
