part of 'core_database.dart';

Future<void> _migrateCoreDatabaseToVersion93(
  CoreDatabase owner,
  Database database,
) async {
  await owner._createWorldOversizedSourceRecoverySchema(database);
  if (!await owner._tableExists(database, 'assistant_worlds') ||
      !await owner._tableExists(database, 'assistants')) {
    return;
  }

  // Android CursorWindow 无法返回单行超大文本。先在 SQLite 内部保留一份
  // 尚未文件化的原文，再把常用表缩为安全预览；整个过程不把大字段读进
  // CursorWindow，覆盖升级不会丢失用户材料。
  await database.execute('''
    INSERT OR REPLACE INTO world_oversized_source_recovery (
      assistant_id, source_text, created_at
    )
    SELECT w.assistant_id, w.visible_world_setting,
           strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    FROM assistant_worlds w
    WHERE length(w.visible_world_setting) > 65536
      AND NOT EXISTS (
        SELECT 1 FROM world_source_materials m
        WHERE m.assistant_id = w.assistant_id AND m.is_active = 1
      )
  ''');
  await database.execute('''
    UPDATE assistant_worlds
    SET visible_world_setting = substr(visible_world_setting, 1, 16384),
        updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    WHERE length(visible_world_setting) > 65536
  ''');
}

Future<void> _migrateCoreDatabaseToVersion94(
  CoreDatabase owner,
  Database database,
) => owner._createWorldOrganizationDraftSchema(database);

Future<void> _migrateCoreDatabaseToVersion95(
  CoreDatabase owner,
  Database database,
) async {
  await owner._createWorldSchema(database);
  if (!await owner._columnExists(
    database,
    'assistant_worlds',
    'world_enabled',
  )) {
    await database.execute('''
      ALTER TABLE assistant_worlds
      ADD COLUMN world_enabled INTEGER NOT NULL DEFAULT 0
        CHECK (world_enabled IN (0, 1))
    ''');
  }
  if (!await owner._columnExists(
    database,
    'assistant_worlds',
    'publication_status',
  )) {
    await database.execute('''
      ALTER TABLE assistant_worlds
      ADD COLUMN publication_status TEXT NOT NULL DEFAULT 'empty'
        CHECK (publication_status IN ('empty', 'published', 'needs_review'))
    ''');
  }
  if (!await owner._columnExists(
    database,
    'world_source_materials',
    'workspace_status',
  )) {
    await database.execute('''
      ALTER TABLE world_source_materials
      ADD COLUMN workspace_status TEXT NOT NULL DEFAULT 'staged'
        CHECK (workspace_status IN (
          'staged', 'organizing', 'interrupted', 'review_ready', 'applied'
        ))
    ''');
  }
  if (!await owner._columnExists(
    database,
    'world_source_materials',
    'last_job_id',
  )) {
    await database.execute('''
      ALTER TABLE world_source_materials
      ADD COLUMN last_job_id TEXT NOT NULL DEFAULT ''
    ''');
  }
  if (!await owner._columnExists(database, 'world_schedules', 'context_mode')) {
    await database.execute('''
      ALTER TABLE world_schedules
      ADD COLUMN context_mode TEXT NOT NULL DEFAULT 'auto'
        CHECK (context_mode IN ('auto', 'topic', 'always'))
    ''');
  }

  await database.execute('''
    UPDATE assistant_worlds
    SET publication_status = 'published', world_enabled = 1
    WHERE TRIM(visible_world_setting) <> ''
       OR TRIM(world_core) <> ''
       OR TRIM(world_rules) <> ''
       OR EXISTS (
         SELECT 1 FROM world_characters c
         WHERE c.assistant_id = assistant_worlds.assistant_id
       )
       OR EXISTS (
         SELECT 1 FROM world_spaces s
         WHERE s.assistant_id = assistant_worlds.assistant_id
       )
       OR EXISTS (
         SELECT 1 FROM world_schedules d
         WHERE d.assistant_id = assistant_worlds.assistant_id
       )
       OR EXISTS (
         SELECT 1 FROM world_lore_items l
         WHERE l.assistant_id = assistant_worlds.assistant_id
       )
  ''');
  await database.execute('''
    UPDATE world_source_materials
    SET workspace_status = 'applied'
    WHERE is_active = 1 AND EXISTS (
      SELECT 1 FROM assistant_worlds w
      WHERE w.assistant_id = world_source_materials.assistant_id
        AND w.organize_revision > 0
        AND w.source_hash = world_source_materials.content_hash
    )
  ''');
  if (await owner._tableExists(database, 'local_jobs')) {
    await database.execute('''
      UPDATE world_source_materials
      SET workspace_status = 'interrupted'
      WHERE is_active = 1 AND EXISTS (
        SELECT 1 FROM assistant_worlds w
        WHERE w.assistant_id = world_source_materials.assistant_id
          AND w.organize_revision = 0
          AND w.last_generation_run_id = ''
          AND w.source_hash = world_source_materials.content_hash
          AND (
            w.world_core = w.visible_world_setting
            OR w.world_core = substr(w.visible_world_setting, 1, 1200) || '……'
          )
          AND EXISTS (
            SELECT 1 FROM local_jobs j
            WHERE j.task_type = 'world_task'
              AND j.scope_type = 'assistant'
              AND j.scope_id = w.assistant_id
              AND j.status IN ('failed', 'cancelled')
              AND j.payload LIKE '%"kind":"organize"%'
          )
      )
    ''');
    await database.execute('''
      UPDATE assistant_worlds
      SET publication_status = 'needs_review', world_enabled = 0
      WHERE EXISTS (
        SELECT 1 FROM world_source_materials m
        WHERE m.assistant_id = assistant_worlds.assistant_id
          AND m.is_active = 1
          AND m.workspace_status = 'interrupted'
      )
    ''');
  }
}
