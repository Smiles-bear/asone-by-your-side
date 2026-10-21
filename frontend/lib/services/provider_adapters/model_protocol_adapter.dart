import 'package:dio/dio.dart';

import 'adapter_types.dart';
import 'adapter_helpers.dart';
import 'model_output_contract.dart';
import 'endpoint_output_policy.dart';

/// 协议适配器抽象接口。
///
/// 每个协议（openai_chat / openai_responses / anthropic_messages / gemini）
/// 实现此接口，负责：端点、鉴权头、请求体构造、响应解析、流解析、
/// 工具调用与结构化输出探针。所有调用方（探针、聊天、记忆整理）共用此层。
abstract class ModelProtocolAdapter {
  String get protocolType;

  /// 该协议的非流式文本/图片请求端点（已脱敏前）。
  /// 返回候选列表：主端点 + /v1 变体（用于 404 自动补试）。
  List<String> candidateEndpoints(String baseUrl);

  /// 鉴权与协议头。
  Map<String, String> headers(String baseUrl, String apiKey);

  /// 构造非流式文本请求体。
  Map<String, Object?> textPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  });

  /// 构造流式文本请求体。
  Map<String, Object?> streamPayload(
    String modelId,
    List<Map<String, Object?>> messages, {
    int? maxTokens,
    double temperature = 0,
    List<Map<String, Object?>>? tools,
  });

  /// 按业务输出契约构造生产请求。协议和供应商参数只能在 Adapter 层翻译，
  /// 业务模块不得自行拼接 response_format / thinking / output_config 等字段。
  Map<String, Object?> outputContractPayload(
    String modelId,
    List<Map<String, Object?>> messages,
    ModelOutputContract contract, {
    required StructuredOutputTransport structuredTransport,
    String? providerId,
    int? maxTokens,
    double temperature = 0,
  });

  /// Ask the provider to require one of the supplied tools for this turn.
  ///
  /// Callers should only use this when the payload already contains tools.
  Map<String, Object?> requireAnyToolPayload(Map<String, Object?> payload);

  /// Completes an already chosen operation, without generating public prose.
  /// Uses the same provider reasoning policy as other short mechanical tasks.
  Map<String, Object?> requiredToolContinuationOverrides(
    String modelId, {
    required String baseUrl,
    String? providerId,
    int? maxTokens,
  }) {
    const contract = ModelOutputContract.shortScalar();
    final payload = outputContractPayload(
      modelId,
      const [],
      contract,
      structuredTransport: StructuredOutputTransport.unknown,
      providerId: providerId,
      maxTokens: maxTokens,
    );
    applyEndpointPolicy(payload, baseUrl, protocolType, contract);
    payload.removeWhere(
      (key, _) => const {
        'model',
        'messages',
        'input',
        'contents',
        'system',
        'tools',
        'stream',
        'max_tokens',
        'max_completion_tokens',
        'temperature',
      }.contains(key),
    );
    return requireAnyToolPayload(payload);
  }

  /// 从非流式响应提取文本（空字符串表示无可读文本）。
  String extractText(Map<dynamic, dynamic> payload);

  /// 从非流式响应提取 reasoning（可空）。
  String extractReasoning(Map<dynamic, dynamic> payload) => '';

  /// 从非流式响应提取工具调用。
  List<ProviderToolCall> extractToolCalls(Map<dynamic, dynamic> payload) =>
      const [];

  /// 保留本次助手输出中下一步必须原样回传的协议原生块。
  Map<String, Object?>? extractNativeContinuation(
    Map<dynamic, dynamic> payload,
  ) => null;

  /// 从一个 SSE 帧提取文本增量。
  String streamTextFromFrame(SseFrame frame);

  /// 从一个 SSE 帧提取正文，并声明上游返回的是增量还是累计全文。
  ///
  /// 大多数标准协议都返回增量，因此默认沿用 [streamTextFromFrame]。
  /// 只有能从协议字段明确识别累计全文的适配器才要覆写，不得通过
  /// 内容相似度猜测。
  ProviderStreamTextChunk streamTextChunkFromFrame(SseFrame frame) =>
      ProviderStreamTextChunk.incremental(streamTextFromFrame(frame));

  /// 从一个 SSE 帧提取 reasoning 增量。
  String streamReasoningFromFrame(SseFrame frame) => '';

  /// 从 SSE 流中提取工具调用（累积所有帧后调用）。
  List<ProviderToolCall> streamExtractToolCalls(List<SseFrame> frames) =>
      const [];

  Map<String, Object?>? streamExtractNativeContinuation(
    List<SseFrame> frames,
  ) => null;

  /// 判断一个协议帧是否明确结束当前 HTTP 流。
  ProviderStreamTerminal streamTerminalFromFrame(SseFrame frame) =>
      const ProviderStreamTerminal.none();

  /// 构造图片理解请求体（vision 能力探针用）。
  /// 默认走 OpenAI Chat content 数组格式，由各协议覆写。
  Map<String, Object?> visionPayload(
    String modelId,
    List<Map<String, Object?>> messages,
    String imageDataUrl, {
    int? maxTokens,
    String? instruction,
  }) {
    final visionMessages = List<Map<String, Object?>>.from(messages);
    visionMessages.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': instruction ?? '请只回答图片顶部文字末尾的三位数字。'},
        {
          'type': 'image_url',
          'image_url': {'url': imageDataUrl},
        },
      ],
    });
    return textPayload(modelId, visionMessages, maxTokens: maxTokens);
  }

  /// Build a provider-native short-audio request. `null` means this protocol
  /// has no official inline audio representation and must not be guessed.
  Map<String, Object?>? audioPayload(
    String modelId,
    List<Map<String, Object?>> messages,
    AudioPayloadData audio, {
    int? maxTokens,
    String? instruction,
  }) => null;

  /// 构造工具调用探针请求体。
  /// 各协议工具结构不同（OpenAI tools[] / Responses tools[] / Anthropic tools[] / Gemini functionDeclarations）。
  Map<String, Object?> toolProbePayload(
    String modelId,
    String toolName,
    String instruction, {
    String? providerId,
    String expectedCode = 'AZ731',
  });

  /// 构造结构化输出探针请求体。
  Map<String, Object?> structuredProbePayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  });

  /// 严格结构化格式被服务拒绝后的真实回退请求。只有协议能够提供
  /// 仍然可验证的结构化语义时才覆写；null 表示没有安全回退。
  Map<String, Object?>? structuredFallbackPayload(
    String modelId,
    String instruction,
    Map<String, Object?> schema, {
    String? providerId,
  }) => null;

  /// 判断该协议是否支持结构化输出探针（Gemini 用 responseSchema，Anthropic 用 forced tool）。
  /// 默认 true；不支持时探针返回 unsupported。
  bool supportsStructuredProbe() => true;

  /// 判断该协议的结构化探针是否通过 forced tool 实现（Anthropic）。
  /// 若是，结构化探针复用工具调用路径。
  bool structuredViaTool() => false;
}

