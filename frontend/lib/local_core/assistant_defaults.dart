import 'package:sqflite/sqflite.dart';

typedef AssistantDefaultsCleanup = Future<void> Function(
  DatabaseExecutor database,
  String assistantId,
);

/// New assistants opt in; assistants without this policy retain legacy defaults.
class AssistantDefaults {
  static Future<void> insert(
    DatabaseExecutor db,
    Map<String, Object?> values,
  ) async {
    await db.insert('assistants', {
      'memory_auto_organize_enabled': 0,
      'timestamps_enabled': 0,
      ...values,
    });
    await initialize(db, values['id']! as String);
  }

  static Future<void> discardPending(DatabaseExecutor db, String id) async {
    final deleted = await db.delete(
      'assistants',
      where: 'id = ? AND import_pending = 1',
      whereArgs: [id],
    );
    if (deleted > 0) await remove(db, id);
  }

  static String key(String id) => 'assistant_tool_default:$id';

  static Future<void> initialize(DatabaseExecutor db, String id) async {
    await db.insert('app_metadata', {
      'key': key(id),
      'value': 'off',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<bool> toolDefault(
    DatabaseExecutor db,
    String id,
    bool legacyDefault,
  ) async {
    if (!legacyDefault) return false;
    final rows = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key(id)],
    );
    return rows.isEmpty || rows.single['value'] != 'off';
  }

  static Future<void> remove(
    DatabaseExecutor db,
    String id, {
    AssistantDefaultsCleanup? cleanup,
  }) async {
    await cleanup?.call(db, id);
    await db.delete('app_metadata', where: 'key = ?', whereArgs: [key(id)]);
  }
}
