part of 'core_database.dart';

Future<void> _migrateCoreDatabaseToVersion96(
  CoreDatabase owner,
  Database database,
) async {
  if (await owner._tableExists(database, 'conversations') &&
      !await owner._columnExists(
        database,
        'conversations',
        'chat_background_path',
      )) {
    await database.execute('''
      ALTER TABLE conversations
      ADD COLUMN chat_background_path TEXT NOT NULL DEFAULT ''
    ''');
  }
}
