// 聊天引擎公开接缝契约（第四轮 R2b）。
//
// 引擎（local_chat_service.dart）公开/私有共享同一套代码；所有私有域能力
// （记忆上下文编译、工具运行时、游戏、一起听/共享活动、延迟动作、自动日记、
// 设备上下文装饰、一起听轮次串行化）经本文件的策略接口注入：
// - 私有版由 attachPrivateChatEngineBindings()（私有聚合初始化时调用）挂载真实实现；
// - 公开版不挂载，字段为 null 即 no-op（工具 schema 为空 → 工具循环不触发；
//   游戏/一起听/延迟动作分支全部短路）。
//
// 语义红线（设计文档 §4）：中断恢复、消息可见性过滤、瞬态重试语义在引擎内
// 原样保留，不属于任何策略。
import 'package:dio/dio.dart';

import '../../models/message.dart';
import '../../tool_runtime/tool_executor.dart';
import '../../tool_runtime/tool_result.dart';
import '../assistant_execution_context.dart';
import '../chat_context_window_planner.dart';
import '../core_database.dart';

/// 一次发送的已编译上下文（私有实现 = 执行上下文解析器 + 记忆冻结编译）。
class ChatEngineTurnContext {
  const ChatEngineTurnContext({
    required this.assistantId,
    required this.modelSnapshot,
    required this.context,
    this.requestId,
  });

  final String assistantId;
  final ModelBindingSnapshot modelSnapshot;
  final Map<String, Object?> context;
  final String? requestId;
}

abstract interface class ChatContextCompiler {
  Future<ChatEngineTurnContext> compileTurnContext({
    required String conversationId,
    required String query,
    String? excludedMessageId,
    String? currentMessageId,
  });
}

/// 工具执行运行时（私有实现为私有工具服务门面）。
///
/// 公开版为 null：工具 schema 策略同为 null → 请求不携带任何工具，
/// 模型不会产生 tool_calls，执行路径不可达（Q3：保留但禁用）。
abstract interface class ChatToolRuntime {
  /// 模型给出的工具名 → 工具 ID（别名表未命中时原样返回）。
  String resolveToolId(String modelName, Map<String, String> aliasToToolId);

  Future<ToolResult> executeTool({
    required ToolCall call,
    required ToolContext context,
  });

  Future<ToolResult> awaitUserConfirmation({
    required ToolCall call,
    required ToolContext context,
    required ToolResult initialResult,
    void Function(String requestId)? onPendingCreated,
  });
}

/// 工具 schema 准备请求（纯数据）。
class ChatToolSchemaRequest {
  const ChatToolSchemaRequest({
    required this.assistantId,
    required this.conversationId,
    required this.modelServiceId,
    required this.timestampsEnabled,
    required this.toolsEnabled,
    required this.queryText,
    required this.previousText,
    required this.hasAnswerVersion,
    required this.automaticTogetherListenTurn,
    required this.forceGameOffer,
    required this.toolIdDenylist,
    this.forcedRelevantToolIds = const <String>{},
    this.sessionId,
    this.allowedToolIds,
  });

  final String assistantId;
  final String conversationId;
  final String modelServiceId;
  final bool timestampsEnabled;
  final bool toolsEnabled;
  final String queryText;
  final String previousText;
  final bool hasAnswerVersion;
  final bool automaticTogetherListenTurn;
  final bool forceGameOffer;
  final Set<String> toolIdDenylist;
  final Set<String> forcedRelevantToolIds;
  final String? sessionId;
  final Set<String>? allowedToolIds;
}

/// 工具 schema 准备结果（纯数据）。
class ChatToolSchemaSetup {
  const ChatToolSchemaSetup({
    required this.tools,
    required this.aliasToToolId,
    required this.candidateToolIds,
    required this.excludedToolReasons,
    required this.holdVisibleReply,
  });

  const ChatToolSchemaSetup.empty()
    : tools = const [],
      aliasToToolId = const {},
      candidateToolIds = const [],
      excludedToolReasons = const {},
      holdVisibleReply = false;

  final List<Map<String, Object?>> tools;
  final Map<String, String> aliasToToolId;
  final List<String> candidateToolIds;
  final Map<String, String> excludedToolReasons;
  final bool holdVisibleReply;
}

abstract interface class ChatToolSchemaStrategy {
  Future<ChatToolSchemaSetup> prepareToolSchema(ChatToolSchemaRequest request);
}

/// 游戏邀请方向（私有 GameOfferDirection 的公开镜像，值一一对应）。
enum ChatGameOfferDirection { userInvitesAssistant, assistantInvitesUser }

/// 游戏邀请识别结果。
class ChatGameOffer {
  const ChatGameOffer({required this.direction, required this.gameName});

