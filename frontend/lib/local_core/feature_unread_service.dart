import 'package:asone_contracts/asone_contracts.dart'
    show
        FeatureUnreadApi,
        FeatureUnreadKind,
        FeatureUnreadKindKey,
        FeatureUnreadSnapshot;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'core_database.dart';

export 'package:asone_contracts/asone_contracts.dart'
    show FeatureUnreadKind, FeatureUnreadKindKey, FeatureUnreadSnapshot;

/// 用户侧三个持续心智入口的统一未读状态。
class FeatureUnreadService implements FeatureUnreadApi {
  FeatureUnreadService({CoreDatabase? coreDatabase})
    : _coreDatabase = coreDatabase ?? CoreDatabase.instance;

  final CoreDatabase _coreDatabase;
  @override
  final ValueNotifier<FeatureUnreadSnapshot> changes = ValueNotifier(
    const FeatureUnreadSnapshot(),
  );
  bool _refreshing = false;
  bool _refreshPending = false;

  @override
  Future<FeatureUnreadSnapshot> refresh() async {
    if (_refreshing) {
      _refreshPending = true;
      return changes.value;
    }
    _refreshing = true;
    try {
      do {
        _refreshPending = false;
        final database = await _coreDatabase.open();
        final snapshot = FeatureUnreadSnapshot(
          stickyNote: await _hasUnread(database, FeatureUnreadKind.stickyNote),
          messageBoardCount: await messageBoardUnreadCount(database: database),
          calendar: await _hasUnread(database, FeatureUnreadKind.calendar),
        );
        if (snapshot != changes.value) changes.value = snapshot;
      } while (_refreshPending);
      return changes.value;
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> markRead(FeatureUnreadKind kind, {DateTime? through}) async {
    final database = await _coreDatabase.open();
    await database.transaction((transaction) async {
      final latest =
          through?.toUtc().toIso8601String() ??
          await _latestAssistantCreatedAt(transaction, kind);
      if (latest == null) return;
      await transaction.rawInsert(
        '''
        INSERT INTO feature_read_state (feature_key, last_read_at)
        VALUES (?, ?)
        ON CONFLICT(feature_key) DO UPDATE SET
          last_read_at = CASE
            WHEN excluded.last_read_at > feature_read_state.last_read_at
              THEN excluded.last_read_at
            ELSE feature_read_state.last_read_at
          END
        ''',
        <Object?>[kind.key, latest],
      );
    });
    await refresh();
  }

  Future<bool> _hasUnread(
    DatabaseExecutor database,
    FeatureUnreadKind kind,
  ) async {
    final latest = await _latestAssistantCreatedAt(database, kind);
    if (latest == null) return false;
    final rows = await database.query(
      'feature_read_state',
      columns: const ['last_read_at'],
      where: 'feature_key = ?',
      whereArgs: <Object?>[kind.key],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    return latest.compareTo(rows.single['last_read_at']! as String) > 0;
  }

  @override
  Future<int> messageBoardUnreadCount({
    String? assistantId,
    DatabaseExecutor? database,
  }) async {
    final db = database ?? await _coreDatabase.open();
    final readRows = await db.query(
      'feature_read_state',
      columns: const ['last_read_at'],
      where: 'feature_key = ?',
      whereArgs: const <Object?>['message_board'],
      limit: 1,
    );
    final lastReadAt = readRows.firstOrNull?['last_read_at'] as String? ?? '';
    final assistantFilter = assistantId == null
        ? ''
        : ' AND author_assistant_id = ?';
    final args = <Object?>[
      lastReadAt,
      if (assistantId != null) assistantId,
      lastReadAt,
      if (assistantId != null) assistantId,
    ];
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS unread_count FROM (
        SELECT post_id AS item_id FROM board_posts
        WHERE author_type = 'assistant' AND deleted_at IS NULL
          AND created_at > ?$assistantFilter
        UNION ALL
        SELECT comment_id AS item_id FROM board_comments
        WHERE author_type = 'assistant' AND deleted_at IS NULL
          AND created_at > ?$assistantFilter
      )
      ''', args);
    return (rows.single['unread_count'] as num?)?.toInt() ?? 0;
  }

  Future<String?> _latestAssistantCreatedAt(
    DatabaseExecutor database,
    FeatureUnreadKind kind,
  ) async {
    final rows = await database.rawQuery(switch (kind) {
      FeatureUnreadKind.stickyNote =>
        '''
        SELECT MAX(created_at) AS latest
        FROM global_notes
        WHERE author_type = 'assistant'
          AND status != 'deleted' AND deleted_at IS NULL
      ''',
      FeatureUnreadKind.messageBoard =>
        '''
        SELECT MAX(created_at) AS latest FROM (
          SELECT created_at FROM board_posts
          WHERE author_type = 'assistant' AND deleted_at IS NULL
          UNION ALL
          SELECT created_at FROM board_comments
          WHERE author_type = 'assistant' AND deleted_at IS NULL
        )
      ''',
      FeatureUnreadKind.calendar =>
        '''
        SELECT MAX(created_at) AS latest
        FROM calendar_events
        WHERE author_type = 'assistant' AND deleted_at IS NULL
      ''',
    });
    return rows.firstOrNull?['latest'] as String?;
  }
}
