import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/model_service.dart';
import 'provider_adapters/adapter_registry.dart';
import 'provider_adapters/adapter_types.dart';
import 'provider_adapters/protocol_client.dart';
import 'provider_adapters/model_protocol_adapter.dart';
import 'vision_test_data.dart';
import 'audio_test_data.dart';

// ModelCapabilityVerdict / ModelCapabilityProbeResult 已迁移至公开契约包
// （asone_contracts），此处再导出保持既有 import 可用。
export 'package:asone_contracts/asone_contracts.dart'
    show ModelCapabilityProbeResult, ModelCapabilityVerdict;

/// 模型能力探针。通过 ProtocolClient + 协议适配器发起真实调用。
///
/// 若配置的 protocol_type 为 auto，首次调用前自动识别协议并缓存适配器。
/// 常用五项能力共用同一适配器；音频由实际使用场景按需调用独立探针。
class ModelCapabilityProbe {
  ModelCapabilityProbe({Dio? dio}) : _client = ProtocolClient(dio: dio);

  final ProtocolClient _client;

  /// 贯穿本次检测的取消令牌。设置后所有请求都携带它，
  /// 取消会立即终止底层 HTTP 请求。
  CancelToken? cancelToken;

  ModelProtocolAdapter? _resolvedAdapter;
  String _resolvedProtocol = '';
  bool _resolutionFailed = false;
  ProtocolCallResult? _resolutionTextResult;
  ProtocolDiagnosis? _resolutionFailureDiagnosis;

  /// 解析协议（若 auto 则自动识别）。缓存结果。
  /// 返回适配器，失败返回 null。
  Future<ModelProtocolAdapter?> _resolveAdapter(ModelService service) async {
    if (_resolvedAdapter != null) return _resolvedAdapter;
    if (_resolutionFailed) return null;

    if (service.protocolType != ProtocolType.auto) {
      _resolvedAdapter = AdapterRegistry.instance.get(service.protocolType);
      _resolvedProtocol = service.protocolType;
      return _resolvedAdapter;
    }

    final resolution = await _client.resolveProtocol(
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      preferredProtocol: ProtocolType.auto,
    );
    if (resolution.success) {
      _resolvedAdapter = resolution.adapter;
      _resolvedProtocol = resolution.protocol;
      _resolutionTextResult = resolution.textResult;
      return _resolvedAdapter;
    }
    _resolutionFailureDiagnosis = resolution.diagnosis;
    _resolutionFailed = true;
    return null;
  }

  /// 获取已解析的协议名（供外部持久化用）。
  String get resolvedProtocol => _resolvedProtocol;

  /// 基础文本/协议未确认时，其余能力没有发请求，不能误判为不支持。
  List<ModelCapabilityProbeResult> unconfirmedDependentResults() => [
    _unconfirmed('streaming', 0, '基础文本或接口协议尚未确认'),
    _unconfirmed('vision_input', 0, '基础文本或接口协议尚未确认'),
    _unconfirmed('client_tool_calling', 0, '基础文本或接口协议尚未确认'),
    _unconfirmed('structured_output', 0, '基础文本或接口协议尚未确认'),
  ];

  /// 文本能力：非流式调用能拿到非空可读文本即支持。
  Future<ModelCapabilityProbeResult> testText(ModelService service) async {
    final adapter = await _resolveAdapter(service);
    if (adapter == null) {
      final diagnosis = _resolutionFailureDiagnosis;
      return ModelCapabilityProbeResult(
        capability: 'text_chat',
        verdict: ModelCapabilityVerdict.unconfirmed,
        elapsedMs: diagnosis?.elapsedMs ?? 0,
        detail: diagnosis?.detail ?? '基础连接或协议尚未确认',
        diagnosis: diagnosis,
      );
    }
    var result =
        _resolutionTextResult ??
        await _client.completeText(
          adapter: adapter,
          baseUrl: service.baseUrl,
          apiKey: service.apiKey,
          modelId: service.model,
          messages: const [
            {'role': 'user', 'content': '请只回复：OK'},
          ],
          maxTokens: 128,
          temperature: 0,
          cancelToken: cancelToken,
        );
    _resolutionTextResult = null;
    if (!result.success && result.reasoning.trim().isNotEmpty) {
      result = await _client.completeText(
        adapter: adapter,
        baseUrl: service.baseUrl,
        apiKey: service.apiKey,
        modelId: service.model,
        messages: const [
          {'role': 'user', 'content': '请只回复：OK'},
        ],
        maxTokens: 512,
        temperature: 0,
        cancelToken: cancelToken,
      );
    }
    final valid = result.success && result.text.trim().isNotEmpty;
    return ModelCapabilityProbeResult(
      capability: 'text_chat',
      verdict: valid
          ? ModelCapabilityVerdict.supported
          : ModelCapabilityVerdict.unconfirmed,
      elapsedMs: result.diagnosis.elapsedMs,
      detail: valid ? '真实调用验证通过' : result.diagnosis.detail,
      protocol: _resolvedProtocol,
      diagnosis: result.diagnosis,
    );
  }