  final ChatGameOfferDirection direction;
  final String gameName;
}

/// recall_game 工具的媒体消息构建结果。
class ChatRecallMedia {
  const ChatRecallMedia({required this.toolContent, this.mediaMessage});

  final String toolContent;
  final Map<String, Object?>? mediaMessage;
}

/// 游戏域策略（邀请意图、疑似邀请提示、召回媒体、回合摘要计数）。
abstract interface class ChatGameStrategy {
  ChatGameOffer? detectOffer(String content);

  String suspectedInvitationHint(String gameName);

  /// 邀请工具名（私有实现 = gameOfferToolName）。
  String get offerToolName;

  /// toolName 非召回工具时实现必须返回 null（引擎不再判断游戏工具名）。
  Future<ChatRecallMedia?> buildRecallMedia({
    required String toolName,
    required ToolResult toolResult,
    required String modelServiceId,
    required String assistantId,
    required String conversationId,
  });

  Future<void> consumeTurn({
    required String sessionId,
    required String assistantId,
    required String conversationId,
  });
}

/// 一起听活动上下文快照（公开 DTO；私有实现来自共享活动上下文提供器）。
class ChatListenSnapshot {
  const ChatListenSnapshot({
    required this.sessionId,
    required this.sessionCreatedAt,
    required this.systemContextBody,
    this.activityId,
  });

  final String sessionId;
  final DateTime sessionCreatedAt;
  final String systemContextBody;
  final String? activityId;
}

/// 共享消息关联来源（值与私有存储层常量对齐）。
abstract final class ChatSharedActivityOrigins {
  static const userInput = 'user_input';
  static const automaticTrackEvent = 'automatic_track_event';
}

/// 一起听/共享活动策略（活动上下文、消息关联、自动切轨事件文案、回合计数）。
abstract interface class ChatSharedActivityStrategy {
  Future<ChatListenSnapshot?> resolveActiveListen({
    required String assistantId,
    required String conversationId,
  });

  String get automaticTrackEventText;

  Future<void> linkMessage({
    required String activityId,
    required String assistantId,
    required String conversationId,
    required String chatMessageId,
    required String origin,
  });

  Future<void> consumeTurn({
    required String activityId,
    required String assistantId,
    required String conversationId,
  });
}

/// 延迟动作提交结果（私有实现为动作单协调器）。
class ChatDeferredActionResult {
  const ChatDeferredActionResult({this.message, this.failureMessage});

  final Message? message;
  final String? failureMessage;
}

/// 延迟动作处理（动作单仅由工具结果产生；公开版工具禁用 → 不可达）。
abstract interface class ChatDeferredActionHandler {
  Future<ChatDeferredActionResult> executeAndCommit({
    required String actionId,
    required String draftMessage,
    required Future<Message> Function(String text) commitMessage,
  });

  /// 取消处于 prepared/messageReady 状态的动作单（异常由实现内部消化）。
  Future<void> cancelPrepared(String actionId);
}

/// 自动日记钩子（私有实现持有定时器与完整日记引擎；公开版另有降级链，
/// 不走本钩子）。
abstract interface class ChatAutoDiaryHook {
  void onChatCompleted(String assistantId, String conversationId);
}

/// 私有实现挂载点。工厂签名与引擎构造参数对齐（coreDatabase 透传，
/// 与 MessageVersionLifecycleHooksBinding 同模式）。
final class ChatEngineBindings {
  ChatEngineBindings._();

  static ChatContextCompiler Function({CoreDatabase? coreDatabase})?
  createContextCompiler;

  static ChatToolRuntime Function()? createToolRuntime;

  static ChatToolSchemaStrategy Function({CoreDatabase? coreDatabase})?
  createToolSchemaStrategy;

  static ChatGameStrategy Function({CoreDatabase? coreDatabase})?
  createGameStrategy;

  static ChatSharedActivityStrategy Function({CoreDatabase? coreDatabase})?
  createSharedActivityStrategy;

  static ChatDeferredActionHandler Function({CoreDatabase? coreDatabase})?
  createDeferredActionHandler;

  static ChatAutoDiaryHook Function()? createAutoDiaryHook;

  /// 工具调用元数据装饰（私有实现注入设备聊天上下文）。
  static void Function(
    Map<String, Object?> metadata,
    ChatContextWindowPlan plan,
    CancelToken? cancelToken,
    List<Map<String, Object?>> toolMessages,
  )?
  decorateToolCallMetadata;

  /// 一起听轮次串行化：返回 true 表示本轮已由协调器接管执行。
  static Future<bool> Function(
    String conversationId,
    Future<void> Function() turn,
  )?
  tryRunViaTurnCoordinator;
}
