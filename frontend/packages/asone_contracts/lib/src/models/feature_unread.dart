/// Unread state kinds of the user-facing feature entries.
enum FeatureUnreadKind { stickyNote, messageBoard, calendar }

/// Stable storage keys for [FeatureUnreadKind].
extension FeatureUnreadKindKey on FeatureUnreadKind {
  String get key => switch (this) {
    FeatureUnreadKind.stickyNote => 'sticky_note',
    FeatureUnreadKind.messageBoard => 'message_board',
    FeatureUnreadKind.calendar => 'calendar',
  };
}

/// Snapshot of unread flags across the feature entries.
class FeatureUnreadSnapshot {
  const FeatureUnreadSnapshot({
    this.stickyNote = false,
    this.messageBoardCount = 0,
    this.calendar = false,
  });

  final bool stickyNote;
  final int messageBoardCount;
  final bool calendar;

  bool get messageBoard => messageBoardCount > 0;

  bool get any => stickyNote || messageBoard || calendar;

  bool contains(FeatureUnreadKind kind) => switch (kind) {
    FeatureUnreadKind.stickyNote => stickyNote,
    FeatureUnreadKind.messageBoard => messageBoard,
    FeatureUnreadKind.calendar => calendar,
  };

  @override
  bool operator ==(Object other) =>
      other is FeatureUnreadSnapshot &&
      other.stickyNote == stickyNote &&
      other.messageBoardCount == messageBoardCount &&
      other.calendar == calendar;

  @override
  int get hashCode => Object.hash(stickyNote, messageBoardCount, calendar);
}
