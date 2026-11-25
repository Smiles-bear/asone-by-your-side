import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../features/world/world_entries.dart';
import '../core_database.dart';
import 'world_entry_schema.dart';

class WorldEntryStore {
  WorldEntryStore({CoreDatabase? coreDatabase})
    : database = coreDatabase ?? CoreDatabase.instance;
  final CoreDatabase database;
  Database? _ready;
  Future<Database>? _preparing;
  Future<Database> _open() async {
    final db = await database.open();
    if (identical(db, _ready)) return db;
    if (_preparing != null) return _preparing!;
    final future = () async {
      await db.transaction((tx) async {
        await createWorldEntrySchema(tx);
        await tx.execute(
          '''CREATE TABLE IF NOT EXISTS community_world_materials (
          material_id TEXT PRIMARY KEY,
          assistant_id TEXT NOT NULL REFERENCES assistants(id) ON DELETE CASCADE,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL
        )''',
        );
      });
      _ready = db;
      return db;
    }();
    _preparing = future;
    try {
      return await future;
    } finally {
      _preparing = null;
    }
  }

  Future<void> saveReviewed(
    String assistantId,
    String source,
    List<WorldEntryDraft> entries,
  ) async {
    for (final entry in entries) {
      entry.validate();
    }
    await (await _open()).transaction((tx) async {
      await ensureWorld(tx, assistantId);
      await tx.insert('community_world_materials', {
        'material_id': _id(),
        'assistant_id': assistantId,
        'content': source,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      for (final entry in entries) {
        final values = _values(entry);
        await tx.insert('world_entries', {
          ...values,
          'entry_id': _id(),
          'assistant_id': assistantId,
          'created_at': values['updated_at'],
        });
      }
    });
  }

  Future<List<String>> sourceMaterials(String assistantId) async =>
      (await (await _open()).query(
        'community_world_materials',
        columns: ['content'],
        where: 'assistant_id = ?',
        whereArgs: [assistantId],
        orderBy: 'created_at, material_id',
      )).map((row) => row['content']! as String).toList(growable: false);

  Future<void> prepare() async {
    await _open();
  }

  final _random = Random.secure();
  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${_random.nextInt(0xffffffff).toRadixString(16)}';

  static WorldEntry fromRow(Map<String, Object?> row) => WorldEntry(
    id: row['entry_id']! as String,
    assistantId: row['assistant_id']! as String,
    category: row['category']! as String,
    title: row['title']! as String,
    content: row['content'] as String? ?? '',
    enabled: row['enabled'] == 1,
    usageMode: row['usage_mode'] == 'always'
        ? WorldUsageMode.always
        : WorldUsageMode.relevant,
    keywords: (jsonDecode(row['keywords_json'] as String? ?? '[]') as List)
        .whereType<String>()
        .toList(),
    sourceMaterialId: row['source_material_id'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  Future<List<WorldEntryCategory>> categories(String assistantId) async {
    final rows = await (await _open()).rawQuery(
      'SELECT category, COUNT(*) AS total, SUM(enabled) AS enabled FROM world_entries '
      'WHERE assistant_id = ? GROUP BY category ORDER BY MIN(created_at), category',
      [assistantId],
    );
    return rows
        .map(
          (r) => WorldEntryCategory(
            r['category']! as String,
            r['total']! as int,
            enabledCount: r['enabled']! as int,
          ),
        )
        .toList();
  }

  Future<List<WorldEntry>> list(
    String assistantId,
    String category, {
    int offset = 0,
    int limit = 40,
  }) async {
    final rows = await (await _open()).query(
      'world_entries',
      columns: [
        'entry_id',
        'assistant_id',
        'category',
        'title',
        'enabled',
        'usage_mode',
        'keywords_json',
        'source_material_id',
        'created_at',
        'updated_at',
      ],
      where: 'assistant_id = ? AND category = ?',
      whereArgs: [assistantId, category],
      orderBy: 'created_at, entry_id',
      offset: offset,
      limit: limit.clamp(1, 100),
    );
    return rows.map(fromRow).toList();
  }

  Future<WorldEntry?> get(String assistantId, String entryId) async {
    final rows = await (await _open()).query(
      'world_entries',
      where: 'assistant_id = ? AND entry_id = ?',
      whereArgs: [assistantId, entryId],
      limit: 1,
    );
    return rows.isEmpty ? null : fromRow(rows.single);
  }

  Future<void> ensureWorld(DatabaseExecutor db, String assistantId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('assistant_worlds', {
      'assistant_id': assistantId,
      'entries_version': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Map<String, Object?> _values(WorldEntryDraft value) => {
    'category': value.category.trim().isEmpty ? '其他资料' : value.category.trim(),
    'title': value.title.trim(),
    'content': value.content.trim(),
    'enabled': value.enabled ? 1 : 0,
    'usage_mode': value.usageMode.name,
    'keywords_json': jsonEncode(value.keywords.map((k) => k.trim()).toList()),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  Future<void> save(
    String assistantId,
    WorldEntryDraft value, {
    String? entryId,
  }) async {
    value.validate();
    await (await _open()).transaction((tx) async {
      await ensureWorld(tx, assistantId);
      final values = _values(value);
      if (entryId == null) {
        await tx.insert('world_entries', {
          ...values,
          'entry_id': _id(),
          'assistant_id': assistantId,
          'created_at': values['updated_at'],
        });
      } else {
        final count = await tx.update(
          'world_entries',
          values,
          where: 'assistant_id = ? AND entry_id = ?',
          whereArgs: [assistantId, entryId],
        );
        if (count != 1) throw StateError('world_entry_missing');
      }
    });
  }

  Future<void> setEnabled(
    String assistantId,
    String entryId,
    bool enabled,
  ) async {
    final count = await (await _open()).update(
      'world_entries',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'assistant_id = ? AND entry_id = ?',
      whereArgs: [assistantId, entryId],
    );
    if (count != 1) throw StateError('world_entry_missing');
  }

  Future<void> setAllEnabled(String assistantId, bool enabled) async {
    final value = enabled ? 1 : 0;
    await (await _open()).update(
      'world_entries',
      {
        'enabled': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'assistant_id = ? AND enabled <> ?',
      whereArgs: [assistantId, value],
    );
  }

  Future<void> delete(String assistantId, String entryId) async {
    await (await _open()).delete(
      'world_entries',
      where: 'assistant_id = ? AND entry_id = ?',
      whereArgs: [assistantId, entryId],
    );
  }
}
