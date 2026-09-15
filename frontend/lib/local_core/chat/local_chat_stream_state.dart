import '../../models/message.dart';
import '../continuous_message_parser.dart';

typedef LocalChatStreamingMessageCreator =
    Future<Message> Function(String initialContent);

class LocalChatStreamState {
  LocalChatStreamState({
    required bool continuous,
    required this.holdVisibleReply,
    required this.onDelta,
    this.onSegmentBoundary,
    this.createStreamingMessage,
    this.onMessageCreated,
  }) : _parser = continuous ? ContinuousMessageParser() : null;

  final bool holdVisibleReply;
  final void Function(String delta) onDelta;
  final void Function()? onSegmentBoundary;
  final LocalChatStreamingMessageCreator? createStreamingMessage;
  final void Function(Message message)? onMessageCreated;

  final ContinuousMessageParser? _parser;
  final StringBuffer _currentSegmentBuffer = StringBuffer();
  final List<String> _completedSegments = <String>[];
  final StringBuffer _completeTextBuffer = StringBuffer();

  bool _justCrossedBoundary = false;
  bool _finished = false;
  Future<Message>? _messageCreationFuture;

  bool get isContinuous => _parser != null;

  Future<Message>? get messageCreationFuture => _messageCreationFuture;

  Future<Message>? ensurePersistentMessage({String initialContent = ''}) {
    final existing = _messageCreationFuture;
    if (existing != null) return existing;
    final create = createStreamingMessage;
    if (create == null) return null;
    final future = create(initialContent);
    _messageCreationFuture = future;
    final notify = onMessageCreated;
    if (notify != null) future.then(notify);
    return future;
  }

  List<String> get completedSegments =>
      List<String>.unmodifiable(_completedSegments);

  String get visibleContent {
    if (!isContinuous) return _completeTextBuffer.toString();
    if (_finished) return _completedSegments.join('\n\n');
    return <String>[
      ..._completedSegments,
      if (_currentSegmentBuffer.toString().trim().isNotEmpty)
        _currentSegmentBuffer.toString(),
    ].join('\n\n');
  }

  String get finalText => isContinuous
      ? _completedSegments.join('\n\n')
      : _completeTextBuffer.toString();

  void addDelta(String delta) {
    if (_finished) return;
    final parser = _parser;
    if (parser == null) {
      _ensureStreamingMessage(delta);
      _completeTextBuffer.write(delta);
      if (!holdVisibleReply) onDelta(delta);
      return;
    }

    for (final event in parser.feed(delta)) {
      if (event is TextAppendEvent) {
        _appendContinuousText(event.text, allowMessageCreation: true);
      } else if (event is SegmentBoundaryEvent) {
        _completeCurrentSegment(notifyBoundary: true);
        _currentSegmentBuffer.clear();
        _justCrossedBoundary = true;
      }
    }
  }

  void finish() {
    if (_finished) return;
    final parser = _parser;
    if (parser != null && !parser.isFinished) {
      for (final event in parser.finish()) {
        if (event is TextAppendEvent && event.text.trim().isNotEmpty) {
          _appendContinuousText(event.text, allowMessageCreation: false);
        }
      }
      _completeCurrentSegment(notifyBoundary: false);
    }
    _finished = true;
  }

  void _appendContinuousText(
    String safeText, {
    required bool allowMessageCreation,
  }) {
    if (_justCrossedBoundary) {
      _currentSegmentBuffer.write(safeText);
      if (safeText.trim().isNotEmpty) {
        if (!holdVisibleReply) {
          onDelta(_currentSegmentBuffer.toString());
        }
        _justCrossedBoundary = false;
      }
    } else {
      _currentSegmentBuffer.write(safeText);
      if (!holdVisibleReply) onDelta(safeText);
    }

    if (allowMessageCreation) _ensureStreamingMessage(safeText);
  }

  void _completeCurrentSegment({required bool notifyBoundary}) {
    final currentSegment = _currentSegmentBuffer.toString();
    if (currentSegment.trim().isEmpty) return;
    _completedSegments.add(currentSegment);
    if (notifyBoundary && !holdVisibleReply) onSegmentBoundary?.call();
  }

  void _ensureStreamingMessage(String initialContent) {
    if (holdVisibleReply ||
        _messageCreationFuture != null ||
        initialContent.trim().isEmpty) {
      return;
    }
    final create = createStreamingMessage;
    if (create == null) return;

    ensurePersistentMessage(initialContent: initialContent);
  }
}
