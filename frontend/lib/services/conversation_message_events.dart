import 'dart:async';

import '../models/message.dart';

class ConversationMessageEvent {
  const ConversationMessageEvent({required this.conversationId, this.message});

  final String conversationId;
  final Message? message;
}

class ConversationMessageEvents {
  ConversationMessageEvents._();

  static final _controller =
      StreamController<ConversationMessageEvent>.broadcast();

  static Stream<ConversationMessageEvent> get changes => _controller.stream;

  static void notify(String conversationId, {Message? message}) {
    if (!_controller.isClosed) {
      _controller.add(
        ConversationMessageEvent(
          conversationId: conversationId,
          message: message,
        ),
      );
    }
  }
}

class ConversationReadEvents {
  ConversationReadEvents._();

  static final _controller = StreamController<String>.broadcast();

  static Stream<String> get changes => _controller.stream;

  static void notify(String conversationId) {
    if (!_controller.isClosed) _controller.add(conversationId);
  }
}
