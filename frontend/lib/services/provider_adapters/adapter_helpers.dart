import 'dart:convert';

import 'adapter_types.dart';
import 'protocol_types.dart';

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

/// 为需要直接结果的非流式请求应用官方模型参数。
///
/// qwen3.8-max 在未指定思考强度时默认使用超高思考预算。绘画、能力探测、
/// 视觉短答、日记和记忆整理使用低思考以控制延迟。Grok 4.6 使用兼容的
/// token 参数；聊天保留模型默认思考强度。
void applyModelRequestPolicy(
  Map<String, Object?> payload, {
  required String baseUrl,
  required String modelId,
  required String protocolType,
  required bool directResponse,
}) {
  if (protocolType != ProtocolType.openaiChat) return;
  final normalizedModel = modelId.trim().toLowerCase();

  if (normalizedModel == 'grok-4.6') {
    final maxTokens = payload.remove('max_tokens');
    if (maxTokens != null) payload['max_completion_tokens'] = maxTokens;
    payload.remove('temperature');
    if (directResponse) payload['reasoning_effort'] = 'low';
  }

  if (normalizedModel != 'qwen3.8-max') return;
  final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
  final isOfficialQwen =
      host == 'dashscope.aliyuncs.com' ||
      host == 'dashscope-us.aliyuncs.com' ||
      host.endsWith('.maas.aliyuncs.com');
  if (isOfficialQwen) {
    final maxTokens = payload.remove('max_tokens');
    if (maxTokens != null) payload['max_completion_tokens'] = maxTokens;
    if (directResponse && !payload.containsKey('enable_thinking')) {
      payload['reasoning_effort'] = 'low';
    }
  }
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
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded;
    // 双层：外层字符串解出来还是字符串，再解一次。
    if (decoded is String) {
      final inner = jsonDecode(decoded);
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
  final values = <Object?>[
    data['type'],
    data['code'],
    if (error is Map) error['type'],
    if (error is Map) error['code'],
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

  // 尝试从常见错误结构提取 message。
  String? serverMessage;
  if (map != null) {
    final error = map['error'];
    if (error is Map) {
      serverMessage =
          (error['message'] as String?) ?? (error['type'] as String?);
    } else if (error is String) {
      serverMessage = error;
    }
    serverMessage ??= (map['message'] as String?) ?? (map['detail'] as String?);
  }

  switch (statusCode) {
    case 401:
    case 403:
      return NormalizedError(
        'AUTH_FAILED',
        '认证失败，请检查 API Key',
        statusCode: statusCode,
        detail: _safePreview(serverMessage ?? text),
      );
    case 404:
      return NormalizedError(
        'ENDPOINT_NOT_FOUND',
        '接口地址不存在，请检查 Base URL',
        statusCode: statusCode,
        detail: _safePreview(serverMessage ?? text),
      );
    case 429:
      return NormalizedError(
        'RATE_LIMITED',
        '请求过于频繁，本次结果未确认',
        statusCode: statusCode,
        detail: _safePreview(serverMessage ?? text),
      );
    case 400:
    case 422:
      return NormalizedError(
        'INVALID_REQUEST',
        '请求参数被服务拒绝',
        statusCode: statusCode,
        detail: _safePreview(serverMessage ?? text),
      );
    default:
      if (statusCode >= 500) {
        return NormalizedError(
          'SERVER_ERROR',
          '模型服务暂时不可用，本次结果未确认',
          statusCode: statusCode,
          detail: _safePreview(serverMessage ?? text),
        );
      }
      return NormalizedError(
        'HTTP_ERROR',
        '请求失败（HTTP $statusCode）',
        statusCode: statusCode,
        detail: _safePreview(serverMessage ?? text),
      );
  }
}

/// 面向诊断与能力判定的安全错误说明。服务端细节已经在
/// [normalizeHttpError] 中做过长度限制，这里不包含请求头或 API Key。
String diagnosticErrorDetail(
  NormalizedError error, {
  Iterable<String> secrets = const [],
}) {
  var detail = error.detail?.trim() ?? '';
  for (final secret in secrets) {
    if (secret.isNotEmpty) detail = detail.replaceAll(secret, '[已隐藏]');
  }
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
