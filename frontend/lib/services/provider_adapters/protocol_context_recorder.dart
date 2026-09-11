/// 协议请求上下文记录接缝。
///
/// 宿主版本可在启动时通过 [ProtocolContextRecorder.current] 挂载真实
/// 记录器（把模型请求/响应上下文写入开发调试记录）；未挂载时协议调用
/// 不做任何上下文记录，公开子集借此保持零私有依赖。
abstract interface class ProtocolContextRecorder {
  /// 进程级绑定点：宿主启动时挂载真实记录器；公开壳保持 null。
  static ProtocolContextRecorder? current;

  /// 记录一次请求上下文，返回请求标识（供 [updateResponse] 关联）。
  String recordRequest({
    required String modelId,
    required List<Map<String, dynamic>> messages,
    required String baseUrl,
    int? maxTokens,
    double? temperature,
    String? protocol,
    String? conversationId,
    String? assistantId,
    List<Map<String, String>>? systemParts,
    List<Map<String, Object?>>? recentMessages,
    Map<String, Object?>? contextMetadata,
  });

  /// 关联请求标识补记响应结果（正文预览、错误码或工具调用）。
  void updateResponse(
    String requestId,
    String response, {
    String? error,
    List<Map<String, Object?>>? toolCalls,
  });
}
