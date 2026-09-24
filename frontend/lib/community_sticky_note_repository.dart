import 'dart:math';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:sqflite/sqflite.dart';

import 'local_core/core_database.dart';

/// 社区版便签仓储。
///
/// 便签只保存用户主动创建或编辑的内容，不创建连续性事件、助手提醒
/// 或其他后台副作用。
class CommunityStickyNoteRepository implements StickyNoteRepositoryApi {
  CommunityStickyNoteRepository({required CoreDatabase database})
    : _database = database;

  final CoreDatabase _database;
  final Random _random = Random.secure();

  static const _notesTable = 'global_notes';
  static const _itemsTable = 'sticky_note_items';
  static const _paletteCount = 6;

  String _id(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${_random.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0')}';

  @override
  Future<StickyNoteItem> createTextNote({
    String? title,
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? originConversationId,
    String? sourceType,
    String? sourceId,
    DateTime? effectiveAt,
    DateTime? expiresAt,
  }) async {
    final body = content.trim();
    if (body.isEmpty) throw ArgumentError('请填写纸条内容');
    _validateAuthor(authorType, authorAssistantId);
    final now = DateTime.now().toUtc();
    final db = await _database.open();
    final note = StickyNoteItem(
      noteId: _id('n'),
      title: _optional(title),
      content: body,
      authorType: authorType,
      authorAssistantId: authorAssistantId,
      originConversationId: originConversationId,
      sourceType: sourceType,
      sourceId: sourceId,
      paletteKey: _random.nextInt(_paletteCount),
      tapeStyle: _random.nextInt(2),
      wallOrder: await _nextOrder(db, pinned: false),
      createdAt: now,
      updatedAt: now,
      effectiveAt: effectiveAt?.toUtc(),
      expiresAt: expiresAt?.toUtc(),
    );
    await db.insert(_notesTable, note.toJson());
    return note;
  }

  @override
  Future<StickyNoteDetail> createChecklistNote({
    String? title,
    required List<String> items,
    List<StickyNoteChecklistDraft>? checklistEntries,
    required String authorType,
    String? authorAssistantId,
    String? originConversationId,
    String? sourceType,
    String? sourceId,
    DateTime? expiresAt,
  }) async {
    final cleaned =
        (checklistEntries ??
                items.map((item) => StickyNoteChecklistDraft(content: item)))
            .map(
              (item) => StickyNoteChecklistDraft(
                content: item.content.trim(),
                checked: item.checked,
              ),
            )
            .where((item) => item.content.isNotEmpty)
            .toList();
    if (cleaned.isEmpty) throw ArgumentError('请至少填写一项清单');
    _validateAuthor(authorType, authorAssistantId);
    final now = DateTime.now().toUtc();
    final allChecked = cleaned.every((item) => item.checked);
    final db = await _database.open();
    late StickyNoteItem note;
    final checklist = <StickyNoteChecklistItem>[];
    await db.transaction((txn) async {
      note = StickyNoteItem(
        noteId: _id('n'),
        title: _optional(title),
        content: '',
        noteType: 'checklist',
        authorType: authorType,
        authorAssistantId: authorAssistantId,
        originConversationId: originConversationId,
        sourceType: sourceType,
        sourceId: sourceId,
        completionState: allChecked ? 'completed' : 'open',
        completionReason: allChecked ? 'completed' : null,
        completedAt: allChecked ? now : null,
        paletteKey: _random.nextInt(_paletteCount),
        tapeStyle: _random.nextInt(2),
        wallOrder: await _nextOrder(txn, pinned: false),
        createdAt: now,
        updatedAt: now,
        expiresAt: expiresAt?.toUtc(),
      );
      await txn.insert(_notesTable, note.toJson());
      for (var index = 0; index < cleaned.length; index++) {
        final item = StickyNoteChecklistItem(
          itemId: _id('i'),
          noteId: note.noteId,
          content: cleaned[index].content,
          position: index,
          checked: cleaned[index].checked,
          checkedAt: cleaned[index].checked ? now : null,
          createdAt: now,
          updatedAt: now,
        );
        checklist.add(item);
        await txn.insert(_itemsTable, item.toJson());
      }
    });
    return StickyNoteDetail(note: note, items: checklist);
  }

  @override
  Future<StickyNoteItem> post({
    required String content,
    required String authorType,
    String? authorAssistantId,
    String? sourceType,
    String? sourceId,
    String? originConversationId,
    DateTime? effectiveAt,
    DateTime? expiresAt,
  }) => createTextNote(
    content: content,
    authorType: authorType,
    authorAssistantId: authorAssistantId,
    sourceType: sourceType,
    sourceId: sourceId,
    originConversationId: originConversationId,
    effectiveAt: effectiveAt,
    expiresAt: expiresAt,
  );

  @override
  Future<StickyNoteDetail> updateNote({
    required String noteId,
    String? title,
    required String noteType,
    String content = '',
    List<String> checklistItems = const [],
    List<StickyNoteChecklistDraft>? checklistEntries,
    DateTime? expiresAt,
  }) async {
    if (noteType != 'text' && noteType != 'checklist') {
      throw ArgumentError('纸条类型无效');
    }
    final body = content.trim();
    final cleaned =
        (checklistEntries ??
                checklistItems.map(
                  (item) => StickyNoteChecklistDraft(content: item),
                ))
            .map(
              (item) => StickyNoteChecklistDraft(
                content: item.content.trim(),
                checked: item.checked,
              ),
            )
            .where((item) => item.content.isNotEmpty)
            .toList();
    if (noteType == 'text' && body.isEmpty) throw ArgumentError('请填写纸条内容');
    if (noteType == 'checklist' && cleaned.isEmpty) {
      throw ArgumentError('请至少填写一项清单');
    }
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        _notesTable,
        where: 'id = ?',
        whereArgs: [noteId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('纸条已不存在');
      await txn.update(
        _notesTable,
        {
          'title': _optional(title),
          'note_type': noteType,
          'content': noteType == 'text' ? body : '',
          'expires_at': expiresAt?.toUtc().toIso8601String(),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [noteId],
      );
      await txn.delete(_itemsTable, where: 'note_id = ?', whereArgs: [noteId]);
      if (noteType == 'checklist') {
        for (var index = 0; index < cleaned.length; index++) {
          await txn.insert(_itemsTable, {
            'item_id': _id('i'),
            'note_id': noteId,
            'content': cleaned[index].content,
            'position': index,
            'checked': cleaned[index].checked ? 1 : 0,
            'checked_at': cleaned[index].checked ? now : null,
            'created_at': now,
            'updated_at': now,
          });
        }
        final allChecked = cleaned.every((item) => item.checked);
        await txn.update(
          _notesTable,
          allChecked
              ? {
                  'completion_state': 'completed',
                  'completion_reason': 'completed',
                  'completed_at': now,
                  'status': 'active',
                  'is_displayed': 0,
                }
              : {
                  'completion_state': 'open',
                  'completion_reason': null,
                  'completed_at': null,
                  'status': 'active',
                },
          where: 'id = ?',
          whereArgs: [noteId],
        );
      }
    });
    return (await loadDetail(noteId))!;
  }

  @override
  Future<StickyNoteDetail?> loadDetail(String noteId) async {
    await completeExpired();
    final db = await _database.open();
    final notes = await db.query(
      _notesTable,
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (notes.isEmpty) return null;
    final items = await db.query(
      _itemsTable,
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'position ASC',
    );
    return StickyNoteDetail(
      note: StickyNoteItem.fromJson(notes.single),
      items: items
          .map(StickyNoteChecklistItem.fromJson)
          .toList(growable: false),
    );
  }

  @override
  Future<StickyNoteItem?> load(String noteId) async =>
      (await loadDetail(noteId))?.note;

  @override
  Future<StickyNoteDetail> setChecklistItemChecked(
    String itemId,
    bool checked,
  ) async {
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    late String noteId;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _itemsTable,
        where: 'item_id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('清单项已不存在');
      noteId = rows.single['note_id']! as String;
      await txn.update(
        _itemsTable,
        {
          'checked': checked ? 1 : 0,
          'checked_at': checked ? now : null,
          'updated_at': now,
        },
        where: 'item_id = ?',
        whereArgs: [itemId],
      );
      final remaining =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM $_itemsTable WHERE note_id = ? AND checked = 0',
              [noteId],
            ),
          ) ??
          0;
      await txn.update(
        _notesTable,
        remaining == 0
            ? {
                'completion_state': 'completed',
                'completion_reason': 'completed',
                'completed_at': now,
                'is_displayed': 0,
                'updated_at': now,
              }
            : {
                'completion_state': 'open',
                'completion_reason': null,
                'completed_at': null,
                'status': 'active',
                'updated_at': now,
              },
        where: 'id = ?',
        whereArgs: [noteId],
      );
    });
    return (await loadDetail(noteId))!;
  }

  @override
  Future<bool> setCompletion(String noteId, String reason) async {
    if (!const {'completed', 'cancelled', 'expired'}.contains(reason)) {
      throw ArgumentError('完成原因无效');
    }
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    return await db.update(
          _notesTable,
          {
            'completion_state': 'completed',
            'completion_reason': reason,
            'completed_at': now,
            'status': reason == 'expired' ? 'expired' : 'active',
            'is_displayed': 0,
            'updated_at': now,
          },
          where: "id = ? AND completion_state = 'open'",
          whereArgs: [noteId],
        ) >
        0;
  }

  @override
  Future<bool> restore(String noteId) async {
    final db = await _database.open();
    return await db.update(
          _notesTable,
          {
            'completion_state': 'open',
            'completion_reason': null,
            'completed_at': null,
            'status': 'active',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: "id = ? AND completion_state = 'completed'",
          whereArgs: [noteId],
        ) >
        0;
  }

  @override
  Future<bool> setPinned(String noteId, bool pinned) async {
    final db = await _database.open();
    return await db.update(
          _notesTable,
          {
            'pinned': pinned ? 1 : 0,
            'wall_order': await _nextOrder(db, pinned: pinned),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [noteId],
        ) >
        0;
  }

  @override
  Future<void> reorderGroup(
    List<String> noteIds, {
    required bool pinned,
  }) async {
    if (noteIds.isEmpty) return;
    final db = await _database.open();
    await db.transaction((txn) async {
      for (var index = 0; index < noteIds.length; index++) {
        await txn.update(
          _notesTable,
          {'wall_order': index},
          where: 'id = ? AND pinned = ? AND completion_state = \'open\'',
          whereArgs: [noteIds[index], pinned ? 1 : 0],
        );
      }
    });
  }

  @override
  Future<bool> setDisplayed(String noteId) async {
    final db = await _database.open();
    return db.transaction((txn) async {
      final target = await txn.query(
        _notesTable,
        columns: ['id'],
        where: "id = ? AND completion_state = 'open'",
        whereArgs: [noteId],
        limit: 1,
      );
      if (target.isEmpty) return false;
      await txn.update(_notesTable, {
        'is_displayed': 0,
      }, where: 'is_displayed = 1');
      return await txn.update(
            _notesTable,
            {'is_displayed': 1},
            where: 'id = ?',
            whereArgs: [noteId],
          ) >
          0;
    });
  }

  @override
  Future<bool> clearDisplayed(String noteId) async {
    final db = await _database.open();
    return await db.update(
          _notesTable,
          {'is_displayed': 0},
          where: 'id = ? AND is_displayed = 1',
          whereArgs: [noteId],
        ) >
        0;
  }

  @override
  Future<bool> hardDelete(String noteId) async {
    final db = await _database.open();
    return await db.delete(_notesTable, where: 'id = ?', whereArgs: [noteId]) >
        0;
  }

  @override
  Future<bool> tear(String noteId) => hardDelete(noteId);

  @override
  Future<int> completeExpired({DateTime? now}) async {
    final db = await _database.open();
    final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    return db.update(
      _notesTable,
      {
        'completion_state': 'completed',
        'completion_reason': 'expired',
        'completed_at': timestamp,
        'status': 'expired',
        'is_displayed': 0,
        'updated_at': timestamp,
      },
      where:
          "completion_state = 'open' AND expires_at IS NOT NULL AND expires_at <= ?",
      whereArgs: [timestamp],
    );
  }

  @override
  Future<List<StickyNoteItem>> listOpen({DateTime? now}) async {
    await completeExpired(now: now);
    final db = await _database.open();
    final rows = await db.query(
      _notesTable,
      where: "completion_state = 'open' AND status = 'active'",
      orderBy: 'pinned DESC, wall_order ASC, updated_at DESC',
    );
    return rows.map(StickyNoteItem.fromJson).toList(growable: false);
  }

  @override
  Future<List<StickyNoteItem>> listHistory({bool completedOnly = false}) async {
    final db = await _database.open();
    final where = completedOnly
        ? "completion_state = 'completed'"
        : "status IN ('active', 'completed', 'expired')";
    final rows = await db.query(
      _notesTable,
      where: where,
      orderBy: 'updated_at DESC',
    );
    return rows.map(StickyNoteItem.fromJson).toList(growable: false);
  }

  @override
  Future<List<StickyNoteItem>> search({
    String? keyword,
    String? noteId,
    bool includeCompleted = false,
    int limit = 5,
  }) async {
    final db = await _database.open();
    final clauses = <String>['status != ?'];
    final args = <Object?>['deleted'];
    if (!includeCompleted) clauses.add("completion_state = 'open'");
    if (noteId != null) {
      clauses.add('id = ?');
      args.add(noteId);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      clauses.add('(content LIKE ? OR title LIKE ?)');
      final pattern = '%${keyword.trim()}%';
      args.addAll([pattern, pattern]);
    }
    final rows = await db.query(
      _notesTable,
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(StickyNoteItem.fromJson).toList(growable: false);
  }

  @override
  Future<List<StickyNoteItem>> listActive() => listOpen();

  @override
  Future<List<StickyNoteItem>> listByAssistant(String assistantId) async {
    final db = await _database.open();
    final rows = await db.query(
      _notesTable,
      where: "status = 'active' AND author_assistant_id = ?",
      whereArgs: [assistantId],
      orderBy: 'created_at DESC',
    );
    return rows.map(StickyNoteItem.fromJson).toList(growable: false);
  }

  @override
  Future<StickyNoteItem?> findBySource(
    String sourceType,
    String sourceId, {
    DateTime? now,
  }) async {
    await completeExpired(now: now);
    final db = await _database.open();
    final rows = await db.query(
      _notesTable,
      where: 'source_type = ? AND source_id = ? AND status != ?',
      whereArgs: [sourceType, sourceId, 'deleted'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : StickyNoteItem.fromJson(rows.single);
  }

  @override
  Future<List<StickyNoteItem>> listBySourceType(String sourceType) async {
    final db = await _database.open();
    final rows = await db.query(
      _notesTable,
      where: 'source_type = ? AND status != ?',
      whereArgs: [sourceType, 'deleted'],
      orderBy: 'created_at DESC',
    );
    return rows.map(StickyNoteItem.fromJson).toList(growable: false);
  }

  @override
  Future<int> countActive() async {
    await completeExpired();
    final db = await _database.open();
    return Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM $_notesTable WHERE status = 'active' AND completion_state = 'open'",
          ),
        ) ??
        0;
  }

  Future<int> _nextOrder(DatabaseExecutor db, {required bool pinned}) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(wall_order), -1) + 1 AS next_order FROM $_notesTable WHERE pinned = ?',
      [pinned ? 1 : 0],
    );
    return (rows.single['next_order'] as num?)?.toInt() ?? 0;
  }

  String? _optional(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  void _validateAuthor(String authorType, String? assistantId) {
    if (authorType != 'user' && authorType != 'assistant') {
      throw ArgumentError('作者类型无效');
    }
    if (authorType == 'assistant' && assistantId == null) {
      throw ArgumentError('助手作者必须提供助手 ID');
    }
    if (authorType == 'user' && assistantId != null) {
      throw ArgumentError('用户作者不能带助手 ID');
    }
  }
}
