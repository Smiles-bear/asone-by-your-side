/// 工具执行器接口
///
/// 定义工具执行的统一接口，所有工具适配器都必须实现此接口。
library;

import 'tool_result.dart';

/// 工具调用数据
///
/// 封装单次工具调用的输入参数和标识信息。
class ToolCall {
  /// 工具唯一标识符（格式：sourceId.toolName）
  final String toolId;

  /// 调用唯一标识符（用于追踪和取消）
  final String callId;

  /// 工具输入参数
  final Map<String, dynamic> arguments;

  /// 创建工具调用
  const ToolCall({
    required this.toolId,
    required this.callId,
    required this.arguments,
  });

  /// 从 JSON 对象创建
  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      toolId: json['toolId'] as String,
      callId: json['callId'] as String,
      arguments: Map<String, dynamic>.from(json['arguments'] as Map),
    );
  }

  /// 转换为 JSON 对象
  Map<String, dynamic> toJson() {
    return {'toolId': toolId, 'callId': callId, 'arguments': arguments};
  }

  @override
  String toString() {
    return 'ToolCall(toolId: $toolId, callId: $callId, arguments: $arguments)';
  }
}

/// 工具执行上下文
///
/// 提供工具执行时的上下文信息，包括助手、会话和用户信息。
class ToolContext {
  /// 助手 ID
  final String assistantId;

  /// 会话 ID
  final String conversationId;

  /// 用户 ID（可选）
  final String? userId;

  /// 额外的上下文数据
  final Map<String, dynamic> metadata;

  /// 是否允许后台执行
  final bool allowBackground;

  /// 创建工具执行上下文
  const ToolContext({
    required this.assistantId,
    required this.conversationId,
    this.userId,
    this.metadata = const {},
    this.allowBackground = false,
  });

  /// 从 JSON 对象创建
  factory ToolContext.fromJson(Map<String, dynamic> json) {
    return ToolContext(
      assistantId: json['assistantId'] as String,
      conversationId: json['conversationId'] as String,
      userId: json['userId'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      allowBackground: json['allowBackground'] as bool? ?? false,
    );
  }

  /// 转换为 JSON 对象
  Map<String, dynamic> toJson() {
    return {
      'assistantId': assistantId,
      'conversationId': conversationId,
      if (userId != null) 'userId': userId,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'allowBackground': allowBackground,
    };
  }

  @override
  String toString() {
    return 'ToolContext(assistantId: $assistantId, conversationId: $conversationId, userId: $userId)';
  }
}

/// 工具执行器抽象接口
///
/// 所有工具适配器都必须实现此接口，提供统一的工具执行能力。
///
/// 实现示例：
/// ```dart
/// class MyToolAdapter implements ToolExecutor {
///   @override
///   Future<ToolResult> execute({
///     required String toolId,
///     required Map<String, dynamic> arguments,
///     required String callId,
///     required ToolContext context,
///   }) async {
///     // 实现工具逻辑
///     return ToolResult.success(
///       data: {'result': 'done'},
///       executionTimeMs: 100,
///     );
///   }
///
///   @override
///   Future<bool> cancel(String callId) async {
///     // 实现取消逻辑
///     return true;
///   }
///
///   @override
///   Future<bool> supports(String toolId) async {
///     // 检查是否支持指定工具
///     return toolId.startsWith('my_adapter.');
///   }
/// }
/// ```
abstract class ToolExecutor {
  /// 执行工具调用
  ///
  /// [toolId] 工具唯一标识符
  /// [arguments] 工具输入参数
  /// [callId] 调用唯一标识符（用于追踪和取消）
  /// [context] 执行上下文
  ///
  /// 返回工具执行结果，永远不会抛出异常（所有错误都封装在 ToolResult 中）。
  Future<ToolResult> execute({
    required String toolId,
    required Map<String, dynamic> arguments,
    required String callId,
    required ToolContext context,
  });

  /// 取消正在执行的工具调用
  ///
  /// [callId] 调用唯一标识符
  ///
  /// 返回是否成功取消。如果调用不存在或已完成，返回 false。
  Future<bool> cancel(String callId);

  /// 检查是否支持指定工具
  ///
  /// [toolId] 工具唯一标识符
  ///
  /// 返回 true 表示此执行器可以执行该工具，false 表示不支持。
  Future<bool> supports(String toolId);
}

/// An executor can supply a bounded deadline for a validated multi-step call.
abstract interface class ManagedToolDeadline {
  Future<Duration?> executionDeadline(ToolCall call, ToolContext context);
}

/// 工具执行器注册表
///
/// 管理工具执行器的注册和查询，根据工具 ID 查找对应的执行器。
class ToolExecutorRegistry {
  /// 执行器存储：sourceId -> ToolExecutor
  final Map<String, ToolExecutor> _executors = {};

  /// 注册执行器
  ///
  /// [sourceId] 来源 ID（如 'mock', 'local', 'http'）
  /// [executor] 执行器实例
  void register(String sourceId, ToolExecutor executor) {
    _executors[sourceId] = executor;
  }

  /// 注销执行器
  ///
  /// [sourceId] 来源 ID
  void unregister(String sourceId) {
    _executors.remove(sourceId);
  }

  /// 根据工具 ID 获取执行器
  ///
  /// [toolId] 工具 ID（格式：sourceId.toolName）
  ///
  /// 返回对应的执行器，如果未注册则返回 null。
  Future<ToolExecutor?> getExecutor(String toolId) async {
    // 从 toolId 中提取 sourceId
    final parts = toolId.split('.');
    if (parts.length < 2) {
      return null;
    }

    final sourceId = parts[0];
    final executor = _executors[sourceId];

    if (executor == null) {
      return null;
    }

    // 检查执行器是否支持此工具
    final supported = await executor.supports(toolId);
    return supported ? executor : null;
  }

  /// 获取所有已注册的执行器
  ///
  /// 返回执行器列表
  List<ToolExecutor> getAllExecutors() {
    return _executors.values.toList();
  }

  /// 获取所有已注册的 sourceId
  ///
  /// 返回 sourceId 列表
  List<String> getAllSourceIds() {
    return _executors.keys.toList();
  }

  /// 检查是否已注册指定来源的执行器
  ///
  /// [sourceId] 来源 ID
  ///
  /// 返回是否已注册
  bool isRegistered(String sourceId) {
    return _executors.containsKey(sourceId);
  }

  /// 清空所有执行器
  void clear() {
    _executors.clear();
  }
}
