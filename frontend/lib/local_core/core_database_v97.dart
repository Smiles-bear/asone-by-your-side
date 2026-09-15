part of 'core_database.dart';

Future<void> _migrateCoreDatabaseToVersion97(
  CoreDatabase owner,
  Database database,
) async {
  if (!await owner._tableExists(database, 'message_voice_assets')) return;
  if (!await owner._columnExists(
    database,
    'message_voice_assets',
    'generation_key',
  )) {
    await database.execute('''
      ALTER TABLE message_voice_assets
      ADD COLUMN generation_key TEXT NOT NULL DEFAULT ''
    ''');
  }
  await database.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_voice_assets_active_generation
    ON message_voice_assets(generation_key)
    WHERE generation_key <> '' AND state IN ('generating', 'ready')
  ''');
}
