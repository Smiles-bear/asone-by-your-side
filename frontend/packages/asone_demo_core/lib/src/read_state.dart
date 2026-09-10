/// Shared per-feature read timestamps for the demo stores.
///
/// Breaks the board <-> unread dependency cycle: content stores record
/// "latest assistant activity" against these timestamps, and the unread
/// store subscribes to [onChanged] to refresh its snapshot.
class DemoReadState {
  final Map<String, DateTime> _lastReadAt = {};

  /// Invoked by content stores after assistant-authored content changes.
  void Function()? onChanged;

  DateTime? lastRead(String key) => _lastReadAt[key];

  void setLastRead(String key, DateTime through) {
    final previous = _lastReadAt[key];
    if (previous == null || through.isAfter(previous)) {
      _lastReadAt[key] = through;
    }
  }

  void notify() => onChanged?.call();
}
