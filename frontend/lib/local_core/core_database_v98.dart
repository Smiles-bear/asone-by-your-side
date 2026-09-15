part of 'core_database.dart';

Future<void> _migrateCoreDatabaseToVersion98(
  CoreDatabase owner,
  Database database,
) async {
  if (!await owner._tableExists(database, 'conversations')) return;
  if (!await owner._columnExists(
    database,
    'conversations',
    'chat_background_mode',
  )) {
    await database.execute('''
      ALTER TABLE conversations
      ADD COLUMN chat_background_mode TEXT NOT NULL DEFAULT 'inherit'
        CHECK (chat_background_mode IN ('inherit', 'default', 'custom'))
    ''');
  }
  await database.rawUpdate('''
    UPDATE conversations
    SET chat_background_mode = CASE
      WHEN TRIM(COALESCE(chat_background_path, '')) <> '' THEN 'custom'
      ELSE 'inherit'
    END
  ''');
}
