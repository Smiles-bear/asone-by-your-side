export 'package:asone_contracts/asone_contracts.dart' show ProtocolDiagnosis;

// 协议适配器数据类型：响应、流事件、工具调用、归一化错误、安全诊断。
// 移植自桌面 `model_services/types.py` 与 `errors.py`，按移动端 Dart 习惯精简。

/// 归一化错误码（与桌面端一致，用于决定是否换协议重试）。
class NormalizedError {
  const NormalizedError(
    this.code,
    this.message, {
    this.statusCode,
    this.detail,
    this.providerMessage = '',
  });

  /// 错误码，如 `AUTH_FAILED` / `MODEL_NOT_FOUND` / `INVALID_RESPONSE` 等。
  final String code;

  /// 面向用户的中文消息（不含秘密）。
  final String message;

  /// HTTP 状态码（若适用）。
  final int? statusCode;

  /// 诊断细节（脱敏，不含 Key / 完整原始响应）。
  final String? detail;
  final String providerMessage;

  @override
  String toString() => message;
}

/// 适配器请求异常。携带归一化错误，调用方据此判定 verdict 与是否重试。
class AdapterRequestException implements Exception {
  AdapterRequestException(
    this.error, {
    this.attempts = 1,
    this.temporarilyUnavailable = false,
  });

  final NormalizedError error;
  final int attempts;
  final bool temporarilyUnavailable;

  @override
  String toString() => error.message;
}

/// 提供给模型调用的工具描述（与 OpenAI tools 结构解耦的内部表示）。
class ToolDescriptor {
  const ToolDescriptor({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

/// 模型返回的工具调用（内部表示，跨协议归一）。
class ProviderToolCall {
  const ProviderToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.nativeId,
  });

  final String id;

  /// Null when the protocol omitted an ID. [id] is then a local association.
  final String? nativeId;
  final String name;

  /// 已解析为 Map 的参数（若模型返回 JSON 字符串则已解码）。
  final Map<String, Object?> arguments;
}

/// 非流式完整响应。
class ProviderResponse {
  const ProviderResponse({
    required this.text,
    this.reasoning = '',
    this.usage = const {},
    this.resolvedModelId = '',
    this.finishReason = '',
    this.statusCode,
    this.toolCalls = const [],
    this.nativeContinuation,
    this.terminalState = ProviderTerminalState.unknown,
    this.toolReceptions = const [],
    this.parsingIssues = const [],
    this.usageSource = 'unreported',
  });

  final String text;
  final String reasoning;
  final Map<String, int> usage;
  final String resolvedModelId;
  final String finishReason;
  final int? statusCode;
  final List<ProviderToolCall> toolCalls;
  final Map<String, Object?>? nativeContinuation;
  final ProviderTerminalState terminalState;
  final List<ProviderToolReception> toolReceptions;
  final List<String> parsingIssues;
  final String usageSource;

  bool get canDispatchTools =>
      terminalState == ProviderTerminalState.toolRequired &&
      parsingIssues.isEmpty &&
      toolReceptions.isNotEmpty &&
      toolReceptions.every(
        (tool) => tool.state == ProviderToolArgumentState.valid,
      );
}

enum ProviderTerminalState {
  completed,
  toolRequired,
  truncated,
  refused,
  failed,
  cancelled,
  unknown,
}

enum ProviderToolArgumentState {
  valid,
  missing,
  incomplete,
  malformed,
  conflict,
}

/// Reception evidence is separate from executable calls. Do not log raw input.
class ProviderToolReception {
  const ProviderToolReception({
    required this.id,
    required this.name,
    required this.state,
    this.nativeId,
    this.arguments,
    this.rawArguments,
  });

  final String id;
  final String? nativeId;
  final String name;
  final ProviderToolArgumentState state;
  final Map<String, Object?>? arguments;
  final Object? rawArguments;
}

/// 流式事件增量。
class StreamEvent {
  const StreamEvent({
    this.textDelta = '',
    this.reasoningDelta = '',
    this.usage = const {},
    this.finishReason = '',
    this.resolvedModelId = '',
  });

  final String textDelta;
  final String reasoningDelta;
  final Map<String, int> usage;
  final String finishReason;
  final String resolvedModelId;
}

enum ProviderStreamTerminalKind { none, success, failure }

class ProviderStreamTerminal {
  const ProviderStreamTerminal._(this.kind, this.reason);

  const ProviderStreamTerminal.none()
    : this._(ProviderStreamTerminalKind.none, '');

  const ProviderStreamTerminal.success(String reason)
    : this._(ProviderStreamTerminalKind.success, reason);

  const ProviderStreamTerminal.failure(String reason)
    : this._(ProviderStreamTerminalKind.failure, reason);

  final ProviderStreamTerminalKind kind;
  final String reason;

  bool get isTerminal => kind != ProviderStreamTerminalKind.none;
  bool get isSuccess => kind == ProviderStreamTerminalKind.success;
  bool get isFailure => kind == ProviderStreamTerminalKind.failure;
}

/// 调用类型。决定适配器走 complete 还是 stream。
enum CallKind { text, streaming, vision, audio, tool, structured }

/// A short inline audio input. Raw bytes are base64 encoded only for the
/// request lifetime and are never persisted by a protocol adapter.
class AudioPayloadData {
  const AudioPayloadData({required this.base64Data, required this.mimeType});

  final String base64Data;
  final String mimeType;

  String? get openAiFormat => switch (mimeType.toLowerCase()) {
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    _ => null,
  };
}

/// 单项检测的安全诊断元数据（不含 Key 与原始响应）。
/// 可尝试另一个协议的错误码白名单（与桌面 `_may_try_another_protocol` 一致）。
const retryableErrorCodes = {
  'MODEL_NOT_FOUND',
  'ENDPOINT_NOT_FOUND',
  'PROTOCOL_MISMATCH',
  'INVALID_REQUEST',
  'INVALID_RESPONSE',
  'MODEL_LIST_UNAVAILABLE',
  'AUTH_FAILED',
};