enum ProviderStreamTextKind { incremental, cumulative }

class ProviderStreamTextChunk {
  const ProviderStreamTextChunk._(this.text, this.kind);

  const ProviderStreamTextChunk.incremental(String text)
    : this._(text, ProviderStreamTextKind.incremental);

  const ProviderStreamTextChunk.cumulative(String text)
    : this._(text, ProviderStreamTextKind.cumulative);

  final String text;
  final ProviderStreamTextKind kind;
}

/// 把协议已明确标记的增量/累计全文统一转为可展示增量。
///
/// 累计全文只接受严格前缀续接。如果上游在同一次响应中改写了已接收正文，
/// 宁可保留已收到内容并按协议异常收口，也不重复拼接或猜测删字。
class ProviderStreamTextAccumulator {
  String _text = '';

  String get text => _text;

  String add(ProviderStreamTextChunk chunk) {
    final incoming = chunk.text;
    if (incoming.isEmpty) return '';
    if (chunk.kind == ProviderStreamTextKind.incremental) {
      _text += incoming;
      return incoming;
    }
    if (incoming == _text) return '';
    if (!incoming.startsWith(_text)) {
      throw const FormatException('模型流累计正文与已接收内容不一致');
    }
    final delta = incoming.substring(_text.length);
    _text = incoming;
    return delta;
  }
}

/// 用 Dio 执行一次非流式 POST，返回响应体（已尝试 JSON 解析）。
/// 出错时抛 AdapterRequestException（携带归一化错误）。
typedef ResponseProvider =
    Future<Response<dynamic>> Function(
      String url,
      Map<String, String> headers,
      Map<String, Object?> body,
    );
