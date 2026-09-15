part of 'core_database.dart';

Future<void> _migrateCoreDatabaseToVersion99(
  CoreDatabase owner,
  Database database,
) => _createCoreDatabaseV99Schema(database);

Future<void> _createCoreDatabaseV99Schema(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS group_message_director_scripts (
      script_id TEXT PRIMARY KEY,
      assistant_id TEXT NOT NULL,
      room_id TEXT NOT NULL,
      message_id TEXT NOT NULL,
      answer_version_id TEXT,
      answer_scope_id TEXT NOT NULL,
      segment_index INTEGER NOT NULL DEFAULT 0,
      script TEXT,
      status TEXT NOT NULL DEFAULT 'none'
        CHECK (status IN ('none', 'pending', 'done', 'failed')),
      revision INTEGER NOT NULL DEFAULT 0,
      mode TEXT NOT NULL DEFAULT 'normal',
      source_text_hash TEXT NOT NULL DEFAULT '',
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (message_id, answer_scope_id, segment_index),
      FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
      FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE,
      FOREIGN KEY (message_id) REFERENCES group_messages(message_id)
        ON DELETE CASCADE,
      FOREIGN KEY (answer_version_id)
        REFERENCES group_answer_versions(answer_version_id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE INDEX IF NOT EXISTS idx_group_director_scripts_current
    ON group_message_director_scripts(
      message_id, answer_scope_id, segment_index, status
    )
  ''');
}