  /// 流式能力：收到真实 SSE 文本增量即支持。
  Future<ModelCapabilityProbeResult> testStreaming(
    ModelService service, {
    int maxTokens = 128,
    Map<String, Object?> payloadOverrides = const {},
  }) async {
    final adapter = await _resolveAdapter(service);
    if (adapter == null) {
      return _unconfirmed('streaming', 0, '基础连接或协议尚未确认');
    }
    var result = await _client.streamText(
      adapter: adapter,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      messages: const [
        {'role': 'user', 'content': '只回复 STREAM_OK'},
      ],
      maxTokens: maxTokens,
      temperature: 0,
      payloadOverrides: payloadOverrides,
      cancelToken: cancelToken,
    );
    if (!result.success && result.reasoning.trim().isNotEmpty) {
      result = await _client.streamText(
        adapter: adapter,
        baseUrl: service.baseUrl,
        apiKey: service.apiKey,
        modelId: service.model,
        messages: const [
          {'role': 'user', 'content': '只回复 STREAM_OK'},
        ],
        maxTokens: 512,
        temperature: 0,
        payloadOverrides: payloadOverrides,
        cancelToken: cancelToken,
      );
    }
    final valid = result.success && result.text.trim().isNotEmpty;
    return ModelCapabilityProbeResult(
      capability: 'streaming',
      verdict: valid
          ? ModelCapabilityVerdict.supported
          : _failureVerdict('streaming', result.diagnosis),
      elapsedMs: result.diagnosis.elapsedMs,
      detail: valid ? '已收到真实 SSE 文本增量' : result.diagnosis.detail,
      protocol: _resolvedProtocol,
      diagnosis: result.diagnosis,
    );
  }

  /// 图片理解：严格复用桌面端图片、提示词和判定规则。
  Future<ModelCapabilityProbeResult> testVision(ModelService service) async {
    final adapter = await _resolveAdapter(service);
    if (adapter == null) {
      return _unconfirmed('vision_input', 0, '基础连接或协议尚未确认');
    }
    final payload = adapter.visionPayload(
      service.model,
      const [],
      'data:image/png;base64,${VisionTestData.pngBase64}',
      maxTokens: 64,
    );
    final result = await _client.completeWithPayload(
      adapter: adapter,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      payload: payload,
      cancelToken: cancelToken,
    );
    if (!result.success) {
      return _fromCallResult(
        'vision_input',
        result,
        unconfirmedDetail: result.diagnosis.detail,
      );
    }
    final matched = result.text.contains('123');
    return ModelCapabilityProbeResult(
      capability: 'vision_input',
      verdict: matched
          ? ModelCapabilityVerdict.supported
          : ModelCapabilityVerdict.unconfirmed,
      elapsedMs: result.diagnosis.elapsedMs,
      detail: matched ? '模型正确读取了图片顶部文字末尾数字' : '模型回复中没有出现图片顶部文字末尾数字 123',
      protocol: _resolvedProtocol,
      diagnosis: result.diagnosis,
    );
  }

  /// 音频理解：发送项目内置的合成单词语音，要求返回固定短语。
  Future<ModelCapabilityProbeResult> testAudio(ModelService service) async {
    final adapter = await _resolveAdapter(service);
    if (adapter == null) {
      return _unconfirmed('audio_input', 0, '基础连接或协议尚未确认');
    }
    final payload = adapter.audioPayload(
      service.model,
      const [],
      AudioPayloadData(
        base64Data: AudioTestData.wavBase64,
        mimeType: 'audio/wav',
      ),
      maxTokens: 32,
      instruction: '音频中说的是英文数字 three。确认后只回复 AUDIO_3。',
    );
    if (payload == null) {
      return ModelCapabilityProbeResult(
        capability: 'audio_input',
        verdict: ModelCapabilityVerdict.unsupported,
        elapsedMs: 0,
        detail: '当前接口协议没有正式音频输入结构',
        protocol: _resolvedProtocol,
        requestWasSent: false,
      );
    }
    final result = await _client.completeWithPayload(
      adapter: adapter,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      payload: payload,
      cancelToken: cancelToken,
    );
    if (!result.success) {
      return _fromCallResult(
        'audio_input',
        result,
        unconfirmedDetail: result.diagnosis.detail,
      );
    }
    final matched = result.text.toUpperCase().contains('AUDIO_3');
    return ModelCapabilityProbeResult(
      capability: 'audio_input',
      verdict: matched
          ? ModelCapabilityVerdict.supported
          : ModelCapabilityVerdict.unconfirmed,
      elapsedMs: result.diagnosis.elapsedMs,
      detail: matched ? '模型正确识别了内置测试语音' : '模型未返回指定音频验证码 AUDIO_3',
      protocol: _resolvedProtocol,
      diagnosis: result.diagnosis,
    );
  }

