import 'dart:async';

/// Chat Generation 任务的运行时事件
sealed class ChatGenerationEvent {
  const ChatGenerationEvent({
    required this.jobId,
    required this.conversationId,
  });

  final String jobId;
  final String conversationId;
}

/// 任务开始事件
class ChatGenerationStarted extends ChatGenerationEvent {
  const ChatGenerationStarted({
    required super.jobId,
    required super.conversationId,
  });
}

/// 正在输入/思考状态
class ChatGenerationTyping extends ChatGenerationEvent {
  const ChatGenerationTyping({
    required super.jobId,
    required super.conversationId,
    this.toolName,
  });

  final String? toolName;
}

/// 流式文本增量
class ChatGenerationDelta extends ChatGenerationEvent {
  const ChatGenerationDelta({
    required super.jobId,
    required super.conversationId,
    required this.delta,
  });

  final String delta;
}

/// 流式思考内容增量。
class ChatGenerationReasoningDelta extends ChatGenerationEvent {
  const ChatGenerationReasoningDelta({
    required super.jobId,
    required super.conversationId,
    required this.delta,
  });

  final String delta;
}

/// 段落边界（连续消息模式 - 实时多气泡）
class ChatGenerationBoundary extends ChatGenerationEvent {
  const ChatGenerationBoundary({
    required super.jobId,
    required super.conversationId,
  });
}

/// 段落提交（连续消息模式）
class ChatGenerationSegmentCommit extends ChatGenerationEvent {
  const ChatGenerationSegmentCommit({
    required super.jobId,
    required super.conversationId,
    required this.segmentIndex,
    required this.content,
  });

  final int segmentIndex;
  final String content;
}

/// 任务完成
class ChatGenerationCompleted extends ChatGenerationEvent {
  const ChatGenerationCompleted({
    required super.jobId,
    required super.conversationId,
    this.directorFallback = false,
  });

  final bool directorFallback;
}

/// 任务失败
class ChatGenerationFailed extends ChatGenerationEvent {
  const ChatGenerationFailed({
    required super.jobId,
    required super.conversationId,
    required this.error,
  });

  final String error;
}

/// 任务取消
class ChatGenerationCancelled extends ChatGenerationEvent {
  const ChatGenerationCancelled({
    required super.jobId,
    required super.conversationId,
  });
}

class ChatGenerationSnapshot {
  const ChatGenerationSnapshot({
    required this.jobId,
    required this.conversationId,
    required this.content,
    this.reasoning = '',
    this.toolName,
  });

  final String jobId;
  final String conversationId;
  final String content;
  final String reasoning;
  final String? toolName;

  bool get isTyping => content.trim().isEmpty;
}

/// Chat Generation 任务事件总线
///
/// 单例，Handler 发送事件，ChatPage 订阅事件
class ChatGenerationEventBus {
  ChatGenerationEventBus._();

  static final ChatGenerationEventBus instance = ChatGenerationEventBus._();

  final StreamController<ChatGenerationEvent> _controller =
      StreamController<ChatGenerationEvent>.broadcast();
  final Map<String, ChatGenerationSnapshot> _snapshots = {};

  /// 事件流（所有任务）
  Stream<ChatGenerationEvent> get events => _controller.stream;

  /// 按 conversationId 过滤的事件流
  Stream<ChatGenerationEvent> eventsForConversation(String conversationId) {
    return events.where((event) => event.conversationId == conversationId);
  }

  /// 按 jobId 过滤的事件流
  Stream<ChatGenerationEvent> eventsForJob(String jobId) {
    return events.where((event) => event.jobId == jobId);
  }

  ChatGenerationSnapshot? snapshotForConversation(String conversationId) =>
      _snapshots[conversationId];

  /// 发送事件
  void emit(ChatGenerationEvent event) {
    switch (event) {
      case ChatGenerationStarted():
        _snapshots[event.conversationId] = ChatGenerationSnapshot(
          jobId: event.jobId,
          conversationId: event.conversationId,
          content: '',
        );
      case ChatGenerationDelta():
        final current = _snapshots[event.conversationId];
        _snapshots[event.conversationId] = ChatGenerationSnapshot(
          jobId: event.jobId,
          conversationId: event.conversationId,
          content: (current?.content ?? '') + event.delta,
          reasoning: current?.reasoning ?? '',
          toolName: current?.toolName,
        );
      case ChatGenerationReasoningDelta():
        final current = _snapshots[event.conversationId];
        _snapshots[event.conversationId] = ChatGenerationSnapshot(
          jobId: event.jobId,
          conversationId: event.conversationId,
          content: current?.content ?? '',
          reasoning: (current?.reasoning ?? '') + event.delta,
          toolName: current?.toolName,
        );
      case ChatGenerationTyping():
        final current = _snapshots[event.conversationId];
        _snapshots[event.conversationId] = ChatGenerationSnapshot(
          jobId: event.jobId,
          conversationId: event.conversationId,
          content: current?.content ?? '',
          reasoning: current?.reasoning ?? '',
          toolName: event.toolName ?? current?.toolName,
        );
      case ChatGenerationBoundary():
        final current = _snapshots[event.conversationId];
        if (current != null && current.content.isNotEmpty) {
          _snapshots[event.conversationId] = ChatGenerationSnapshot(
            jobId: event.jobId,
            conversationId: event.conversationId,
            content: '${current.content}\n\n',
            reasoning: current.reasoning,
            toolName: current.toolName,
          );
        }
      case ChatGenerationCompleted() ||
          ChatGenerationFailed() ||
          ChatGenerationCancelled():
        _snapshots.remove(event.conversationId);
      default:
        break;
    }
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// 清理资源（测试用）
  void dispose() {
    _controller.close();
  }
}
