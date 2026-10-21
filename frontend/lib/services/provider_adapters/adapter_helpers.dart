import 'dart:convert';

import 'adapter_types.dart';
import '../provider_failure_presentation.dart';
import 'protocol_types.dart';
import 'reasoning_recovery_policy.dart';
import 'provider_rejection_evidence.dart';
import 'model_parameter_policy.dart';
import 'tool_argument_parser.dart';

/// 适配器共享工具：端点拼接、内容提取、JSON 解包、SSE 解析、错误归一化。
///
/// 这些函数跨协议复用，避免在每个 adapter 里重复实现。

/// 拼接 base 与 path，自动处理首尾斜杠。
/// 若 base 已经以 path 结尾则直接返回 base。
String joinEndpoint(String baseUrl, String path) {
  final base = baseUrl.trim();
  if (base.isEmpty) {
    throw ArgumentError('API 地址为空');
  }
  var clean = path;
  while (clean.startsWith('/')) {
    clean = clean.substring(1);
  }
  if (clean.isEmpty) return base;
  final trimmedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  if (trimmedBase.endsWith('/$clean')) {
    return trimmedBase;
  }
  return '$trimmedBase/$clean';
}

/// 为一个基础端点生成候选变体列表。
///
/// 用户填的 Base URL 可能带 /v1、不带 /v1、或带自定义前缀。
/// 标准 OpenAI 兼容地址优先补 `/v1`，失败后再回退原始拼接。
/// 仅当原始路径不含 /v1 时才补 /v1 变体。
List<String> endpointVariants(String baseUrl, String path) {
  final primary = joinEndpoint(baseUrl, path);
  final base = baseUrl.trim();
  final hasV1 = base.contains('/v1') || base.endsWith('/v1');

  final variants = <String>[];
  if (!hasV1) {
    // 许多中转站的根路径是网页，即使 POST 也会返回 200 HTML。
    // 因此先走标准 /v1 端点，404 时由调用方回退原始端点。
    final withV1 = joinEndpoint('$base/v1', path);
    variants.add(withV1);
    if (!variants.contains(primary)) variants.add(primary);
  } else {
    variants.add(primary);
    // 原始 base 含 /v1，补一个去掉 /v1 的变体。
    final withoutV1 = base.replaceAll(RegExp(r'/v1(?=/|$)'), '');
    if (withoutV1 != base && withoutV1.isNotEmpty) {
      final noV1 = joinEndpoint(withoutV1, path);
      if (!variants.contains(noV1)) variants.add(noV1);
    }
  }
  return variants;
}

/// Shared endpoint policy for every production and capability request.
void applyModelRequestPolicy(
  Map<String, Object?> payload, {
  required String baseUrl,
  required String modelId,
  required String protocolType,
  required bool directResponse,
  String apiKey = '',
  String requestPath = '',
}) {
  ModelParameterPolicy.forEndpoint(
    baseUrl: baseUrl,
    modelId: modelId,
    protocol: protocolType,
    apiKey: apiKey,
    requestPath: requestPath,
  ).apply(payload, directResponse: directResponse);
  final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
  // OpenRouter declares the unified `reasoning` object, not OpenAI's knob.
  // Preserve the chosen effort and provider-default chat requests.
  if (protocolType == ProtocolType.openaiChat &&
      host == 'openrouter.ai' &&
      directResponse) {
    final effort = payload.remove('reasoning_effort');
    if (effort != null && !payload.containsKey('reasoning')) {
      payload['reasoning'] = <String, Object?>{'effort': effort};
    }
  }
}

/// Returns the narrow protocol override used when a DeepSeek chat stream
/// finishes with reasoning but no user-visible content.
///
/// Recovery uses an explicit provider/protocol capability registry, not model
/// name matching. Other providers keep their original contract and surface
/// the existing empty-response failure instead of receiving an unverified
/// parameter.
Map<String, Object?> reasoningOnlyRecoveryPayload({
  required String providerId,
  required String modelId,
  required String protocolType,
}) {
  return ReasoningRecoveryPolicy.payload(providerId, protocolType);
}