  /// 工具调用：模型生成了指定工具调用即支持。
  Future<ModelCapabilityProbeResult> testTool(ModelService service) async {
    final adapter = await _resolveAdapter(service);
    if (adapter == null) {
      return _unconfirmed('client_tool_calling', 0, '基础连接或协议尚未确认');
    }
    final payload = adapter.toolProbePayload(
      service.model,
      'record_probe',
      '调用工具记录验证码 AZ731，禁止直接回答。',
      providerId: service.providerId,
    );
    final result = await _client.completeWithPayload(
      adapter: adapter,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      payload: payload,
      cancelToken: cancelToken,
    );
    if (!result.success) {
      return _fromCallResult(
        'client_tool_calling',
        result,
        unconfirmedDetail: result.diagnosis.detail,
      );
    }
    final matched = result.toolCalls.any(
      (call) =>
          call.name == 'record_probe' && call.arguments['code'] == 'AZ731',
    );
    return ModelCapabilityProbeResult(
      capability: 'client_tool_calling',
      verdict: matched
          ? ModelCapabilityVerdict.supported
          : ModelCapabilityVerdict.unconfirmed,
      elapsedMs: result.diagnosis.elapsedMs,
      detail: matched ? '模型生成了指定工具调用及参数' : '响应中没有找到指定工具调用及参数',
      protocol: _resolvedProtocol,
      diagnosis: result.diagnosis,
    );
  }

  /// 结构化输出：模型返回符合 schema 的 JSON 即支持。
  Future<ModelCapabilityProbeResult> testStructured(
    ModelService service,
  ) async {
    final adapter = await _resolveAdapter(service);
    if (adapter == null) {
      return _unconfirmed('structured_output', 0, '基础连接或协议尚未确认');
    }
    // Anthropic 通过 forced tool 实现结构化输出。
    final isViaTool = adapter.structuredViaTool();
    final schema = {
      'type': 'object',
      'properties': {
        'code': {'type': 'string', 'const': 'AZ731'},
        'count': {'type': 'integer', 'const': 7},
      },
      'required': ['code', 'count'],
      'additionalProperties': false,
    };
    final instruction = isViaTool
        ? '返回 code=AZ731、count=7 的结构化结果。'
        : '按给定结构返回 code=AZ731、count=7。';
    final payload = adapter.structuredProbePayload(
      service.model,
      instruction,
      schema,
      providerId: service.providerId,
    );
    var result = await _client.completeWithPayload(
      adapter: adapter,
      baseUrl: service.baseUrl,
      apiKey: service.apiKey,
      modelId: service.model,
      payload: payload,
      cancelToken: cancelToken,
    );
    final fallback = adapter.structuredFallbackPayload(
      service.model,
      instruction,
      schema,
      providerId: service.providerId,
    );
    if (!result.success &&
        result.diagnosis.errorCode == 'INVALID_REQUEST' &&
        fallback != null) {
      final strictElapsed = result.diagnosis.elapsedMs;
      final fallbackResult = await _client.completeWithPayload(
        adapter: adapter,
        baseUrl: service.baseUrl,
        apiKey: service.apiKey,
        modelId: service.model,
        payload: fallback,
        cancelToken: cancelToken,
      );
      result = ProtocolCallResult(
        success: fallbackResult.success,
        text: fallbackResult.text,
        toolCalls: fallbackResult.toolCalls,
        structuredData: fallbackResult.structuredData,
        diagnosis: fallbackResult.diagnosis.copyWith(
          elapsedMs: strictElapsed + fallbackResult.diagnosis.elapsedMs,
          detail: fallbackResult.success
              ? '严格 JSON Schema 被拒绝，JSON Object 回退验证通过'
              : fallbackResult.diagnosis.detail,
        ),
      );
    }
    if (!result.success) {
      return _fromCallResult(
        'structured_output',
        result,
        unconfirmedDetail: result.diagnosis.detail,
      );
    }

    // 结构化输出验证逻辑：
    // - 若通过 forced tool（Anthropic），检查 toolCalls 中是否有结构化工具调用
    // - 否则检查文本是否能解析为符合 schema 的 JSON
    bool matched;
    var wrappedText = false;
    if (isViaTool) {
      matched = result.toolCalls.any(
        (call) =>
            call.name == 'asone_structured_test' &&
            call.arguments['code'] == 'AZ731' &&
            call.arguments['count'] == 7,
      );
    } else {
      try {
        final extracted = _extractJsonText(result.text);
        wrappedText = extracted.trim() != result.text.trim();
        final decoded = jsonDecode(extracted);
        matched =
            decoded is Map &&
            decoded['code'] == 'AZ731' &&
            decoded['count'] == 7 &&
            decoded.length == 2;
      } catch (_) {
        matched = false;
      }
    }
    final transport = isViaTool
        ? 'forced_tool'
        : result.diagnosis.detail.contains('JSON Object')
        ? 'json_object'
        : _resolvedProtocol == ProtocolType.gemini
        ? 'gemini_schema'
        : 'json_schema';
    final diagnosis = result.diagnosis.copyWith(
      structuredTransport: transport,
      providerId: service.providerId,
      adapterVersion: service.providerAdapterVersion,
      strictSchemaObserved:
          matched && !wrappedText && transport == 'json_schema',
    );
    return ModelCapabilityProbeResult(
      capability: 'structured_output',
      verdict: matched
          ? ModelCapabilityVerdict.supported
          : ModelCapabilityVerdict.unconfirmed,
      elapsedMs: result.diagnosis.elapsedMs,
      detail: matched
          ? (wrappedText
                ? '结构化 JSON 可读取，但服务未严格遵循输出格式'
                : result.diagnosis.detail.contains('JSON Object')
                ? '支持 JSON Object；不支持严格 JSON Schema'
                : '支持严格 JSON Schema')
          : '响应中没有找到符合约束的结构化 JSON',
      protocol: _resolvedProtocol,
      diagnosis: diagnosis.copyWith(
        detail: matched && wrappedText
            ? '结构化 JSON 经过兼容清理后通过本地校验'
            : diagnosis.detail,
      ),
    );
  }

