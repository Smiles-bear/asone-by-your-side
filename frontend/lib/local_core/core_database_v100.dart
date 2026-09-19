part of 'core_database.dart';

Future<void> _migrateCoreDatabaseToVersion100(
  CoreDatabase owner,
  Database database,
) async {
  final tables = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'conversations'",
  );
  if (tables.isEmpty) return;
  final columns = await database.rawQuery('PRAGMA table_info(conversations)');
  if (!columns.any((row) => row['name'] == 'pinned_at')) {
    await database.execute(
      'ALTER TABLE conversations ADD COLUMN pinned_at TEXT',
    );
  }
}
