import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:asone_contracts/asone_contracts.dart';

import '../read_state.dart';
import 'board_store.dart';
import 'calendar_store.dart';
import 'sticky_note_store.dart';

/// In-memory [FeatureUnreadApi] implementation.
class DemoFeatureUnreadStore implements FeatureUnreadApi {
  DemoFeatureUnreadStore({
    required DemoReadState readState,
    required DemoBoardStore board,
    required DemoStickyNoteStore stickyNotes,
    required DemoCalendarStore calendar,
  }) : _readState = readState,
       _board = board,
       _stickyNotes = stickyNotes,
       _calendar = calendar {
    _readState.onChanged = () => unawaited(refresh());
    unawaited(refresh());
  }

  final DemoReadState _readState;
  final DemoBoardStore _board;
  final DemoStickyNoteStore _stickyNotes;
  final DemoCalendarStore _calendar;

  @override
  final ValueNotifier<FeatureUnreadSnapshot> changes = ValueNotifier(
    const FeatureUnreadSnapshot(),
  );

  bool _hasUnread(String key, DateTime? latest) {
    if (latest == null) return false;
    final lastRead = _readState.lastRead(key);
    return lastRead == null || latest.isAfter(lastRead);
  }

  @override
  Future<FeatureUnreadSnapshot> refresh() async {
    // 演示数据全在内存：同步计算，避免并发 refresh 的竞态与陈旧快照。
    final snapshot = FeatureUnreadSnapshot(
      stickyNote: _hasUnread(
        'sticky_note',
        _stickyNotes.latestAssistantCreatedAt(),
      ),
      messageBoardCount: _board.unreadCountSync(),
      calendar: _hasUnread('calendar', _calendar.latestAssistantCreatedAt()),
    );
    if (snapshot != changes.value) changes.value = snapshot;
    return snapshot;
  }

  @override
  Future<void> markRead(FeatureUnreadKind kind, {DateTime? through}) async {
    _readState.setLastRead(kind.key, through ?? DateTime.now());
    await refresh();
  }

  @override
  Future<int> messageBoardUnreadCount({String? assistantId}) =>
      _board.unreadCount(assistantId: assistantId);
}