  ModelCapabilityProbeResult _fromCallResult(
    String capability,
    ProtocolCallResult result, {
    required String unconfirmedDetail,
  }) {
    // 若错误码是明确的能力拒绝（INVALID_REQUEST 且包含不支持关键词）→ unsupported
    if (_failureVerdict(capability, result.diagnosis) ==
        ModelCapabilityVerdict.unsupported) {
      return ModelCapabilityProbeResult(
        capability: capability,
        verdict: ModelCapabilityVerdict.unsupported,
        elapsedMs: result.diagnosis.elapsedMs,
        detail: '服务明确说明不支持这项能力',
        protocol: _resolvedProtocol,
        diagnosis: result.diagnosis,
      );
    }
    return ModelCapabilityProbeResult(
      capability: capability,
      verdict: ModelCapabilityVerdict.unconfirmed,
      elapsedMs: result.diagnosis.elapsedMs,
      detail: unconfirmedDetail,
      protocol: _resolvedProtocol,
      diagnosis: result.diagnosis,
    );
  }

  ModelCapabilityVerdict _failureVerdict(
    String capability,
    ProtocolDiagnosis diagnosis,
  ) {
    if (diagnosis.errorCode == 'INVALID_REQUEST' &&
        _explicitlyRejectsCapability(capability, diagnosis.detail)) {
      return ModelCapabilityVerdict.unsupported;
    }
    return ModelCapabilityVerdict.unconfirmed;
  }

  ModelCapabilityProbeResult _unconfirmed(
    String capability,
    int elapsedMs,
    String detail,
  ) => ModelCapabilityProbeResult(
    capability: capability,
    verdict: ModelCapabilityVerdict.unconfirmed,
    elapsedMs: elapsedMs,
    detail: detail,
    protocol: _resolvedProtocol,
  );

  static bool _explicitlyRejectsCapability(String capability, String text) {
    final lower = text.toLowerCase();
    final rejects =
        lower.contains('unsupported') ||
        lower.contains('not support') ||
        lower.contains('does not support') ||
        lower.contains('不支持');
    if (!rejects) return false;
    final markers = switch (capability) {
      'vision_input' => const ['image', 'vision', '图片', '视觉'],
      'audio_input' => const ['audio', 'sound', '音频', '声音'],
      'client_tool_calling' => const ['tool', 'function', '工具', '函数'],
      'structured_output' => const [
        'response_format',
        'json_schema',
        'structured',
        '结构化',
      ],
      'streaming' => const ['stream', 'sse', '流式'],
      _ => const ['text', 'chat', '文本', '对话'],
    };
    return markers.any(lower.contains);
  }

  /// 从模型输出中提取 JSON 文本，剥离 ```json ... ``` 代码块包裹。
  /// Claude 等模型常把结构化结果包在 markdown 代码块里，直接 jsonDecode 会失败。
  static String _extractJsonText(String text) {
    final trimmed = text.trim();
    final fence = RegExp(
      r'^```(?:json|JSON)?\s*\n?(.*?)\n?```\s*$',
      dotAll: true,
    ).firstMatch(trimmed);
    return fence?.group(1)?.trim() ?? trimmed;
  }
}