/// 从 OpenAI 风格 content 字段提取文本。
/// content 可以是 String，也可以是 [{type:text, text:...}, ...] 列表。
String contentText(dynamic content) {
  if (content is String) return content;
  if (content is! List) return '';
  final parts = <String>[];
  for (final part in content) {
    if (part is! Map) continue;
    final type = part['type'];
    if (type == 'text' || type == 'input_text' || type == 'output_text') {
      final text = part['text'];
      if (text is String) parts.add(text);
    }
  }
  return parts.join();
}

/// 尝试把响应体解析为 Map。支持 JSON 字符串被包裹一层的情况（递归两层）。
Map<dynamic, dynamic>? jsonObject(dynamic value) {
  if (value is Map) return value;
  if (value is List<int>) {
    value = utf8.decode(value, allowMalformed: true);
  }
  if (value is! String || value.trim().isEmpty) return null;
  try {
    final decoded = decodeStrictProviderJson(value);
    if (decoded is Map) return decoded;
    // 双层：外层字符串解出来还是字符串，再解一次。
    if (decoded is String) {
      final inner = decodeStrictProviderJson(decoded);
      if (inner is Map) return inner;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// 响应顶层字段名列表（用于诊断，不含值）。
List<String> topLevelKeys(dynamic value) {
  final map = jsonObject(value);
  if (map == null) return const [];
  return map.keys.map((key) => key.toString()).toList()..sort();
}

/// 解析 SSE 流为 (eventType, dataJson) 对。
///
/// 支持两种 SSE 形态：
/// 1. `event: xxx\ndata: {...}` 多行事件（Anthropic / Responses）；
/// 2. 仅 `data: {...}` 单行事件（OpenAI Chat / Gemini alt=sse）。
///
/// 对 data 行做 jsonDecode，解不出则跳过。返回的 eventType 可能为空字符串。
class SseFrame {
  const SseFrame({this.eventType = '', required this.data});
  final String eventType;
  final Map<dynamic, dynamic> data;
}

Iterable<SseFrame> parseSseLines(Iterable<String> lines) sync* {
  String? pendingEvent;
  final pendingData = <String>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      // 事件分隔。若有积攒 data 则产出一帧。
      if (pendingData.isNotEmpty) {
        final dataStr = pendingData.join('\n').trim();
        if (dataStr.isNotEmpty && dataStr != '[DONE]') {
          final parsed = decodeSseData(dataStr);
          if (parsed != null) {
            yield SseFrame(eventType: pendingEvent ?? '', data: parsed);
          }
        }
      }
      pendingEvent = null;
      pendingData.clear();
      continue;
    }
    if (line.startsWith('event:')) {
      pendingEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      pendingData.add(line.substring(5).trim());
    }
  }
  // 流结束时若仍有积攒。
  if (pendingData.isNotEmpty) {
    final dataStr = pendingData.join('\n').trim();
    if (dataStr.isNotEmpty && dataStr != '[DONE]') {
      final parsed = decodeSseData(dataStr);
      if (parsed != null) {
        yield SseFrame(eventType: pendingEvent ?? '', data: parsed);
      }
    }
  }
}

Map<dynamic, dynamic>? decodeSseData(String dataStr) {
  try {
    final decoded = jsonDecode(dataStr);
    if (decoded is Map) return decoded;
    if (decoded is String) {
      final inner = jsonDecode(decoded);
      if (inner is Map) return inner;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String streamFailureReason(
  Map<dynamic, dynamic> data, {
  required String fallback,
}) {
  final error = data['error'];
  final response = data['response'];
  final nestedError = response is Map ? response['error'] : null;
  final incomplete =
      data['incomplete_details'] ??
      (response is Map ? response['incomplete_details'] : null);
  final values = <Object?>[
    data['type'],
    data['code'],
    if (error is Map) error['type'],
    if (error is Map) error['code'],
    if (nestedError is Map) nestedError['type'],
    if (nestedError is Map) nestedError['code'],
    if (incomplete is Map) incomplete['reason'],
    if (response is Map && nestedError == null && incomplete == null)
      response['status'],
  ];
  final parts = values
      .whereType<Object>()
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty && value != 'error')
      .toSet()
      .toList(growable: false);
  return parts.isEmpty ? fallback : parts.join(':');
}

/// 把 HTTP 错误响应归一化为 NormalizedError。
String? _providerResponseMessage(Map<dynamic, dynamic>? map) {
  // 尝试从常见错误结构提取 message。
  String? serverMessage;
  if (map != null) {
    final error = map['error'];
    if (error is Map) {
      serverMessage = (error['message'] is String
          ? error['message'] as String
          : null);
    } else if (error is String) {
      serverMessage = error;
    }
    serverMessage ??=
        (map['message'] is String ? map['message'] as String : null) ??
        (map['detail'] is String ? map['detail'] as String : null);
  }

  return serverMessage;
}

String? _providerSemanticCode(
  Map<dynamic, dynamic>? map,
  int status,
  String? technicalFact,
) {
  final error = map?['error'];
  final semanticCode =
      (error is Map ? error['code'] ?? error['type'] : map?['code'])
          ?.toString()
          .toLowerCase();
  if (const {
        'protocol_mismatch',
        'unsupported_protocol',
      }.contains(semanticCode) &&
      const {401, 402, 403, 408, 429}.contains(status)) {
    return null;
  }
  return const {
        'invalid_api_key': 'AUTH_FAILED',
        'authentication_error': 'AUTH_FAILED',
        'insufficient_quota': 'ACCOUNT_BILLING',
        'insufficient_balance': 'ACCOUNT_BILLING',
        'billing_error': 'ACCOUNT_BILLING',
        'account_deactivated': 'ACCOUNT_BILLING',
        'invalid_request_error': 'INVALID_REQUEST',
        'invalid_parameter': 'INVALID_REQUEST',
        'model_not_found': 'INVALID_REQUEST',
        'rate_limit_exceeded': 'RATE_LIMITED',
        'protocol_mismatch': 'PROTOCOL_MISMATCH',
        'unsupported_protocol': 'PROTOCOL_MISMATCH',
      }[semanticCode] ??
      const {'接口协议不匹配': 'PROTOCOL_MISMATCH'}[technicalFact];
}

NormalizedError normalizeHttpError(
  int statusCode,
  dynamic responseBody,
  String fallbackText,
) {
  final map = jsonObject(responseBody);
  final String text;
  if (responseBody is String) {
    text = responseBody;
  } else if (responseBody == null) {
    text = fallbackText;
  } else if (map != null) {
    text = jsonEncode(map);
  } else {
    // 无法 JSON 序列化的对象（如流式响应的 ResponseBody）→ 用回退文案。
    text = fallbackText;
  }

  final serverMessage =
      _providerResponseMessage(map) ??
      (map == null && responseBody is String ? responseBody : null);
  final providerMessage = safeProviderMessage(serverMessage);
  // Preserve only fixed technical facts when an error echoes a request field.
  // The original explanation still goes through the ordinary privacy filter.
  final safeFact = providerTechnicalFact(statusCode, serverMessage);
  final detail = _safePreview(safeFact ?? serverMessage ?? text);
  if (_isContentPolicyViolation(map)) {
    return NormalizedError(
      'CONTENT_POLICY_VIOLATION',
      '请求内容未通过服务商审核',
      statusCode: statusCode,
      detail: detail,
      providerMessage: providerMessage,
    );
  }

  if (providerHasNoChannel(statusCode, serverMessage)) {
    return NormalizedError(
      'MODEL_CHANNEL_UNAVAILABLE',
      '当前模型暂无可用渠道，请更换模型或稍后重试。',
      statusCode: statusCode,
      detail: '当前模型暂无可用渠道',
      providerMessage: providerMessage,
    );
  }

  final semantic = _providerSemanticCode(map, statusCode, safeFact);
  if (semantic != null) {
    return NormalizedError(
      semantic,
      '模型服务拒绝了本次请求',
      statusCode: statusCode,
      detail: detail,
      providerMessage: providerMessage,
    );
  }
  switch (statusCode) {
    case 401:
    case 403:
      return NormalizedError(
        'AUTH_FAILED',
        '认证失败，请检查 API Key',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
    case 402:
      return NormalizedError(
        'ACCOUNT_BILLING',
        '服务商账户、余额或额度异常',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
    case 404:
      return NormalizedError(
        'ENDPOINT_NOT_FOUND',
        '接口地址不存在，请检查 Base URL',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
    case 429:
      return NormalizedError(
        'RATE_LIMITED',
        '请求过于频繁，本次结果未确认',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
    case 400:
      final error = map?['error'];
      final explicit = error is Map
          ? error['code'] ?? error['type']
          : map?['code'];
      if (!const {
            'invalid_request_error',
            'invalid_request',
            'invalid_parameter',
            'unsupported_parameter',
            'model_not_found',
          }.contains(explicit) &&
          safeFact == null &&
          !RegExp(
            r'parameter|model|参数|模型|response_?format|output format|tool_choice|responseSchema|responseMimeType|input_audio|\bschema\b',
            caseSensitive: false,
          ).hasMatch(serverMessage ?? '')) {
        return NormalizedError(
          'HTTP_ERROR',
          '模型请求失败，请查看服务商说明',
          statusCode: statusCode,
          providerMessage: providerMessage,
        );
      }
      return NormalizedError(
        'INVALID_REQUEST',
        '请求参数被服务拒绝',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
    case 422:
      return NormalizedError(
        'INVALID_REQUEST',
        '请求参数被服务拒绝',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
    default:
      if (statusCode >= 500) {
        return NormalizedError(
          'SERVER_ERROR',
          '模型服务暂时不可用，本次结果未确认',
          statusCode: statusCode,
          detail: detail,
          providerMessage: providerMessage,
        );
      }
      return NormalizedError(
        'HTTP_ERROR',
        '请求失败（HTTP $statusCode）',
        statusCode: statusCode,
        detail: detail,
        providerMessage: providerMessage,
      );
  }
}

bool _isContentPolicyViolation(Map? response) {
  final error = response?['error'];
  final code = error is Map
      ? error['code'] ?? error['type']
      : response?['code'];
  return const {
    'content_policy_violation',
    'content_filter',
    'content_policy',
    'safety_violation',
  }.contains(code);
}

/// 面向诊断与能力判定的安全错误说明。服务端细节已经在
/// [normalizeHttpError] 中做过长度限制，这里不包含请求头或 API Key。
String diagnosticErrorDetail(
  NormalizedError error, {
  Iterable<String> secrets = const [],
  Object? requestPayload,
}) {
  final detail = safeProviderMessage(
    error.detail,
    secrets: secrets,
    requestPayload: requestPayload,
  );
  return detail.isEmpty ? error.message : '${error.message}：$detail';
}

String _safePreview(String value) {
  final compact = value
      .replaceAll(
        RegExp(r'bearer\s+[^\s,;]+', caseSensitive: false),
        'Bearer [已隐藏]',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{6,}\b'), '[已隐藏]')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.length <= 200) return compact;
  return '${compact.substring(0, 200)}…';
}

/// 脱敏端点：去掉 query string，去掉可能泄露的 key 参数。
String sanitizeEndpoint(String url) {
  final q = url.indexOf('?');
  if (q < 0) return url;
  return url.substring(0, q);
}

String diagnosticProviderMessage(
  NormalizedError error, {
  Iterable<String> secrets = const [],
  Object? requestPayload,
}) => safeProviderMessage(
  error.providerMessage,
  secrets: secrets,
  requestPayload: requestPayload,
);

NormalizedError? streamProviderError(
  Iterable<SseFrame> frames,
  String terminationReason, {
  Iterable<String> secrets = const [],
  Object? requestPayload,
}) {
  for (final frame in frames) {
    final data =
        frame.data['response'] is Map &&
            (frame.data['response'] as Map)['error'] != null
        ? (frame.data['response'] as Map)
        : frame.data;
    if (data['error'] != null ||
        frame.eventType == 'error' ||
        data['type'] == 'error') {
      final error = normalizeHttpError(200, data, '服务商中断了请求');
      return NormalizedError(
        error.code,
        error.message,
        statusCode: error.statusCode,
        providerMessage: diagnosticProviderMessage(
          error,
          secrets: secrets,
          requestPayload: requestPayload,
        ),
      );
    }
  }
  if (terminationReason.contains('content_filter')) {
    return const NormalizedError('CONTENT_POLICY_VIOLATION', '请求内容未通过服务商审核');
  }
  return null;
}
