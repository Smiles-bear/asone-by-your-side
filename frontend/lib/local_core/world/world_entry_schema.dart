import 'package:sqflite/sqflite.dart';

Future<void> createWorldEntrySchema(DatabaseExecutor database) async {
  final columns = await database.rawQuery(
    'PRAGMA table_info(assistant_worlds)',
  );
  if (!columns.any((row) => row['name'] == 'entries_version')) {
    await database.execute(
      'ALTER TABLE assistant_worlds ADD COLUMN entries_version INTEGER NOT NULL DEFAULT 0',
    );
  }
  await database.execute('''
    CREATE TABLE IF NOT EXISTS world_entries (
      entry_id TEXT PRIMARY KEY,
      assistant_id TEXT NOT NULL REFERENCES assistants(id) ON DELETE CASCADE,
      category TEXT NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
      usage_mode TEXT NOT NULL CHECK (usage_mode IN ('always','relevant')),
      keywords_json TEXT NOT NULL DEFAULT '[]',
      source_material_id TEXT REFERENCES world_source_materials(material_id) ON DELETE SET NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_world_entries_category '
    'ON world_entries(assistant_id, category, created_at, entry_id)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_world_entries_enabled '
    'ON world_entries(assistant_id, enabled, usage_mode)',
  );
}
