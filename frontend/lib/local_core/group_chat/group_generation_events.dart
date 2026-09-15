library;

import 'dart:async';

sealed class GroupGenerationEvent {
  const GroupGenerationEvent({
    required this.roomId,
    required this.roundId,
    this.messageId,
  });

  final String roomId;
  final String roundId;
  final String? messageId;
}

class GroupRoundStarted extends GroupGenerationEvent {
  const GroupRoundStarted({required super.roomId, required super.roundId});
}

class GroupStepStarted extends GroupGenerationEvent {
  const GroupStepStarted({
    required super.roomId,
    required super.roundId,
    required super.messageId,
    required this.assistantId,
    required this.position,
    required this.total,
  });

  final String assistantId;
  final int position;
  final int total;
}

class GroupReplyDelta extends GroupGenerationEvent {
  const GroupReplyDelta({
    required super.roomId,
    required super.roundId,
    required super.messageId,
    required this.delta,
  });

  final String delta;
}

class GroupReplySegmentBoundary extends GroupGenerationEvent {
  const GroupReplySegmentBoundary({
    required super.roomId,
    required super.roundId,
    required super.messageId,
  });
}

class GroupStepFinished extends GroupGenerationEvent {
  const GroupStepFinished({
    required super.roomId,
    required super.roundId,
    required super.messageId,
    required this.status,
  });

  final String status;
}

class GroupRoundFinished extends GroupGenerationEvent {
  const GroupRoundFinished({
    required super.roomId,
    required super.roundId,
    required this.status,
  });

  final String status;
}

class GroupGenerationEventBus {
  GroupGenerationEventBus();

  final StreamController<GroupGenerationEvent> _controller =
      StreamController<GroupGenerationEvent>.broadcast(sync: true);

  Stream<GroupGenerationEvent> get events => _controller.stream;

  Stream<GroupGenerationEvent> forRoom(String roomId) =>
      _controller.stream.where((event) => event.roomId == roomId);

  Stream<GroupGenerationEvent> forMessage(String roomId, String messageId) =>
      _controller.stream.where(
        (event) => event.roomId == roomId && event.messageId == messageId,
      );

  void emit(GroupGenerationEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> close() => _controller.close();
}

class GroupRoomReadEvents {
  GroupRoomReadEvents._();

  static final StreamController<String> _controller =
      StreamController<String>.broadcast(sync: true);

  static Stream<String> get changes => _controller.stream;

  static void notify(String roomId) {
    if (!_controller.isClosed) _controller.add(roomId);
  }
}
