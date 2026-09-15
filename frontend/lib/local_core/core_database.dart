import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_backup_service.dart';
import 'database_open_gate.dart';

part 'core_database_v95.dart';
part 'core_database_v96.dart';
part 'core_database_v97.dart';
part 'core_database_v98.dart';
part 'core_database_v99.dart';

typedef AppSupportDirectoryProvider = Future<Directory> Function();

/// 手机唯一正式数据权威源。
class CoreDatabase {
  CoreDatabase._({
    DatabaseFactory? factory,
    AppSupportDirectoryProvider? supportDirectoryProvider,
  }) : _databaseFactory = factory,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  static final CoreDatabase instance = CoreDatabase._();

  factory CoreDatabase.forTesting({
    required DatabaseFactory databaseFactory,
    required AppSupportDirectoryProvider supportDirectoryProvider,
  }) => CoreDatabase._(
    factory: databaseFactory,
    supportDirectoryProvider: supportDirectoryProvider,
  );

  static const schemaVersion = 99;
  static const databaseFileName = 'asone.db';

  final DatabaseFactory? _databaseFactory;
  final AppSupportDirectoryProvider _supportDirectoryProvider;
  Database? _database;
  Future<Database>? _opening;

  Future<String> get databasePath async {
    final root = await _supportDirectoryProvider();
    final dataDirectory = Directory(
      '${root.path}${Platform.pathSeparator}data',
    );
    await dataDirectory.create(recursive: true);
    return '${dataDirectory.path}${Platform.pathSeparator}$databaseFileName';
  }

  Future<Directory> get filesDirectory async {
    final root = await _supportDirectoryProvider();
    final directory = Directory('${root.path}${Platform.pathSeparator}files');
    await directory.create(recursive: true);
    return directory;
  }

  Future<Database> open() async {
    if (_database case final openDatabase? when openDatabase.isOpen) {
      return openDatabase;
    }
    if (_opening case final opening?) return opening;
    final opening = _openOnce();
    _opening = opening;
    try {
      return await opening;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _openOnce() async {
    final path = await databasePath;
    final factory = _databaseFactory ?? databaseFactory;
    return DatabaseOpenGate(lockFile: File('$path.open.lock')).protect(
      () async {
        await DatabaseBackupService(
          databaseFactory: factory,
        ).createBeforeUpgrade(sourcePath: path, targetVersion: schemaVersion);
        _database = await factory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: schemaVersion,
            onConfigure: (database) async {
              await database.execute('PRAGMA foreign_keys = ON');
              // Android 原生 sqflite 在 onConfigure 阶段不允许 execute 执行带返回值的
              // PRAGMA（报 "Queries can be performed ... rawQuery methods only"），
              // 必须用 rawQuery；失败不致命（WAL 仅为可选优化），忽略即可。
              try {
                await database.rawQuery('PRAGMA journal_mode = WAL');
              } catch (_) {
                // ignore: WAL 不可用时回退默认 journal 模式，功能不受影响
              }
            },
            onCreate: (database, version) async {
              await _createSchema(database);
              for (
                var appliedVersion = 1;
                appliedVersion <= schemaVersion;
                appliedVersion++
              ) {
                await database.insert('schema_migrations', {
                  'version': appliedVersion,
                  'applied_at': DateTime.now().toUtc().toIso8601String(),
                });
              }
            },
            onUpgrade: (database, oldVersion, newVersion) async {
              await _upgradeSchema(database, oldVersion, newVersion);
            },
          ),
        );
        return _database!;
      },
    );
  }

  Future<void> close() async {
    if (_opening case final opening?) await opening;
    final database = _database;
    _database = null;
    if (database != null && database.isOpen) await database.close();
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    // 后续迁移逐版本追加。必须先备份，且不得在一个迁移里重写全部消息。
    if (oldVersion < 1) await _createSchema(database);
    if (oldVersion < 2) {
      await database.execute('''
        CREATE TABLE IF NOT EXISTS app_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) await _migrateToVersion3(database);
    if (oldVersion < 4) await _migrateToVersion4(database);
    if (oldVersion < 5) await _migrateToVersion5(database);
    if (oldVersion < 6) await _migrateToVersion6(database);
    if (oldVersion < 7) await _migrateToVersion7(database);
    if (oldVersion < 8) await _migrateToVersion8(database);
    if (oldVersion < 9) await _migrateToVersion9(database);
    if (oldVersion < 10) await _migrateToVersion10(database);
    if (oldVersion < 11) await _migrateToVersion11(database);
    if (oldVersion < 12) await _migrateToVersion12(database);
    if (oldVersion < 13) await _migrateToVersion13(database);
    if (oldVersion < 14) await _migrateToVersion14(database);
    if (oldVersion < 15) await _migrateToVersion15(database);
    if (oldVersion < 16) await _migrateToVersion16(database);
    if (oldVersion < 17) await _migrateToVersion17(database);
    if (oldVersion < 18) await _migrateToVersion18(database);
    if (oldVersion < 19) await _migrateToVersion19(database);
    if (oldVersion < 20) await _migrateToVersion20(database);
    if (oldVersion < 21) await _migrateToVersion21(database);
    if (oldVersion < 22) await _migrateToVersion22(database);
    if (oldVersion < 23) await _migrateToVersion23(database);
    if (oldVersion < 24) await _migrateToVersion24(database);
    if (oldVersion < 25) await _migrateToVersion25(database);
    if (oldVersion < 26) await _migrateToVersion26(database);
    if (oldVersion < 27) await _migrateToVersion27(database);
    if (oldVersion < 28) await _migrateToVersion28(database);
    if (oldVersion < 29) await _migrateToVersion29(database);
    if (oldVersion < 30) await _migrateToVersion30(database);
    if (oldVersion < 31) await _migrateToVersion31(database);
    if (oldVersion < 32) await _migrateToVersion32(database);
    if (oldVersion < 33) await _migrateToVersion33(database);
    if (oldVersion < 34) await _migrateToVersion34(database);
    if (oldVersion < 35) await _migrateToVersion35(database);
    if (oldVersion < 36) await _migrateToVersion36(database);
    if (oldVersion < 37) await _migrateToVersion37(database);
    if (oldVersion < 38) await _migrateToVersion38(database);
    if (oldVersion < 39) await _migrateToVersion39(database);
    if (oldVersion < 40) await _migrateToVersion40(database);
    if (oldVersion < 41) await _migrateToVersion41(database);
    if (oldVersion < 42) await _migrateToVersion42(database);
    if (oldVersion < 43) await _migrateToVersion43(database);
    if (oldVersion < 44) await _migrateToVersion44(database);
    if (oldVersion < 45) await _migrateToVersion45(database);
    if (oldVersion < 46) await _migrateToVersion46(database);
    if (oldVersion < 47) await _migrateToVersion47(database);
    if (oldVersion < 48) await _migrateToVersion48(database);
    if (oldVersion < 49) await _migrateToVersion49(database);
    if (oldVersion < 50) await _migrateToVersion50(database);
    if (oldVersion < 51) await _migrateToVersion51(database);
    if (oldVersion < 52) await _migrateToVersion52(database);
    if (oldVersion < 53) await _migrateToVersion53(database);
    if (oldVersion < 54) await _migrateToVersion54(database);
    if (oldVersion < 55) await _migrateToVersion55(database);
    if (oldVersion < 56) await _migrateToVersion56(database);
    if (oldVersion < 57) await _migrateToVersion57(database);
    if (oldVersion < 58) await _migrateToVersion58(database);
    if (oldVersion < 59) await _migrateToVersion59(database);
    if (oldVersion < 60) await _migrateToVersion60(database);
    if (oldVersion < 61) await _migrateToVersion61(database);
    if (oldVersion < 62) await _migrateToVersion62(database);
    if (oldVersion < 63) await _migrateToVersion63(database);
    if (oldVersion < 64) await _migrateToVersion64(database);
    if (oldVersion < 65) await _migrateToVersion65(database);
    if (oldVersion < 66) await _migrateToVersion66(database);
    if (oldVersion < 67) await _migrateToVersion67(database);
    if (oldVersion < 68) await _migrateToVersion68(database);
    if (oldVersion < 69) await _migrateToVersion69(database);
    if (oldVersion < 70) await _migrateToVersion70(database);
    if (oldVersion < 71) await _migrateToVersion71(database);
    if (oldVersion < 72) await _migrateToVersion72(database);
    if (oldVersion < 73) await _migrateToVersion73(database);
    if (oldVersion < 74) await _migrateToVersion74(database);
    if (oldVersion < 75) await _migrateToVersion75(database);
    if (oldVersion < 76) await _migrateToVersion76(database);
    if (oldVersion < 77) await _migrateToVersion77(database);
    if (oldVersion < 78) await _migrateToVersion78(database);
    if (oldVersion < 79) await _migrateToVersion79(database);
    if (oldVersion < 80) await _migrateToVersion80(database);
    if (oldVersion < 81) await _migrateToVersion81(database);
    if (oldVersion < 82) await _migrateToVersion82(database);
    if (oldVersion < 83) await _migrateToVersion83(database);
    if (oldVersion < 84) await _migrateToVersion84(database);
    if (oldVersion < 85) await _migrateToVersion85(database);
    if (oldVersion < 86) await _migrateToVersion86(database);
    if (oldVersion < 87) await _migrateToVersion87(database);
    if (oldVersion < 88) await _migrateToVersion88(database);
    if (oldVersion < 89) await _migrateToVersion89(database);
    if (oldVersion < 90) await _migrateToVersion90(database);
    if (oldVersion < 91) await _migrateToVersion91(database);
    if (oldVersion < 92) await _migrateToVersion92(database);
    if (oldVersion < 93) await _migrateCoreDatabaseToVersion93(this, database);
    if (oldVersion < 94) await _migrateCoreDatabaseToVersion94(this, database);
    if (oldVersion < 95) await _migrateCoreDatabaseToVersion95(this, database);
    if (oldVersion < 96) await _migrateCoreDatabaseToVersion96(this, database);
    if (oldVersion < 97) await _migrateCoreDatabaseToVersion97(this, database);
    if (oldVersion < 98) await _migrateCoreDatabaseToVersion98(this, database);
    if (oldVersion < 99) await _migrateCoreDatabaseToVersion99(this, database);
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      await database.insert('schema_migrations', {
        'version': version,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _createSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE assistants (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar TEXT NOT NULL DEFAULT '',
        main_model TEXT NOT NULL DEFAULT '',
        assistant_model TEXT NOT NULL DEFAULT '',
        voice TEXT NOT NULL DEFAULT '',
        system_prompt TEXT NOT NULL DEFAULT '',
        model_service_id TEXT NOT NULL DEFAULT '',
        memory_expression_style TEXT NOT NULL DEFAULT 'natural',
        memory_expression_custom TEXT NOT NULL DEFAULT '',
        memory_auto_organize_enabled INTEGER NOT NULL DEFAULT 1,
        reply_mode TEXT NOT NULL DEFAULT 'complete',
        communication_style TEXT NOT NULL DEFAULT '',
        behavior_boundaries TEXT NOT NULL DEFAULT '',
        context_window INTEGER NOT NULL DEFAULT 100000,
        max_output_tokens INTEGER NOT NULL DEFAULT 8192,
        timestamps_enabled INTEGER NOT NULL DEFAULT 1,
        user_profile TEXT NOT NULL DEFAULT '',
        diary_writer TEXT NOT NULL DEFAULT '助手',
        diary_subject TEXT NOT NULL DEFAULT '用户',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        import_pending INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '新对话',
        assistant_id TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'single',
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        import_pending INTEGER NOT NULL DEFAULT 0,
        draft_text TEXT NOT NULL DEFAULT '',
        draft_updated_at TEXT,
        voice_reply_mode TEXT NOT NULL DEFAULT 'text'
          CHECK (voice_reply_mode IN ('text', 'voice', 'voice_text')),
        voice_auto_play INTEGER NOT NULL DEFAULT 0 CHECK (voice_auto_play IN (0, 1)),
        director_text_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (director_text_enabled IN (0, 1)),
        director_call_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (director_call_enabled IN (0, 1)),
        chat_background_path TEXT NOT NULL DEFAULT '',
        chat_background_mode TEXT NOT NULL DEFAULT 'inherit'
          CHECK (chat_background_mode IN ('inherit', 'default', 'custom')),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
        content TEXT NOT NULL,
        reasoning TEXT,
        revision INTEGER NOT NULL DEFAULT 1,
        current_message_version_id TEXT,
        current_answer_version_id TEXT,
        current_answer_version_number INTEGER,
        answer_version_count INTEGER NOT NULL DEFAULT 0,
        answer_status TEXT,
        failure_hint TEXT,
        elapsed_ms INTEGER,
        tool_used INTEGER NOT NULL DEFAULT 0 CHECK (tool_used IN (0, 1)),
        is_deleted INTEGER NOT NULL DEFAULT 0,
        visible INTEGER NOT NULL DEFAULT 1,
        context_visible INTEGER NOT NULL DEFAULT 0
          CHECK (context_visible IN (0, 1)),
        content_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        import_order INTEGER,
        import_pending_job_id TEXT,
        game_invitation_id TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE message_segments (
        message_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL,
        content TEXT NOT NULL,
        PRIMARY KEY (message_id, segment_index),
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');
    await _createConversationChangeStateSchema(database);
    await database.execute('''
      CREATE INDEX idx_message_segments_message_id
      ON message_segments(message_id, segment_index ASC)
    ''');
    await _createConversationReadStateSchema(database);
    await database.execute('''
      CREATE TABLE message_versions (
        version_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        edited_by TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        UNIQUE(message_id, version_number)
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_message_versions_message_id
      ON message_versions(message_id, version_number DESC)
    ''');
    await database.execute('''
      CREATE TABLE answer_versions (
        answer_version_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        model_service_id TEXT,
        model_name TEXT,
        prompt_tokens INTEGER,
        completion_tokens INTEGER,
        finish_reason TEXT,
        elapsed_ms INTEGER,
        reasoning TEXT,
        tool_used INTEGER NOT NULL DEFAULT 0 CHECK (tool_used IN (0, 1)),
        tts_script TEXT,
        tts_script_status TEXT NOT NULL DEFAULT 'none'
          CHECK (tts_script_status IN ('none', 'pending', 'done', 'failed')),
        tts_script_revision INTEGER NOT NULL DEFAULT 0,
        tts_script_mode TEXT,
        tts_script_source_hash TEXT,
        branch_parent_version_id TEXT,
        branch_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        UNIQUE(message_id, version_number)
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_answer_versions_message_id
      ON answer_versions(message_id, version_number DESC)
    ''');
    await database.execute('''
      CREATE INDEX idx_answer_versions_branch
      ON answer_versions(message_id, branch_active DESC, version_number DESC)
    ''');
    await _createSingleChatAnswerBranchSchema(database);
    await database.execute('''
      CREATE UNIQUE INDEX idx_answer_versions_one_active
      ON answer_versions(message_id)
      WHERE branch_active = 1
    ''');
    await database.execute('''
      CREATE TABLE local_jobs (
        job_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        stage TEXT NOT NULL,
        total_items INTEGER NOT NULL,
        processed_items INTEGER NOT NULL DEFAULT 0,
        cancel_requested INTEGER NOT NULL DEFAULT 0,
        checkpoint INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        task_type TEXT,
        payload TEXT,
        scope_type TEXT,
        scope_id TEXT,
        last_error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createImportSchema(database);
    await _createMemoryV2Schema(database);
    await _createMemorySearchIndexSchema(database);
    // 阶段 1：模型绑定表
    await database.execute('''
      CREATE TABLE assistant_model_bindings (
        assistant_id TEXT NOT NULL,
        binding_role TEXT NOT NULL,
        model_service_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, binding_role),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (model_service_id) REFERENCES model_services(id)
      )
    ''');
    await database.execute('''
      CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_conversations_updated_at
      ON conversations(updated_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX idx_messages_conversation_created_at
      ON messages(conversation_id, created_at ASC, id ASC)
    ''');
    await database.execute('''
      CREATE INDEX idx_messages_conversation_import_order
      ON messages(conversation_id, import_order ASC)
    ''');
    await database.execute('''
      CREATE INDEX idx_messages_import_pending_job
      ON messages(import_pending_job_id)
    ''');
    await database.execute('''
      CREATE INDEX idx_local_jobs_updated_at
      ON local_jobs(updated_at DESC)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX idx_conversations_one_active_single_per_assistant
      ON conversations(assistant_id)
      WHERE kind='single' AND status='active'
    ''');
    // Token 用量统计表
    await database.execute('''
      CREATE TABLE token_usage_records (
        record_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        task_type TEXT NOT NULL,
        task_subtype TEXT,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        request_count INTEGER NOT NULL DEFAULT 1,
        model_service_id TEXT,
        model TEXT,
        protocol_type TEXT,
        is_estimated INTEGER NOT NULL DEFAULT 0 CHECK (is_estimated IN (0, 1)),
        request_id TEXT,
        conversation_id TEXT,
        message_id TEXT,
        job_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_token_usage_assistant_time
      ON token_usage_records(assistant_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX idx_token_usage_task_type
      ON token_usage_records(task_type, created_at DESC)
    ''');
    await _createDeveloperToolsSchema(database);
    await _createToolSourcesSchema(database);
    await _createToolRuntimeGrantSchema(database);
    await _createToolCallRunsSchema(database);
    await _createCapabilityStatesSchema(database);
    await _createLocalGameSchema(database);
    await _createSessionToolGrantsSchema(database);
    await _createToolArtifactsSchema(database);
    await _createMemoryOrganizeQueueSchema(database);
    await _createMindBoardSchema(database);
    await database.execute('''
      CREATE TABLE feature_read_state (
        feature_key TEXT PRIMARY KEY
          CHECK (feature_key IN ('sticky_note', 'message_board', 'calendar')),
        last_read_at TEXT NOT NULL
      )
    ''');
    await _createContinuityAwarenessSchema(database);
    await _createAttentionSchema(database);
    await _createHeartbeatSettingsSchema(database);
    await _createAssistantToolEnablementSchema(database);
    await _createAssistantCapabilityConsentsSchema(database);
    await _createHeartbeatRuntimeSchema(database);
    await _createProactiveMessagesSchema(database);
    await _createModelRequestTraceSchema(database);
    await _createPatrolFactsSchema(database);
    await _createAssistantAllowedAppsSchema(database);
    await _createAssistantActionOutboxSchema(database);
    await _createAssistantAppRestrictionsSchema(database);
    await _createVoiceSchema(database);
    await _createTogetherWatchSchema(database);
    await _createTogetherListenSchema(database);
    await _createTogetherPlaySchema(database);
    await _createConfigurationHelpSchema(database);
    await _createToolAuthoringSchema(database);
    await _createMyDevicesSchema(database);
    await _createToolConfirmationSchema(database);
    await _createGroupChatSchema(database);
    await _createGroupChatExtensionSchema(database);
    await _createCoreDatabaseV99Schema(database);
    await _createWorldSchema(database);
  }

  Future<void> _migrateToVersion3(Database database) async {
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'import_pending')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN import_pending INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (await _tableExists(database, 'conversations') &&
        !await _columnExists(database, 'conversations', 'import_pending')) {
      await database.execute(
        'ALTER TABLE conversations ADD COLUMN import_pending INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'import_order')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN import_order INTEGER',
      );
    }
    await _createImportSchema(database);
    if (await _tableExists(database, 'messages')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_conversation_import_order
        ON messages(conversation_id, import_order ASC)
      ''');
    }
  }

  Future<bool> _tableExists(DatabaseExecutor database, String table) async {
    final rows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(
    DatabaseExecutor database,
    String table,
    String column,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  Future<void> _createImportSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_jobs (
        job_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        stage TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0,
        total_items INTEGER NOT NULL,
        processed_items INTEGER NOT NULL DEFAULT 0,
        stage_total_items INTEGER NOT NULL DEFAULT 0,
        stage_processed_items INTEGER NOT NULL DEFAULT 0,
        warnings TEXT NOT NULL DEFAULT '[]',
        errors TEXT NOT NULL DEFAULT '[]',
        warning_count INTEGER NOT NULL DEFAULT 0,
        error_count INTEGER NOT NULL DEFAULT 0,
        retryable INTEGER NOT NULL DEFAULT 0,
        error_code TEXT NOT NULL DEFAULT '',
        cancel_requested INTEGER NOT NULL DEFAULT 0,
        checkpoint INTEGER NOT NULL DEFAULT 0,
        target_assistant_id TEXT,
        target_conversation_id TEXT,
        target_count INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0,
        worker_token TEXT,
        lease_expires_at TEXT,
        heartbeat_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_staging_conversations (
        job_id TEXT NOT NULL,
        source_conversation_id TEXT NOT NULL,
        source_order INTEGER NOT NULL,
        title TEXT NOT NULL,
        PRIMARY KEY (job_id, source_conversation_id),
        FOREIGN KEY (job_id) REFERENCES import_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_staging_messages (
        job_id TEXT NOT NULL,
        source_conversation_id TEXT NOT NULL,
        source_message_id TEXT NOT NULL,
        source_sequence INTEGER NOT NULL,
        global_sequence INTEGER NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
        content TEXT NOT NULL,
        source_created_at TEXT,
        timestamp_status TEXT NOT NULL,
        source_fingerprint TEXT,
        fingerprint_version TEXT NOT NULL DEFAULT 'v1',
        source_identity TEXT NOT NULL DEFAULT '',
        stable_source_id INTEGER NOT NULL DEFAULT 1,
        planned_sequence INTEGER,
        source_role TEXT,
        role_status TEXT NOT NULL DEFAULT 'explicit',
        PRIMARY KEY (job_id, source_conversation_id, source_message_id),
        UNIQUE (job_id, global_sequence),
        FOREIGN KEY (job_id, source_conversation_id)
          REFERENCES import_staging_conversations(job_id, source_conversation_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_plans (
        job_id TEXT PRIMARY KEY,
        target_assistant_name TEXT NOT NULL,
        target_conversation_title TEXT NOT NULL,
        plan_json TEXT NOT NULL DEFAULT '',
        frozen_at TEXT NOT NULL,
        FOREIGN KEY (job_id) REFERENCES import_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    await _createGroupedImportPlanSchema(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_batches (
        job_id TEXT NOT NULL,
        checkpoint INTEGER NOT NULL,
        start_sequence INTEGER NOT NULL,
        end_sequence INTEGER NOT NULL,
        item_count INTEGER NOT NULL,
        committed_at TEXT NOT NULL,
        PRIMARY KEY (job_id, checkpoint),
        FOREIGN KEY (job_id) REFERENCES import_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_message_sources (
        message_id TEXT PRIMARY KEY,
        import_job_id TEXT NOT NULL,
        import_batch_id INTEGER NOT NULL,
        source_conversation_id TEXT NOT NULL,
        source_message_id TEXT NOT NULL,
        source_sequence INTEGER NOT NULL,
        source_created_at TEXT,
        timestamp_status TEXT NOT NULL,
        source_fingerprint TEXT,
        fingerprint_version TEXT NOT NULL DEFAULT 'v1',
        source_identity TEXT NOT NULL DEFAULT '',
        stable_source_id INTEGER NOT NULL DEFAULT 1,
        UNIQUE (import_job_id, source_conversation_id, source_message_id),
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (import_job_id) REFERENCES import_jobs(job_id) ON DELETE RESTRICT
      )
    ''');
    await _createParserMetadataSchema(database);
    await _createAttachmentSchema(database);
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_jobs_status_updated
      ON import_jobs(status, updated_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_jobs_lease
      ON import_jobs(status, lease_expires_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_staging_stable_order
      ON import_staging_messages(job_id, global_sequence ASC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_staging_role_status
      ON import_staging_messages(job_id, role_status, source_role)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_batches_cleanup
      ON import_batches(job_id, checkpoint ASC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_sources_job_sequence
      ON import_message_sources(
        import_job_id,
        source_conversation_id,
        source_sequence ASC
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_sources_stable_identity
      ON import_message_sources(
        source_identity,
        source_conversation_id,
        source_message_id
      )
      WHERE stable_source_id = 1
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_sources_fingerprint
      ON import_message_sources(fingerprint_version, source_fingerprint)
    ''');
  }

  Future<void> _migrateToVersion4(Database database) async {
    if (await _tableExists(database, 'import_staging_messages') &&
        !await _columnExists(
          database,
          'import_staging_messages',
          'source_role',
        )) {
      await database.execute(
        'ALTER TABLE import_staging_messages ADD COLUMN source_role TEXT',
      );
    }
    if (await _tableExists(database, 'import_staging_messages') &&
        !await _columnExists(
          database,
          'import_staging_messages',
          'role_status',
        )) {
      await database.execute(
        "ALTER TABLE import_staging_messages ADD COLUMN role_status TEXT NOT NULL DEFAULT 'explicit'",
      );
    }
    await _createParserMetadataSchema(database);
    if (await _tableExists(database, 'import_staging_messages')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_import_staging_role_status
        ON import_staging_messages(job_id, role_status, source_role)
      ''');
    }
  }

  Future<void> _migrateToVersion5(Database database) async {
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'import_pending_job_id')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN import_pending_job_id TEXT',
      );
    }
    if (await _tableExists(database, 'import_jobs') &&
        !await _columnExists(database, 'import_jobs', 'target_count')) {
      await database.execute(
        'ALTER TABLE import_jobs ADD COLUMN target_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (await _tableExists(database, 'import_plans') &&
        !await _columnExists(database, 'import_plans', 'plan_json')) {
      await database.execute(
        "ALTER TABLE import_plans ADD COLUMN plan_json TEXT NOT NULL DEFAULT ''",
      );
    }
    await _createGroupedImportPlanSchema(database);
    if (await _tableExists(database, 'messages')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_import_pending_job
        ON messages(import_pending_job_id)
      ''');
    }
  }

  Future<void> _migrateToVersion6(Database database) async {
    for (final column in const [
      ('fingerprint_version', "TEXT NOT NULL DEFAULT 'v1'"),
      ('source_identity', "TEXT NOT NULL DEFAULT ''"),
      ('stable_source_id', 'INTEGER NOT NULL DEFAULT 1'),
      ('planned_sequence', 'INTEGER'),
    ]) {
      if (await _tableExists(database, 'import_staging_messages') &&
          !await _columnExists(
            database,
            'import_staging_messages',
            column.$1,
          )) {
        await database.execute(
          'ALTER TABLE import_staging_messages ADD COLUMN ${column.$1} ${column.$2}',
        );
      }
    }
    for (final column in const [
      ('fingerprint_version', "TEXT NOT NULL DEFAULT 'v1'"),
      ('source_identity', "TEXT NOT NULL DEFAULT ''"),
      ('stable_source_id', 'INTEGER NOT NULL DEFAULT 1'),
    ]) {
      if (await _tableExists(database, 'import_message_sources') &&
          !await _columnExists(database, 'import_message_sources', column.$1)) {
        await database.execute(
          'ALTER TABLE import_message_sources ADD COLUMN ${column.$1} ${column.$2}',
        );
      }
    }
    if (await _tableExists(database, 'import_parser_metadata') &&
        !await _columnExists(
          database,
          'import_parser_metadata',
          'source_identity',
        )) {
      await database.execute(
        "ALTER TABLE import_parser_metadata ADD COLUMN source_identity TEXT NOT NULL DEFAULT ''",
      );
    }
    await _createAttachmentSchema(database);
    if (await _tableExists(database, 'import_message_sources')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_import_sources_stable_identity
        ON import_message_sources(
          source_identity,
          source_conversation_id,
          source_message_id
        )
        WHERE stable_source_id = 1
      ''');
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_import_sources_fingerprint
        ON import_message_sources(fingerprint_version, source_fingerprint)
      ''');
    }
    // 双回复模式（批1）：助手回复方式 + 消息 turn/segment 字段
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'reply_mode')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN reply_mode TEXT NOT NULL DEFAULT 'complete'",
      );
    }
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'assistant_turn_id')) {
      await database.execute(
        "ALTER TABLE messages ADD COLUMN assistant_turn_id TEXT NOT NULL DEFAULT ''",
      );
    }
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'segment_index')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN segment_index INTEGER NOT NULL DEFAULT 0',
      );
    }
    // 注入系统字段（批2）：三件套 + 用户资料 + 上下文窗口 + 最大输出 Token + 时间戳开关
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'communication_style')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN communication_style TEXT NOT NULL DEFAULT ''",
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'behavior_boundaries')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN behavior_boundaries TEXT NOT NULL DEFAULT ''",
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'context_window')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN context_window INTEGER NOT NULL DEFAULT 100000',
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'max_output_tokens')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN max_output_tokens INTEGER NOT NULL DEFAULT 8192',
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'timestamps_enabled')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN timestamps_enabled INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'user_profile')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN user_profile TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<void> _migrateToVersion7(Database database) async {
    await _createMemoryV2Schema(database);
  }

  Future<void> _migrateToVersion8(Database database) async {
    for (final column in const [
      ('warning_count', 'INTEGER NOT NULL DEFAULT 0'),
      ('error_count', 'INTEGER NOT NULL DEFAULT 0'),
      ('stage_total_items', 'INTEGER NOT NULL DEFAULT 0'),
      ('stage_processed_items', 'INTEGER NOT NULL DEFAULT 0'),
      ('retryable', 'INTEGER NOT NULL DEFAULT 0'),
      ('error_code', "TEXT NOT NULL DEFAULT ''"),
      ('worker_token', 'TEXT'),
      ('lease_expires_at', 'TEXT'),
      ('heartbeat_at', 'TEXT'),
    ]) {
      if (await _tableExists(database, 'import_jobs') &&
          !await _columnExists(database, 'import_jobs', column.$1)) {
        await database.execute(
          'ALTER TABLE import_jobs ADD COLUMN ${column.$1} ${column.$2}',
        );
      }
    }
    for (final column in const [
      ('retryable', 'INTEGER NOT NULL DEFAULT 0'),
      ('error_code', "TEXT NOT NULL DEFAULT ''"),
      ('worker_token', 'TEXT'),
      ('lease_expires_at', 'TEXT'),
      ('heartbeat_at', 'TEXT'),
    ]) {
      if (await _tableExists(database, 'memory_rebuild_jobs') &&
          !await _columnExists(database, 'memory_rebuild_jobs', column.$1)) {
        await database.execute(
          'ALTER TABLE memory_rebuild_jobs ADD COLUMN ${column.$1} ${column.$2}',
        );
      }
    }
    if (await _tableExists(database, 'import_jobs') &&
        await _columnExists(database, 'import_jobs', 'status') &&
        await _columnExists(database, 'import_jobs', 'lease_expires_at')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_import_jobs_lease
        ON import_jobs(status, lease_expires_at)
      ''');
    }
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_rebuild_jobs_lease
      ON memory_rebuild_jobs(status, lease_expires_at)
    ''');
  }

  Future<void> _migrateToVersion9(Database database) async {
    if (await _tableExists(database, 'memory_rebuild_checkpoints') &&
        !await _columnExists(
          database,
          'memory_rebuild_checkpoints',
          'checkpoint_kind',
        )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_checkpoints
        ADD COLUMN checkpoint_kind TEXT NOT NULL DEFAULT 'chunk'
      ''');
    }
    if (await _tableExists(database, 'memory_rebuild_checkpoints') &&
        !await _columnExists(
          database,
          'memory_rebuild_checkpoints',
          'request_context_json',
        )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_checkpoints
        ADD COLUMN request_context_json TEXT NOT NULL DEFAULT '{}'
      ''');
    }
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_rebuild_checkpoints_kind
      ON memory_rebuild_checkpoints(run_id, checkpoint_kind, chunk_index)
    ''');
  }

  Future<void> _migrateToVersion10(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    if (await _tableExists(database, 'model_services') &&
        !await _columnExists(database, 'model_services', 'api_key_ref')) {
      await database.execute('''
        ALTER TABLE model_services
        ADD COLUMN api_key_ref TEXT NOT NULL DEFAULT ''
      ''');
    }
    await _createCapabilityAndCoverageSchema(database);

    // 老版本可能已经产生了一个助手对应多个对话的数据。升级时先保留数据，
    // 由仓储层阻止继续新增；仅在没有冲突时建立最终的一对一数据库约束。
    final hasConversations = await _tableExists(database, 'conversations');
    final duplicates = hasConversations
        ? await database.rawQuery('''
            SELECT assistant_id
            FROM conversations
            GROUP BY assistant_id
            HAVING COUNT(*) > 1
            LIMIT 1
          ''')
        : const <Map<String, Object?>>[];
    if (hasConversations && duplicates.isEmpty) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_one_per_assistant
        ON conversations(assistant_id)
      ''');
    } else {
      await database.insert('app_metadata', {
        'key': 'conversation_one_to_one_conflict',
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _migrateToVersion11(Database database) async {
    if (await _tableExists(database, 'memory_rebuild_jobs') &&
        !await _columnExists(database, 'memory_rebuild_jobs', 'partial_kept')) {
      await database.execute('''
        ALTER TABLE memory_rebuild_jobs
        ADD COLUMN partial_kept INTEGER NOT NULL DEFAULT 0
      ''');
    }
    await _createMemoryRebuildSnapshotSchema(database);
  }

  Future<void> _migrateToVersion12(Database database) async {
    // 模型服务增加协议类型字段，用于协议自动识别后持久化。
    if (await _tableExists(database, 'model_services') &&
        !await _columnExists(database, 'model_services', 'protocol_type')) {
      await database.execute('''
        ALTER TABLE model_services
        ADD COLUMN protocol_type TEXT NOT NULL DEFAULT 'auto'
      ''');
    }
  }

  Future<void> _migrateToVersion13(Database database) async {
    if (!await _tableExists(database, 'model_capability_tests')) {
      await _createCapabilityAndCoverageSchema(database);
      return;
    }
    if (await _columnExists(
      database,
      'model_capability_tests',
      'request_sent',
    )) {
      return;
    }

    // v10-v12 把 elapsed_ms 强制为 >= 1，导致"未发出请求"的短路项也被
    // 伪装成 1ms。SQLite 无法直接修改 CHECK，因此原子重建这张小表。
    await database.execute('DROP TABLE IF EXISTS model_capability_tests_v13');
    await database.execute('''
      CREATE TABLE model_capability_tests_v13 (
        service_id TEXT NOT NULL,
        capability TEXT NOT NULL,
        verdict TEXT NOT NULL
          CHECK (verdict IN ('supported', 'unsupported', 'unconfirmed')),
        elapsed_ms INTEGER NOT NULL CHECK (elapsed_ms >= 0),
        request_sent INTEGER NOT NULL DEFAULT 1
          CHECK (request_sent IN (0, 1)),
        diagnosis_json TEXT NOT NULL DEFAULT '{}',
        configuration_fingerprint TEXT NOT NULL,
        detail TEXT NOT NULL DEFAULT '',
        tested_at TEXT NOT NULL,
        PRIMARY KEY (service_id, capability),
        FOREIGN KEY (service_id) REFERENCES model_services(id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      INSERT INTO model_capability_tests_v13 (
        service_id, capability, verdict, elapsed_ms, request_sent,
        diagnosis_json, configuration_fingerprint, detail, tested_at
      )
      SELECT service_id, capability, verdict, elapsed_ms, 1, '{}',
             configuration_fingerprint, detail, tested_at
      FROM model_capability_tests
    ''');
    await database.execute('DROP TABLE model_capability_tests');
    await database.execute('''
      ALTER TABLE model_capability_tests_v13
      RENAME TO model_capability_tests
    ''');
  }

  /// 阶段 1：稳定 ID 工厂与模型绑定 schema
  Future<void> _migrateToVersion14(Database database) async {
    // 1. 创建 assistant_model_bindings 表
    if (!await _tableExists(database, 'assistant_model_bindings')) {
      await database.execute('''
        CREATE TABLE assistant_model_bindings (
          assistant_id TEXT NOT NULL,
          binding_role TEXT NOT NULL,
          model_service_id TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (assistant_id, binding_role),
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (model_service_id) REFERENCES model_services(id)
        )
      ''');
    }

    // 2. 为 conversations 添加 kind 和 status 字段
    if (!await _columnExists(database, 'conversations', 'kind')) {
      await database.execute(
        "ALTER TABLE conversations ADD COLUMN kind TEXT NOT NULL DEFAULT 'single'",
      );
    }
    if (!await _columnExists(database, 'conversations', 'status')) {
      await database.execute(
        "ALTER TABLE conversations ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
      );
    }

    // 3. 删除旧的唯一索引并创建部分唯一索引
    // SQLite 不支持 DROP INDEX IF EXISTS，需要先检查
    final indexes = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_conversations_one_per_assistant'",
    );
    if (indexes.isNotEmpty) {
      await database.execute('DROP INDEX idx_conversations_one_per_assistant');
    }

    // 创建新的部分唯一索引（只约束 kind='single' AND status='active'）
    await database.execute('''
      CREATE UNIQUE INDEX idx_conversations_one_active_single_per_assistant
      ON conversations(assistant_id)
      WHERE kind='single' AND status='active'
    ''');
  }

  /// 阶段 5：桌面端式消息版本与回答版本
  Future<void> _migrateToVersion15(Database database) async {
    // 1. 为 messages 表添加版本相关字段
    if (!await _columnExists(database, 'messages', 'revision')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN revision INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!await _columnExists(
      database,
      'messages',
      'current_message_version_id',
    )) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN current_message_version_id TEXT',
      );
    }
    if (!await _columnExists(
      database,
      'messages',
      'current_answer_version_id',
    )) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN current_answer_version_id TEXT',
      );
    }
    if (!await _columnExists(
      database,
      'messages',
      'current_answer_version_number',
    )) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN current_answer_version_number INTEGER',
      );
    }
    if (!await _columnExists(database, 'messages', 'answer_version_count')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN answer_version_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(database, 'messages', 'answer_status')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN answer_status TEXT',
      );
    }
    if (!await _columnExists(database, 'messages', 'is_deleted')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(database, 'messages', 'visible')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN visible INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!await _columnExists(database, 'messages', 'content_hash')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN content_hash TEXT',
      );
    }
    if (!await _columnExists(database, 'messages', 'updated_at')) {
      await database.execute('ALTER TABLE messages ADD COLUMN updated_at TEXT');
    }

    // 2. 创建 message_versions 表
    if (!await _tableExists(database, 'message_versions')) {
      await database.execute('''
        CREATE TABLE message_versions (
          version_id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          version_number INTEGER NOT NULL,
          content TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          edited_by TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
          UNIQUE(message_id, version_number)
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_message_versions_message_id
        ON message_versions(message_id, version_number DESC)
      ''');
    }

    // 3. 创建 answer_versions 表
    if (!await _tableExists(database, 'answer_versions')) {
      await database.execute('''
        CREATE TABLE answer_versions (
          answer_version_id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          version_number INTEGER NOT NULL,
          content TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          model_service_id TEXT,
          model_name TEXT,
          prompt_tokens INTEGER,
          completion_tokens INTEGER,
          finish_reason TEXT,
          branch_parent_version_id TEXT,
          branch_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
          UNIQUE(message_id, version_number)
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_answer_versions_message_id
        ON answer_versions(message_id, version_number DESC)
      ''');
      await database.execute('''
        CREATE INDEX idx_answer_versions_branch
        ON answer_versions(message_id, branch_active DESC, version_number DESC)
      ''');
    }
  }

  /// 阶段 6：记忆覆盖、精确来源与失效重评
  Future<void> _migrateToVersion16(Database database) async {
    // 1. 创建处理批次表（修订感知的覆盖记录）
    if (!await _tableExists(database, 'background_source_batches')) {
      await database.execute('''
        CREATE TABLE background_source_batches (
          batch_id TEXT PRIMARY KEY,
          processor TEXT NOT NULL,
          assistant_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          source_hash TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending'
            CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
          trigger_source TEXT NOT NULL,
          output_refs_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
          UNIQUE(processor, assistant_id, conversation_id, source_hash)
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_background_batches_processor_status
        ON background_source_batches(processor, status, created_at DESC)
      ''');
    }

    // 2. 创建修订感知的覆盖账本
    if (!await _tableExists(database, 'background_source_message_state')) {
      await database.execute('''
        CREATE TABLE background_source_message_state (
          processor TEXT NOT NULL,
          assistant_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          revision_key TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          batch_id TEXT,
          status TEXT NOT NULL DEFAULT 'pending'
            CHECK (status IN ('pending', 'processing', 'completed', 'skipped')),
          processed_at TEXT,
          PRIMARY KEY(processor, assistant_id, conversation_id, message_id),
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
          FOREIGN KEY (batch_id) REFERENCES background_source_batches(batch_id) ON DELETE SET NULL
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_background_state_status
        ON background_source_message_state(processor, status, processed_at DESC)
      ''');
    }

    // 3. 为 memory_evidence 表补齐精确来源字段
    if (!await _columnExists(
      database,
      'memory_evidence',
      'message_version_id',
    )) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN message_version_id TEXT',
      );
    }
    if (!await _columnExists(
      database,
      'memory_evidence',
      'answer_version_id',
    )) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN answer_version_id TEXT',
      );
    }
    if (!await _columnExists(database, 'memory_evidence', 'revision_key')) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN revision_key TEXT',
      );
    }
    if (!await _columnExists(
      database,
      'memory_evidence',
      'source_content_hash',
    )) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN source_content_hash TEXT',
      );
    }
    if (!await _columnExists(database, 'memory_evidence', 'invalidated')) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN invalidated INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(
      database,
      'memory_evidence',
      'invalidated_reason',
    )) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN invalidated_reason TEXT',
      );
    }
    if (!await _columnExists(database, 'memory_evidence', 'invalidated_at')) {
      await database.execute(
        'ALTER TABLE memory_evidence ADD COLUMN invalidated_at TEXT',
      );
    }

    // 4. 为 memory_items 表添加生命周期字段
    if (!await _columnExists(database, 'memory_items', 'lifecycle_status')) {
      await database.execute(
        'ALTER TABLE memory_items ADD COLUMN lifecycle_status TEXT',
      );
    }
    if (!await _columnExists(database, 'memory_items', 'pending_update')) {
      await database.execute(
        'ALTER TABLE memory_items ADD COLUMN pending_update INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(database, 'memory_items', 'pending_delete')) {
      await database.execute(
        'ALTER TABLE memory_items ADD COLUMN pending_delete INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists(database, 'memory_items', 'pause_retrieval')) {
      await database.execute(
        'ALTER TABLE memory_items ADD COLUMN pause_retrieval INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  /// 阶段 6：记忆重评任务表
  Future<void> _migrateToVersion17(Database database) async {
    // 创建重评任务表
    if (!await _tableExists(database, 'memory_recheck_tasks')) {
      await database.execute('''
        CREATE TABLE memory_recheck_tasks (
          task_id TEXT PRIMARY KEY,
          memory_id TEXT NOT NULL,
          source_message_id TEXT NOT NULL,
          expected_version_id TEXT NOT NULL,
          change_type TEXT NOT NULL
            CHECK (change_type IN ('edit', 'delete', 'answer_version_switch')),
          not_before TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'waiting_stability'
            CHECK (status IN ('waiting_stability', 'processing', 'waiting_confirmation',
                              'completed', 'superseded', 'cancelled', 'failed')),
          attempt_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          suggestion_json TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id) ON DELETE CASCADE,
          FOREIGN KEY (source_message_id) REFERENCES messages(id) ON DELETE CASCADE
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_recheck_tasks_status
        ON memory_recheck_tasks(status, not_before ASC)
      ''');
      await database.execute('''
        CREATE INDEX idx_recheck_tasks_message
        ON memory_recheck_tasks(source_message_id, status)
      ''');
    }
  }

  Future<void> _migrateToVersion18(Database database) async {
    // 阶段 7：日记域表
    if (!await _tableExists(database, 'diary_entries')) {
      await database.execute('''
        CREATE TABLE diary_entries (
          diary_id TEXT PRIMARY KEY,
          assistant_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          title TEXT,
          content TEXT NOT NULL,
          mood TEXT,
          tags TEXT,
          source TEXT NOT NULL DEFAULT 'auto',
          status TEXT NOT NULL DEFAULT 'active',
          is_read INTEGER NOT NULL DEFAULT 0,
          prompt_tokens INTEGER DEFAULT 0,
          completion_tokens INTEGER DEFAULT 0,
          total_tokens INTEGER DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_diary_entries_assistant
        ON diary_entries(assistant_id, created_at DESC)
      ''');
      await database.execute('''
        CREATE INDEX idx_diary_entries_conversation
        ON diary_entries(conversation_id, created_at DESC)
      ''');
    }

    if (!await _tableExists(database, 'journal_message_links')) {
      await database.execute('''
        CREATE TABLE journal_message_links (
          diary_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          usage_type TEXT NOT NULL DEFAULT 'auto',
          revision_key TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (diary_id, message_id),
          FOREIGN KEY (diary_id) REFERENCES diary_entries(diary_id) ON DELETE CASCADE,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_journal_links_message
        ON journal_message_links(message_id, diary_id)
      ''');
    }

    if (!await _tableExists(database, 'auto_journal_message_state')) {
      await database.execute('''
        CREATE TABLE auto_journal_message_state (
          message_id TEXT PRIMARY KEY,
          eligibility TEXT NOT NULL,
          reason TEXT,
          settled_by TEXT,
          settled_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_auto_journal_eligibility
        ON auto_journal_message_state(eligibility)
      ''');
    }

    if (!await _tableExists(database, 'diary_runs')) {
      await database.execute('''
        CREATE TABLE diary_runs (
          run_id TEXT PRIMARY KEY,
          assistant_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          run_type TEXT NOT NULL,
          decision TEXT NOT NULL,
          reason TEXT,
          candidate_count INTEGER DEFAULT 0,
          source_hash TEXT,
          diary_id TEXT,
          error_message TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
          FOREIGN KEY (diary_id) REFERENCES diary_entries(diary_id) ON DELETE SET NULL
        )
      ''');
      await database.execute('''
        CREATE INDEX idx_diary_runs_created
        ON diary_runs(created_at DESC)
      ''');
      await database.execute('''
        CREATE INDEX idx_diary_runs_assistant
        ON diary_runs(assistant_id, created_at DESC)
      ''');
    }

    if (!await _tableExists(database, 'auto_journal_toggle_events')) {
      await database.execute('''
        CREATE TABLE auto_journal_toggle_events (
          event_id TEXT PRIMARY KEY,
          assistant_id TEXT NOT NULL,
          enabled INTEGER NOT NULL,
          reason TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
        )
      ''');
    }

    if (!await _tableExists(database, 'diary_reflection_state')) {
      await database.execute('''
        CREATE TABLE diary_reflection_state (
          assistant_id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          last_reflection_at TEXT,
          reflection_count INTEGER DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        )
      ''');
    }
  }

  Future<void> _migrateToVersion19(Database database) async {
    // 模型服务增加 provider_id 与 Adapter 版本，支持官方服务商预置。
    if (await _tableExists(database, 'model_services') &&
        !await _columnExists(database, 'model_services', 'provider_id')) {
      await database.execute('''
        ALTER TABLE model_services
        ADD COLUMN provider_id TEXT NOT NULL DEFAULT 'custom'
      ''');
    }
    if (await _tableExists(database, 'model_services') &&
        !await _columnExists(
          database,
          'model_services',
          'provider_adapter_version',
        )) {
      await database.execute('''
        ALTER TABLE model_services
        ADD COLUMN provider_adapter_version INTEGER NOT NULL DEFAULT 1
      ''');
    }
  }

  Future<void> _migrateToVersion20(Database database) async {
    // 助手新增「记忆表达风格」设置：natural / concise / detailed / custom。
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(
          database,
          'assistants',
          'memory_expression_style',
        )) {
      await database.execute('''
        ALTER TABLE assistants
        ADD COLUMN memory_expression_style TEXT NOT NULL DEFAULT 'natural'
      ''');
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(
          database,
          'assistants',
          'memory_expression_custom',
        )) {
      await database.execute('''
        ALTER TABLE assistants
        ADD COLUMN memory_expression_custom TEXT NOT NULL DEFAULT ''
      ''');
    }
  }

  Future<void> _migrateToVersion21(Database database) async {
    // 注入系统字段 + 双回复 reply_mode 统一在此补齐。
    // 此前这些列被误挂在 v6 迁移里，而 schemaVersion 未随之上涨，
    // 已升级到 v20 的旧库不触发 onUpgrade、列一直缺失（no such column）。
    // 升到 v21 强制旧库补列；新建库由建表语句直接带出这些列。
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'reply_mode')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN reply_mode TEXT NOT NULL DEFAULT 'complete'",
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'communication_style')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN communication_style TEXT NOT NULL DEFAULT ''",
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'behavior_boundaries')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN behavior_boundaries TEXT NOT NULL DEFAULT ''",
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'context_window')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN context_window INTEGER NOT NULL DEFAULT 100000',
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'max_output_tokens')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN max_output_tokens INTEGER NOT NULL DEFAULT 8192',
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'timestamps_enabled')) {
      await database.execute(
        'ALTER TABLE assistants ADD COLUMN timestamps_enabled INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(database, 'assistants', 'user_profile')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN user_profile TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<void> _migrateToVersion22(Database database) async {
    // Token 用量统计表
    await database.execute('''
      CREATE TABLE IF NOT EXISTS token_usage_records (
        record_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        task_type TEXT NOT NULL CHECK (task_type IN ('chat', 'memory_rebuild', 'function')),
        task_subtype TEXT,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        request_id TEXT,
        conversation_id TEXT,
        message_id TEXT,
        job_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_token_usage_assistant_time
      ON token_usage_records(assistant_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_token_usage_task_type
      ON token_usage_records(task_type, created_at DESC)
    ''');
  }

  Future<void> _migrateToVersion23(Database database) async {
    // 第一批：助手自我信息修正 - Pattern 元数据
    // 老库若尚未存在 memory_pattern_candidates（极端历史路径），跳过补列：
    // 该表建表语句已自带这些列；真实设备库该表早在 v7 迁移已创建。
    if (!await _tableExists(database, 'memory_pattern_candidates')) return;
    if (!await _columnExists(
      database,
      'memory_pattern_candidates',
      'subject_scope',
    )) {
      await database.execute('''
        ALTER TABLE memory_pattern_candidates
        ADD COLUMN subject_scope TEXT NOT NULL DEFAULT 'other'
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_pattern_candidates',
      'assistant_self_kind',
    )) {
      await database.execute('''
        ALTER TABLE memory_pattern_candidates
        ADD COLUMN assistant_self_kind TEXT
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_pattern_candidates',
      'eligible_for_active',
    )) {
      await database.execute('''
        ALTER TABLE memory_pattern_candidates
        ADD COLUMN eligible_for_active INTEGER NOT NULL DEFAULT 0
      ''');
    }
  }

  Future<void> _migrateToVersion24(Database database) async {
    // 第一批封口：确保 memory_items 主体元数据字段存在（补齐 v23 遗漏）
    // 与 v23 同理：memory_items 不存在时跳过（建表语句已带这些列）。
    if (!await _tableExists(database, 'memory_items')) return;
    if (!await _columnExists(database, 'memory_items', 'subject_scope')) {
      await database.execute('''
        ALTER TABLE memory_items
        ADD COLUMN subject_scope TEXT NOT NULL DEFAULT 'other'
      ''');
    }
    if (!await _columnExists(database, 'memory_items', 'assistant_self_kind')) {
      await database.execute('''
        ALTER TABLE memory_items
        ADD COLUMN assistant_self_kind TEXT
      ''');
    }
  }

  Future<void> _migrateToVersion25(Database database) async {
    // 通用持久后台任务系统：补齐通用任务中心的数据基础
    // 扩展 local_jobs 表，使其能够承载不同业务任务的持久化记录
    if (!await _tableExists(database, 'local_jobs')) return;

    // 添加任务类型
    if (!await _columnExists(database, 'local_jobs', 'task_type')) {
      await database.execute('''
        ALTER TABLE local_jobs
        ADD COLUMN task_type TEXT
      ''');
    }

    // 添加任务参数（JSON）
    if (!await _columnExists(database, 'local_jobs', 'payload')) {
      await database.execute('''
        ALTER TABLE local_jobs
        ADD COLUMN payload TEXT
      ''');
    }

    // 添加归属 scope
    if (!await _columnExists(database, 'local_jobs', 'scope_type')) {
      await database.execute('''
        ALTER TABLE local_jobs
        ADD COLUMN scope_type TEXT
      ''');
    }
    if (!await _columnExists(database, 'local_jobs', 'scope_id')) {
      await database.execute('''
        ALTER TABLE local_jobs
        ADD COLUMN scope_id TEXT
      ''');
    }

    // 添加错误信息
    if (!await _columnExists(database, 'local_jobs', 'last_error')) {
      await database.execute('''
        ALTER TABLE local_jobs
        ADD COLUMN last_error TEXT
      ''');
    }

    // 添加重试次数
    if (!await _columnExists(database, 'local_jobs', 'retry_count')) {
      await database.execute('''
        ALTER TABLE local_jobs
        ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0
      ''');
    }
  }

  Future<void> _migrateToVersion26(Database database) async {
    // 消息 segment 子表：一个 message 可以有多个 UI 气泡
    await database.execute('''
      CREATE TABLE IF NOT EXISTS message_segments (
        message_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL,
        content TEXT NOT NULL,
        PRIMARY KEY (message_id, segment_index),
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_segments_message_id
      ON message_segments(message_id, segment_index ASC)
    ''');
  }

  Future<void> _migrateToVersion27(Database database) async {
    await _createDeveloperToolsSchema(database);
  }

  Future<void> _migrateToVersion28(Database database) async {
    // 添加上下文检查器的结构化字段（如果不存在）
    // 使用 PRAGMA table_info 检查列是否存在，避免重复添加
    final columns = await database.rawQuery(
      "PRAGMA table_info(developer_request_contexts)",
    );
    final columnNames = columns.map((col) => col['name'] as String).toSet();

    if (!columnNames.contains('system_parts_json')) {
      await database.execute('''
        ALTER TABLE developer_request_contexts
        ADD COLUMN system_parts_json TEXT
      ''');
    }
    if (!columnNames.contains('recent_messages_json')) {
      await database.execute('''
        ALTER TABLE developer_request_contexts
        ADD COLUMN recent_messages_json TEXT
      ''');
    }
    if (!columnNames.contains('context_metadata_json')) {
      await database.execute('''
        ALTER TABLE developer_request_contexts
        ADD COLUMN context_metadata_json TEXT
      ''');
    }
  }

  Future<void> _migrateToVersion29(Database database) async {
    await _createToolSourcesSchema(database);
  }

  Future<void> _migrateToVersion30(Database database) async {
    await _createToolRuntimeGrantSchema(database);

    // tool_sources 补充 trust 字段（§54 Tool Source Trust）
    final columns = await database.rawQuery("PRAGMA table_info(tool_sources)");
    final columnNames = columns.map((col) => col['name'] as String).toSet();
    if (!columnNames.contains('trust')) {
      await database.execute('''
        ALTER TABLE tool_sources
        ADD COLUMN trust TEXT NOT NULL DEFAULT 'remote'
      ''');
    }
  }

  Future<void> _migrateToVersion31(Database database) async {
    if (!await _tableExists(database, 'diary_entries')) return;
    final columns = await database.rawQuery("PRAGMA table_info(diary_entries)");
    final columnNames = columns
        .map((column) => column['name'] as String)
        .toSet();
    if (!columnNames.contains('is_read')) {
      await database.execute('''
        ALTER TABLE diary_entries
        ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0
      ''');
    }
  }

  Future<void> _migrateToVersion32(Database database) async {
    if (!await _tableExists(database, 'assistants')) return;
    if (!await _columnExists(database, 'assistants', 'diary_writer')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN diary_writer TEXT NOT NULL DEFAULT '助手'",
      );
    }
    if (!await _columnExists(database, 'assistants', 'diary_subject')) {
      await database.execute(
        "ALTER TABLE assistants ADD COLUMN diary_subject TEXT NOT NULL DEFAULT '用户'",
      );
    }
  }

  Future<void> _migrateToVersion33(Database database) async {
    await _createToolCallRunsSchema(database);
  }

  /// 工具调用运行记录表（Tool 底座方案 §52 tool_call_runs）
  ///
  /// 审计日志持久化，追加型写入。敏感内容脱敏由写入方负责（§28）。
  Future<void> _createToolCallRunsSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_call_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        audit_id TEXT NOT NULL,
        tool_id TEXT NOT NULL,
        call_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT,
        user_id TEXT,
        started_at TEXT NOT NULL,
        finished_at TEXT NOT NULL,
        status TEXT NOT NULL,
        error_code TEXT,
        error_message TEXT,
        duration_ms INTEGER NOT NULL,
        input_summary TEXT,
        output_summary TEXT,
        risk_level TEXT,
        privacy_class TEXT,
        budget_class TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_call_runs_tool_started
      ON tool_call_runs(tool_id, started_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_call_runs_assistant_started
      ON tool_call_runs(assistant_id, started_at DESC)
    ''');
  }

  /// 工具权限状态表（Tool 底座方案 §52/§54）
  ///
  /// - assistant_tool_grants：助手级授权（第二级授权），重启不丢
  /// - tool_enablement：工具启用开关（第一级授权），重启不丢
  Future<void> _createToolRuntimeGrantSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_tool_grants (
        assistant_id TEXT NOT NULL,
        tool_id TEXT NOT NULL,
        granted_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, tool_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_assistant_tool_grants_tool
      ON assistant_tool_grants(tool_id)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_enablement (
        tool_id TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// 工具来源表（Tool 底座方案 §52 tool_sources）
  ///
  /// 存储用户添加的外部工具源（首版为 MCP，预留 http/device/game/custom）。
  /// 注意：本表只存配置与 secret_ref，绝不存密钥本体（§29）。
  Future<void> _createToolSourcesSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_sources (
        source_id TEXT PRIMARY KEY,
        source_type TEXT NOT NULL,
        name TEXT NOT NULL,
        config_json TEXT NOT NULL,
        auth_secret_ref TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        trust TEXT NOT NULL DEFAULT 'remote',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_sources_type
      ON tool_sources(source_type)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_sources_enabled
      ON tool_sources(enabled)
    ''');
  }

  Future<void> _createDeveloperToolsSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS developer_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        level TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        tag TEXT,
        details TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_developer_logs_timestamp
      ON developer_logs(timestamp DESC, id DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS developer_request_contexts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id TEXT NOT NULL UNIQUE,
        timestamp TEXT NOT NULL,
        model_id TEXT NOT NULL,
        messages_json TEXT NOT NULL,
        base_url TEXT NOT NULL,
        max_tokens INTEGER,
        temperature REAL,
        protocol TEXT,
        conversation_id TEXT,
        assistant_id TEXT,
        response_preview TEXT,
        error_message TEXT,
        system_parts_json TEXT,
        recent_messages_json TEXT,
        context_metadata_json TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_developer_contexts_timestamp
      ON developer_request_contexts(timestamp DESC, id DESC)
    ''');
  }

  /// Memory V2 与聊天、导入共用这一份手机 SQLite；不存在 Import Memory 副本。
  Future<void> _createMemoryV2Schema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS model_services (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        api_key_ref TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        protocol_type TEXT NOT NULL DEFAULT 'auto',
        provider_id TEXT NOT NULL DEFAULT 'custom',
        provider_adapter_version INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'untested'
          CHECK (status IN ('untested', 'available', 'error')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_items (
        memory_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        content TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'archived')),
        event_time TEXT,
        time_precision TEXT NOT NULL DEFAULT 'unknown',
        event_timezone TEXT NOT NULL DEFAULT '',
        importance REAL NOT NULL DEFAULT 0.5,
        reinforcement_count INTEGER NOT NULL DEFAULT 0,
        manual_edit INTEGER NOT NULL DEFAULT 0,
        source_mode TEXT NOT NULL DEFAULT 'sourced'
          CHECK (source_mode IN ('sourced', 'source_free')),
        source_time TEXT,
        is_new INTEGER NOT NULL DEFAULT 0,
        edit_version INTEGER NOT NULL DEFAULT 1,
        rebuild_run_id TEXT NOT NULL DEFAULT '',
        lifecycle_status TEXT,
        pending_update INTEGER NOT NULL DEFAULT 0,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        pause_retrieval INTEGER NOT NULL DEFAULT 0,
        subject_scope TEXT NOT NULL DEFAULT 'other',
        assistant_self_kind TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_evidence (
        evidence_id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        type TEXT NOT NULL
          CHECK (type IN ('explicit_fact', 'weak_signal', 'counter_example')),
        strength REAL NOT NULL CHECK (strength >= 0 AND strength <= 1),
        content TEXT NOT NULL,
        source_message_id TEXT NOT NULL,
        source_role TEXT NOT NULL,
        source_message_time TEXT,
        source_conversation_id TEXT NOT NULL,
        source_group_key TEXT NOT NULL,
        processed_order INTEGER NOT NULL DEFAULT 0,
        rebuild_run_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        message_version_id TEXT,
        answer_version_id TEXT,
        revision_key TEXT,
        source_content_hash TEXT,
        invalidated INTEGER NOT NULL DEFAULT 0,
        invalidated_reason TEXT,
        invalidated_at TEXT,
        UNIQUE (memory_id, source_message_id, type),
        FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id)
          ON DELETE CASCADE,
        FOREIGN KEY (source_message_id) REFERENCES messages(id)
          ON DELETE RESTRICT
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_lifecycle_operations (
        operation_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        memory_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK (action IN (
          'add', 'revise', 'supersede', 'reinforce',
          'merge', 'ignore', 'refine', 'drift'
        )),
        target_memory_ids_json TEXT NOT NULL DEFAULT '[]',
        rebuild_run_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tombstones (
        tombstone_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        content_snippet TEXT NOT NULL,
        semantic_terms_json TEXT NOT NULL DEFAULT '[]',
        deleted_memory_id TEXT NOT NULL DEFAULT '',
        deletion_checkpoint_message_id TEXT NOT NULL DEFAULT '',
        deletion_source TEXT NOT NULL DEFAULT 'user_manual',
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_pattern_candidates (
        pattern_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        hypothesis TEXT NOT NULL,
        supporting_evidence_json TEXT NOT NULL DEFAULT '[]',
        counter_evidence_json TEXT NOT NULL DEFAULT '[]',
        support_groups_json TEXT NOT NULL DEFAULT '[]',
        counter_groups_json TEXT NOT NULL DEFAULT '[]',
        support_group_count INTEGER NOT NULL DEFAULT 0,
        counter_group_count INTEGER NOT NULL DEFAULT 0,
        stability REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'observing'
          CHECK (status IN ('observing', 'confirmed', 'rejected', 'merged')),
        merged_to_memory_id TEXT,
        suppressed_by_tombstone_id TEXT NOT NULL DEFAULT '',
        rebuild_run_id TEXT NOT NULL DEFAULT '',
        subject_scope TEXT NOT NULL DEFAULT 'other',
        assistant_self_kind TEXT,
        eligible_for_active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (merged_to_memory_id) REFERENCES memory_items(memory_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_continuity_state (
        assistant_id TEXT NOT NULL,
        state_version INTEGER NOT NULL,
        relationship_state TEXT NOT NULL DEFAULT '',
        relationship_state_status TEXT NOT NULL DEFAULT 'current'
          CHECK (relationship_state_status IN ('current', 'needs_refresh')),
        relationship_state_pending_message_ids_json TEXT NOT NULL DEFAULT '[]',
        current_user_impression TEXT NOT NULL DEFAULT '',
        current_relationship_view TEXT NOT NULL DEFAULT '',
        pending_changes_json TEXT NOT NULL DEFAULT '[]',
        source_summary TEXT NOT NULL DEFAULT '',
        covered_message_ids_json TEXT NOT NULL DEFAULT '[]',
        checkpoint_message_id TEXT NOT NULL DEFAULT '',
        is_calibrated INTEGER NOT NULL DEFAULT 0,
        rebuild_run_id TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, state_version),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_jobs (
        run_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT,
        import_job_id TEXT,
        scope TEXT NOT NULL CHECK (scope IN ('recent', 'all')),
        recent_count INTEGER,
        idempotency_key TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'queued'
          CHECK (status IN (
            'queued', 'running', 'pause_requested', 'paused',
            'completed', 'failed', 'cancelled'
          )),
        desired_state TEXT NOT NULL DEFAULT 'running'
          CHECK (desired_state IN ('running', 'paused')),
        frozen_message_count INTEGER NOT NULL DEFAULT 0,
        total_chunks INTEGER NOT NULL DEFAULT 0,
        processed_chunks INTEGER NOT NULL DEFAULT 0,
        committed_memories INTEGER NOT NULL DEFAULT 0,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        partial_kept INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        retryable INTEGER NOT NULL DEFAULT 0,
        error_code TEXT NOT NULL DEFAULT '',
        worker_token TEXT,
        lease_expires_at TEXT,
        heartbeat_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE SET NULL,
        FOREIGN KEY (import_job_id) REFERENCES import_jobs(job_id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_scope_messages (
        run_id TEXT NOT NULL,
        frozen_order INTEGER NOT NULL,
        message_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        PRIMARY KEY (run_id, frozen_order),
        UNIQUE (run_id, message_id),
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE RESTRICT
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_checkpoints (
        checkpoint_id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        chunk_fingerprint TEXT NOT NULL,
        request_key TEXT NOT NULL UNIQUE,
        checkpoint_kind TEXT NOT NULL DEFAULT 'chunk'
          CHECK (checkpoint_kind IN ('chunk', 'final_consolidation')),
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'calling', 'done', 'failed')),
        message_ids_json TEXT NOT NULL,
        request_context_json TEXT NOT NULL DEFAULT '{}',
        response_json TEXT,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (run_id, chunk_index),
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_usage_records (
        usage_id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        checkpoint_id TEXT NOT NULL UNIQUE,
        model TEXT NOT NULL DEFAULT '',
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE,
        FOREIGN KEY (checkpoint_id) REFERENCES memory_rebuild_checkpoints(checkpoint_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_items_assistant_status
      ON memory_items(assistant_id, status, updated_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_evidence_source
      ON memory_evidence(assistant_id, source_message_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tombstones_assistant_hash
      ON tombstones(assistant_id, content_hash)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_patterns_assistant_status
      ON memory_pattern_candidates(assistant_id, status, support_group_count)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_rebuild_jobs_assistant_updated
      ON memory_rebuild_jobs(assistant_id, updated_at DESC)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_rebuild_one_active_assistant
      ON memory_rebuild_jobs(assistant_id)
      WHERE status IN ('queued', 'running', 'pause_requested')
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_rebuild_jobs_lease
      ON memory_rebuild_jobs(status, lease_expires_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_rebuild_checkpoints_kind
      ON memory_rebuild_checkpoints(run_id, checkpoint_kind, chunk_index)
    ''');
    await _createMemoryRebuildSnapshotSchema(database);
    await _createCapabilityAndCoverageSchema(database);

    // 阶段 6：处理批次和覆盖账本（v16）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS background_source_batches (
        batch_id TEXT PRIMARY KEY,
        processor TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
        trigger_source TEXT NOT NULL,
        output_refs_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        UNIQUE(processor, assistant_id, conversation_id, source_hash)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_background_batches_processor_status
      ON background_source_batches(processor, status, created_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS background_source_message_state (
        processor TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        revision_key TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        batch_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'processing', 'completed', 'skipped')),
        processed_at TEXT,
        PRIMARY KEY(processor, assistant_id, conversation_id, message_id),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES background_source_batches(batch_id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_background_state_status
      ON background_source_message_state(processor, status, processed_at DESC)
    ''');

    // 阶段 6：重评任务（v17）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_recheck_tasks (
        task_id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        source_message_id TEXT NOT NULL,
        expected_version_id TEXT NOT NULL,
        change_type TEXT NOT NULL
          CHECK (change_type IN ('edit', 'delete', 'answer_version_switch')),
        not_before TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'waiting_stability'
          CHECK (status IN ('waiting_stability', 'processing', 'waiting_confirmation',
                            'completed', 'superseded', 'cancelled', 'failed')),
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        suggestion_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id) ON DELETE CASCADE,
        FOREIGN KEY (source_message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_recheck_tasks_status
      ON memory_recheck_tasks(status, not_before ASC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_recheck_tasks_message
      ON memory_recheck_tasks(source_message_id, status)
    ''');

    // 阶段 7：日记域表（v18）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS diary_entries (
        diary_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL,
        mood TEXT,
        tags TEXT,
        source TEXT NOT NULL DEFAULT 'auto',
        status TEXT NOT NULL DEFAULT 'active',
        is_read INTEGER NOT NULL DEFAULT 0,
        prompt_tokens INTEGER DEFAULT 0,
        completion_tokens INTEGER DEFAULT 0,
        total_tokens INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_diary_entries_assistant
      ON diary_entries(assistant_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_diary_entries_conversation
      ON diary_entries(conversation_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS journal_message_links (
        diary_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        usage_type TEXT NOT NULL DEFAULT 'auto',
        revision_key TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (diary_id, message_id),
        FOREIGN KEY (diary_id) REFERENCES diary_entries(diary_id) ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_journal_links_message
      ON journal_message_links(message_id, diary_id)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS auto_journal_message_state (
        message_id TEXT PRIMARY KEY,
        eligibility TEXT NOT NULL,
        reason TEXT,
        settled_by TEXT,
        settled_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_auto_journal_eligibility
      ON auto_journal_message_state(eligibility)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS diary_runs (
        run_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        run_type TEXT NOT NULL,
        decision TEXT NOT NULL,
        reason TEXT,
        candidate_count INTEGER DEFAULT 0,
        source_hash TEXT,
        diary_id TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (diary_id) REFERENCES diary_entries(diary_id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_diary_runs_created
      ON diary_runs(created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_diary_runs_assistant
      ON diary_runs(assistant_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS auto_journal_toggle_events (
        event_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS diary_reflection_state (
        assistant_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        last_reflection_at TEXT,
        reflection_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createMemoryRebuildSnapshotSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_snapshots (
        run_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createCapabilityAndCoverageSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS model_capability_tests (
        service_id TEXT NOT NULL,
        capability TEXT NOT NULL,
        verdict TEXT NOT NULL
          CHECK (verdict IN ('supported', 'unsupported', 'unconfirmed')),
        elapsed_ms INTEGER NOT NULL CHECK (elapsed_ms >= 0),
        request_sent INTEGER NOT NULL DEFAULT 1
          CHECK (request_sent IN (0, 1)),
        diagnosis_json TEXT NOT NULL DEFAULT '{}',
        configuration_fingerprint TEXT NOT NULL,
        detail TEXT NOT NULL DEFAULT '',
        tested_at TEXT NOT NULL,
        PRIMARY KEY (service_id, capability),
        FOREIGN KEY (service_id) REFERENCES model_services(id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_message_coverage (
        message_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        run_id TEXT NOT NULL,
        processed_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_coverage_assistant_processed
      ON memory_message_coverage(assistant_id, processed_at DESC)
    ''');
  }

  Future<void> _createGroupedImportPlanSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_plan_groups (
        job_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        group_order INTEGER NOT NULL,
        target_kind TEXT NOT NULL CHECK (target_kind IN ('new', 'existing')),
        existing_assistant_id TEXT,
        assistant_name TEXT NOT NULL,
        conversation_title TEXT NOT NULL,
        target_assistant_id TEXT,
        target_conversation_id TEXT,
        created_assistant INTEGER NOT NULL DEFAULT 0,
        created_conversation INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (job_id, group_id),
        FOREIGN KEY (job_id) REFERENCES import_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_plan_conversations (
        job_id TEXT NOT NULL,
        source_conversation_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        PRIMARY KEY (job_id, source_conversation_id),
        FOREIGN KEY (job_id, group_id)
          REFERENCES import_plan_groups(job_id, group_id) ON DELETE CASCADE,
        FOREIGN KEY (job_id, source_conversation_id)
          REFERENCES import_staging_conversations(job_id, source_conversation_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_plan_conversations_group
      ON import_plan_conversations(job_id, group_id)
    ''');
  }

  Future<void> _createParserMetadataSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_parser_metadata (
        job_id TEXT PRIMARY KEY,
        parser_id TEXT NOT NULL,
        parser_version TEXT NOT NULL,
        container_format TEXT NOT NULL,
        confidence REAL NOT NULL,
        capabilities TEXT NOT NULL DEFAULT '[]',
        uncertain_roles TEXT NOT NULL DEFAULT '[]',
        image_count INTEGER NOT NULL DEFAULT 0,
        file_count INTEGER NOT NULL DEFAULT 0,
        can_start INTEGER NOT NULL DEFAULT 0,
        source_name TEXT NOT NULL,
        source_identity TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (job_id) REFERENCES import_jobs(job_id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createAttachmentSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY,
        content_hash TEXT UNIQUE,
        storage_path TEXT,
        mime_type TEXT,
        extension TEXT,
        byte_size INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL CHECK (
          status IN ('available', 'missing', 'damaged', 'oversized', 'rejected')
        ),
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS message_attachments (
        message_id TEXT NOT NULL,
        attachment_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        original_name TEXT NOT NULL,
        source_path TEXT,
        source_url TEXT,
        status TEXT NOT NULL,
        PRIMARY KEY (message_id, position),
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (attachment_id) REFERENCES attachments(id) ON DELETE RESTRICT
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_staging_attachments (
        job_id TEXT NOT NULL,
        source_conversation_id TEXT NOT NULL,
        source_message_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        original_name TEXT NOT NULL,
        source_path TEXT,
        source_url TEXT,
        declared_mime TEXT,
        kind TEXT NOT NULL CHECK (kind IN ('image', 'file')),
        staging_path TEXT,
        content_hash TEXT,
        detected_mime TEXT,
        extension TEXT,
        byte_size INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        attachment_id TEXT,
        PRIMARY KEY (
          job_id,
          source_conversation_id,
          source_message_id,
          position
        ),
        FOREIGN KEY (job_id, source_conversation_id, source_message_id)
          REFERENCES import_staging_messages(
            job_id,
            source_conversation_id,
            source_message_id
          ) ON DELETE CASCADE,
        FOREIGN KEY (attachment_id) REFERENCES attachments(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_attachments_message
      ON message_attachments(message_id, position)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_import_staging_attachments_status
      ON import_staging_attachments(job_id, status)
    ''');
  }

  Future<void> _migrateToVersion34(Database database) async {
    if (!await _tableExists(database, 'messages')) return;
    // 增加 messages.reasoning 字段用于保存推理过程（thinking/reasoning）
    if (!await _columnExists(database, 'messages', 'reasoning')) {
      await database.execute('''
        ALTER TABLE messages ADD COLUMN reasoning TEXT
      ''');
    }
  }

  Future<void> _migrateToVersion35(Database database) async {
    await _createCapabilityStatesSchema(database);
  }

  /// 系统能力状态表（Tool 底座方案 §52 capability_states）
  ///
  /// CapabilityRegistry 的状态持久化。
  Future<void> _createCapabilityStatesSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS capability_states (
        capability_id TEXT PRIMARY KEY,
        platform TEXT NOT NULL DEFAULT 'android',
        available INTEGER NOT NULL DEFAULT 0,
        supported_on_device INTEGER NOT NULL DEFAULT 0,
        system_permission_state TEXT NOT NULL DEFAULT 'unknown',
        service_state TEXT NOT NULL DEFAULT 'none',
        last_verified_at TEXT,
        degraded_reason TEXT,
        repair_action TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateToVersion36(Database database) async {
    await _createLocalGameSchema(database);
  }

  Future<void> _migrateToVersion37(Database database) async {
    final columns = await database.rawQuery(
      'PRAGMA table_info(game_invitations)',
    );
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('inviter_actor')) {
      await database.execute('''
        ALTER TABLE game_invitations
        ADD COLUMN inviter_actor TEXT NOT NULL DEFAULT 'user'
          CHECK (inviter_actor IN ('user', 'assistant'))
      ''');
    }
    if (!names.contains('invitee_actor')) {
      await database.execute('''
        ALTER TABLE game_invitations
        ADD COLUMN invitee_actor TEXT NOT NULL DEFAULT 'assistant'
          CHECK (invitee_actor IN ('user', 'assistant'))
      ''');
    }
  }

  Future<void> _migrateToVersion38(Database database) async {
    final columns = await database.rawQuery(
      'PRAGMA table_info(game_invitations)',
    );
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('assistant_play_mode')) {
      await database.execute('''
        ALTER TABLE game_invitations
        ADD COLUMN assistant_play_mode TEXT CHECK (
          assistant_play_mode IS NULL OR assistant_play_mode IN (
            'intentional_let_win',
            'held_back',
            'normal',
            'serious',
            'full_strength'
          )
        )
      ''');
    }
  }

  Future<void> _migrateToVersion39(Database database) async {
    // v35 曾在并行分支分别承载 capability 与 game schema。
    // 最终版本在这里幂等补齐两侧，兼容已运行过任一分支迁移的数据库。
    await _createCapabilityStatesSchema(database);
    await _createLocalGameSchema(database);
    final columns = await database.rawQuery('PRAGMA table_info(game_sessions)');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('context_turns_remaining')) {
      await database.execute('''
        ALTER TABLE game_sessions
        ADD COLUMN context_turns_remaining INTEGER NOT NULL DEFAULT 0
          CHECK (
            context_turns_remaining >= 0 AND
            context_turns_remaining <= 5
          )
      ''');
    }
  }

  Future<void> _migrateToVersion40(Database database) async {
    await _createMemorySearchIndexSchema(database);
  }

  Future<void> _migrateToVersion41(Database database) async {
    await _createMemorySearchIndexSchema(database);
  }

  Future<void> _migrateToVersion44(Database database) async {
    await _createMemoryOrganizeQueueSchema(database);
  }

  Future<void> _migrateToVersion45(Database database) async {
    if (await _tableExists(database, 'assistants') &&
        !await _columnExists(
          database,
          'assistants',
          'memory_auto_organize_enabled',
        )) {
      await database.execute('''
        ALTER TABLE assistants
        ADD COLUMN memory_auto_organize_enabled INTEGER NOT NULL DEFAULT 1
      ''');
    }
    if (await _tableExists(database, 'memory_items') &&
        !await _columnExists(database, 'memory_items', 'source_mode')) {
      await database.execute('''
        ALTER TABLE memory_items
        ADD COLUMN source_mode TEXT NOT NULL DEFAULT 'sourced'
          CHECK (source_mode IN ('sourced', 'source_free'))
      ''');
    }
    if (await _tableExists(database, 'memory_items') &&
        !await _columnExists(database, 'memory_items', 'source_time')) {
      await database.execute('''
        ALTER TABLE memory_items ADD COLUMN source_time TEXT
      ''');
    }
    if (await _tableExists(database, 'memory_items') &&
        !await _columnExists(database, 'memory_items', 'is_new')) {
      await database.execute('''
        ALTER TABLE memory_items
        ADD COLUMN is_new INTEGER NOT NULL DEFAULT 0
      ''');
    }
    await _createMindBoardSchema(database);
  }

  Future<void> _migrateToVersion46(Database database) async {
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'game_invitation_id')) {
      await database.execute('''
        ALTER TABLE messages ADD COLUMN game_invitation_id TEXT
      ''');
    }
    final canCreateGameSchema =
        await _tableExists(database, 'assistants') &&
        await _tableExists(database, 'conversations') &&
        await _tableExists(database, 'messages');
    if (!canCreateGameSchema) return;
    await _createLocalGameSchema(database);
    if (!await _columnExists(database, 'game_card_projections', 'game_type')) {
      await database.execute('''
        ALTER TABLE game_card_projections
        ADD COLUMN game_type TEXT NOT NULL DEFAULT 'gomoku'
      ''');
    }
    await _createPictionaryFoundationSchema(database);
    await _createContinuityAwarenessSchema(database);
  }

  Future<void> _migrateToVersion47(Database database) async {
    if (await _tableExists(database, 'pictionary_sessions') &&
        !await _columnExists(database, 'pictionary_sessions', 'end_reason')) {
      await database.execute('''
        ALTER TABLE pictionary_sessions
        ADD COLUMN end_reason TEXT NOT NULL DEFAULT 'normal'
          CHECK (end_reason IN ('normal', 'aborted', 'technical_failure'))
      ''');
    }
  }

  Future<void> _migrateToVersion48(Database database) async {
    if (!await _tableExists(database, 'developer_request_contexts')) return;
    if (!await _columnExists(
      database,
      'developer_request_contexts',
      'request_id',
    )) {
      await database.execute('''
        ALTER TABLE developer_request_contexts ADD COLUMN request_id TEXT
      ''');
      await database.execute('''
        UPDATE developer_request_contexts
        SET request_id = 'legacy-' || id
        WHERE request_id IS NULL
      ''');
    }
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_developer_contexts_request_id
      ON developer_request_contexts(request_id)
    ''');
  }

  /// Reconciles the two independently shipped v45-v48 migration branches.
  ///
  /// Remote databases at v46 need the memory and Pictionary schemas, while
  /// local acceptance databases at v48 need the mind-board and continuity
  /// schemas. Every operation below is idempotent.
  Future<void> _migrateToVersion49(Database database) async {
    await _migrateToVersion45(database);
    await _migrateToVersion46(database);
    await _migrateToVersion47(database);
    await _migrateToVersion48(database);
  }

  /// 持续心智批次 5：Attention（M4 §9）
  Future<void> _migrateToVersion50(Database database) async {
    await _createAttentionSchema(database);
  }

  Future<void> _migrateToVersion51(Database database) async {
    await _createVoiceSchema(database);
  }

  Future<void> _migrateToVersion52(Database database) async {
    if (!await _tableExists(database, 'conversations')) return;
    if (!await _columnExists(database, 'conversations', 'draft_text')) {
      await database.execute(
        "ALTER TABLE conversations ADD COLUMN draft_text TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!await _columnExists(database, 'conversations', 'draft_updated_at')) {
      await database.execute(
        'ALTER TABLE conversations ADD COLUMN draft_updated_at TEXT',
      );
    }
  }

  Future<void> _migrateToVersion53(Database database) async {
    await _createPictionaryUserGuessesSchema(database);
  }

  /// Repairs databases that reached v50 through the former voice branch
  /// before the Attention schema was merged into that same version number.
  Future<void> _migrateToVersion54(Database database) async {
    await _createContinuityAwarenessSchema(database);
    await _createAttentionSchema(database);
  }

  Future<void> _migrateToVersion55(Database database) async {
    if (!await _tableExists(database, 'messages')) return;
    if (!await _columnExists(database, 'messages', 'context_visible')) {
      await database.execute('''
        ALTER TABLE messages ADD COLUMN context_visible INTEGER NOT NULL
          DEFAULT 0 CHECK (context_visible IN (0, 1))
      ''');
    }
  }

  Future<void> _migrateToVersion56(Database database) async {
    if (await _tableExists(database, 'tool_artifacts') &&
        !await _columnExists(database, 'tool_artifacts', 'activity_id')) {
      await database.execute(
        'ALTER TABLE tool_artifacts ADD COLUMN activity_id TEXT',
      );
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_tool_artifacts_activity
        ON tool_artifacts(activity_id)
      ''');
    }
    await _createTogetherWatchSchema(database);
  }

  /// 心跳与助手工具授权底座（心跳主动消息方案 §6.1）。
  Future<void> _migrateToVersion57(Database database) async {
    await _createHeartbeatSettingsSchema(database);
    await _createAssistantToolEnablementSchema(database);
    await _createAssistantCapabilityConsentsSchema(database);
    await _createHeartbeatRuntimeSchema(database);
    await _createProactiveMessagesSchema(database);
  }

  Future<void> _migrateToVersion58(Database database) async {
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'context_visible')) {
      await database.execute('''
        ALTER TABLE messages ADD COLUMN context_visible INTEGER NOT NULL
          DEFAULT 0 CHECK (context_visible IN (0, 1))
      ''');
    }
    await _createModelRequestTraceSchema(database);
  }

  Future<void> _migrateToVersion59(Database database) async {
    await _createPatrolFactsSchema(database);
  }

  Future<void> _migrateToVersion60(Database database) async {
    await _createAssistantAllowedAppsSchema(database);
  }

  Future<void> _migrateToVersion61(Database database) async {
    await _createAssistantActionOutboxSchema(database);
  }

  Future<void> _migrateToVersion62(Database database) async {
    await _createAssistantAppRestrictionsSchema(database);
  }

  /// 修复并行分支曾复用 53～62 迁移号造成的版本碰撞。
  ///
  /// 所有步骤均幂等：无论数据库来自共同活动分支还是心跳分支，升级后都补齐
  /// 两边的正式表与列，不依赖旧版本号所代表的历史含义。
  Future<void> _migrateToVersion63(Database database) async {
    await _migrateToVersion53(database);
    await _migrateToVersion54(database);
    await _migrateToVersion55(database);
    await _migrateToVersion56(database);
    await _migrateToVersion57(database);
    await _migrateToVersion58(database);
    await _migrateToVersion59(database);
    await _migrateToVersion60(database);
    await _migrateToVersion61(database);
    await _migrateToVersion62(database);
  }

  Future<void> _createAssistantAppRestrictionsSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_app_restrictions (
        restriction_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        package_name TEXT NOT NULL,
        reason_fact_id TEXT,
        starts_at TEXT NOT NULL,
        ends_at TEXT NOT NULL,
        status TEXT NOT NULL
          CHECK (status IN ('prepared', 'active', 'released', 'expired', 'failed')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (reason_fact_id) REFERENCES assistant_patrol_facts(fact_id)
          ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_restrictions_assistant_status
      ON assistant_app_restrictions(assistant_id, status, ends_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_app_restrictions_package_status
      ON assistant_app_restrictions(package_name, status, ends_at)
    ''');
  }

  Future<void> _createAssistantActionOutboxSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_action_outbox (
        action_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        tool_id TEXT NOT NULL,
        arguments_json TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL
          CHECK (status IN (
            'prepared', 'message_ready', 'executing', 'action_succeeded',
            'committed', 'failed', 'cancelled'
          )),
        draft_message TEXT,
        voice_state_json TEXT,
        result_json TEXT,
        error_code TEXT,
        committed_message_id TEXT,
        action_completed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (committed_message_id) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_action_outbox_recovery
      ON assistant_action_outbox(status, updated_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_action_outbox_assistant_time
      ON assistant_action_outbox(assistant_id, created_at DESC)
    ''');
  }

  Future<void> _createAssistantAllowedAppsSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_allowed_apps (
        assistant_id TEXT NOT NULL,
        package_name TEXT NOT NULL,
        selected_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, package_name),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_allowed_apps_package
      ON assistant_allowed_apps(package_name)
    ''');
  }

  Future<void> _createPatrolFactsSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_patrol_facts (
        fact_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        fact_type TEXT NOT NULL,
        summary TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        source_tool_id TEXT NOT NULL,
        observed_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'injected', 'expired', 'suppressed')),
        injected_message_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (injected_message_id) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_patrol_facts_assistant_pending
      ON assistant_patrol_facts(assistant_id, status, expires_at, priority DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_patrol_facts_source_time
      ON assistant_patrol_facts(assistant_id, source_tool_id, observed_at DESC)
    ''');
  }

  Future<void> _createModelRequestTraceSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS model_request_traces (
        trace_id TEXT PRIMARY KEY,
        task_type TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT,
        trigger_job_id TEXT,
        schedule_generation INTEGER,
        status TEXT NOT NULL
          CHECK (status IN ('prepared', 'completed', 'cancelled', 'failed')),
        source_refs_json TEXT NOT NULL DEFAULT '[]',
        tool_ids_json TEXT NOT NULL DEFAULT '[]',
        committed_message_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (committed_message_id) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_model_request_traces_assistant_time
      ON model_request_traces(assistant_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_model_request_traces_job
      ON model_request_traces(trigger_job_id)
    ''');
  }

  Future<void> _createProactiveMessagesSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_proactive_messages (
        message_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        trigger_job_id TEXT,
        committed_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_proactive_messages_assistant_time
      ON assistant_proactive_messages(assistant_id, committed_at DESC)
    ''');
  }

  Future<void> _createHeartbeatRuntimeSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_heartbeat_runtime (
        assistant_id TEXT PRIMARY KEY,
        next_due_at TEXT,
        schedule_generation INTEGER NOT NULL DEFAULT 0,
        last_due_at TEXT,
        last_started_at TEXT,
        last_completed_at TEXT,
        last_skip_reason TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createAssistantCapabilityConsentsSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_capability_consents (
        assistant_id TEXT NOT NULL,
        capability_group TEXT NOT NULL,
        consent_version INTEGER NOT NULL,
        granted_at TEXT NOT NULL,
        revoked_at TEXT,
        PRIMARY KEY (assistant_id, capability_group),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createAssistantToolEnablementSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_tool_enablement (
        assistant_id TEXT NOT NULL,
        tool_id TEXT NOT NULL,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, tool_id),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createHeartbeatSettingsSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_heartbeat_settings (
        assistant_id TEXT PRIMARY KEY,
        heartbeat_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (heartbeat_enabled IN (0, 1)),
        interval_min_minutes INTEGER NOT NULL DEFAULT 20
          CHECK (interval_min_minutes BETWEEN 1 AND 150),
        interval_max_minutes INTEGER NOT NULL DEFAULT 59
          CHECK (interval_max_minutes BETWEEN 1 AND 150),
        dnd_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (dnd_enabled IN (0, 1)),
        dnd_start_minute INTEGER NOT NULL DEFAULT 1380
          CHECK (dnd_start_minute BETWEEN 0 AND 1439),
        dnd_end_minute INTEGER NOT NULL DEFAULT 480
          CHECK (dnd_end_minute BETWEEN 0 AND 1439),
        proactive_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (proactive_enabled IN (0, 1)),
        proactive_style TEXT NOT NULL DEFAULT '',
        board_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (board_enabled IN (0, 1)),
        sticky_note_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (sticky_note_enabled IN (0, 1)),
        calendar_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (calendar_enabled IN (0, 1)),
        patrol_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (patrol_enabled IN (0, 1)),
        app_usage_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (app_usage_enabled IN (0, 1)),
        app_control_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (app_control_enabled IN (0, 1)),
        notification_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (notification_enabled IN (0, 1)),
        health_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (health_enabled IN (0, 1)),
        device_control_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (device_control_enabled IN (0, 1)),
        updated_at TEXT NOT NULL,
        CHECK (interval_min_minutes <= interval_max_minutes),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _migrateToVersion64(Database database) async {
    await _createTogetherWatchSchema(database);
    if (!await _tableExists(database, 'together_watch_sessions') ||
        !await _columnExists(
          database,
          'together_watch_sessions',
          'assistant_id',
        )) {
      return;
    }

    await database.rawInsert('''
      INSERT OR IGNORE INTO shared_sessions (
        session_id,
        assistant_id,
        conversation_id,
        session_type,
        status,
        playback_revision,
        created_at,
        ended_at,
        updated_at,
        stop_reason
      )
      SELECT
        session_id,
        assistant_id,
        conversation_id,
        'together_watch',
        CASE status WHEN 'background_paused' THEN 'active' ELSE status END,
        playback_revision,
        created_at,
        ended_at,
        updated_at,
        stop_reason
      FROM together_watch_sessions
    ''');

    if (await _tableExists(database, 'shared_activities')) {
      await database.execute(
        'ALTER TABLE shared_activity_messages RENAME TO shared_activity_messages_v56',
      );
      await database.execute(
        'ALTER TABLE shared_activity_cards RENAME TO shared_activity_cards_v56',
      );
      await database.execute(
        'ALTER TABLE shared_activities RENAME TO shared_activities_v56',
      );
      await database.execute(
        'DROP INDEX IF EXISTS idx_shared_activity_messages_context',
      );
      await database.execute(
        'DROP INDEX IF EXISTS idx_shared_activity_cards_timeline',
      );
      await database.execute(
        'DROP INDEX IF EXISTS idx_shared_activity_one_active_per_session',
      );
      await database.execute(
        'DROP INDEX IF EXISTS idx_shared_activity_scope_time',
      );
      await database.execute('DROP INDEX IF EXISTS idx_shared_activity_source');
      await _createTogetherWatchSchema(database);
      await database.rawInsert('''
        INSERT INTO shared_activities (
          activity_id,
          session_id,
          assistant_id,
          conversation_id,
          activity_type,
          status,
          stop_reason,
          source_kind,
          source_label,
          source_fingerprint,
          source_locator,
          duration_ms,
          start_position_ms,
          last_position_ms,
          furthest_position_ms,
          played_duration_ms,
          started_at,
          stopped_at,
          updated_at,
          summary,
          carryover_turns_remaining,
          card_id
        )
        SELECT
          activity_id,
          session_id,
          assistant_id,
          conversation_id,
          activity_type,
          status,
          stop_reason,
          source_kind,
          source_label,
          source_fingerprint,
          source_locator,
          duration_ms,
          start_position_ms,
          last_position_ms,
          furthest_position_ms,
          played_duration_ms,
          started_at,
          stopped_at,
          updated_at,
          summary,
          carryover_turns_remaining,
          card_id
        FROM shared_activities_v56
      ''');
      await database.rawInsert('''
        INSERT INTO shared_activity_messages (
          message_id,
          activity_id,
          assistant_id,
          conversation_id,
          role,
          origin,
          content,
          answer_status,
          visible,
          created_at
        )
        SELECT
          message_id,
          activity_id,
          assistant_id,
          conversation_id,
          role,
          origin,
          content,
          answer_status,
          visible,
          created_at
        FROM shared_activity_messages_v56
      ''');
      await database.rawInsert('''
        INSERT INTO shared_activity_cards (
          card_id,
          activity_id,
          assistant_id,
          conversation_id,
          state,
          title,
          source_label,
          start_position_ms,
          last_position_ms,
          played_duration_ms,
          summary,
          occurred_at,
          updated_at
        )
        SELECT
          card_id,
          activity_id,
          assistant_id,
          conversation_id,
          state,
          title,
          source_label,
          start_position_ms,
          last_position_ms,
          played_duration_ms,
          summary,
          occurred_at,
          updated_at
        FROM shared_activity_cards_v56
      ''');
      await database.execute('DROP TABLE shared_activity_messages_v56');
      await database.execute('DROP TABLE shared_activity_cards_v56');
      await database.execute('DROP TABLE shared_activities_v56');
    }

    await database.execute(
      'ALTER TABLE together_watch_sessions RENAME TO together_watch_sessions_v56',
    );
    await database.execute(
      'DROP INDEX IF EXISTS idx_together_watch_one_open_session',
    );
    await database.execute(
      'DROP INDEX IF EXISTS idx_together_watch_session_scope',
    );
    await _createTogetherWatchSchema(database);
    await database.rawInsert('''
      INSERT INTO together_watch_sessions (
        session_id,
        observation_interval_seconds,
        background_paused
      )
      SELECT
        session_id,
        observation_interval_seconds,
        CASE status WHEN 'background_paused' THEN 1 ELSE 0 END
      FROM together_watch_sessions_v56
    ''');
    await database.execute('DROP TABLE together_watch_sessions_v56');
  }

  Future<void> _migrateToVersion65(Database database) async {
    await _createTogetherListenSchema(database);
  }

  Future<void> _migrateToVersion66(Database database) async {
    await _createTogetherWatchSchema(database);
    if (!await _columnExists(
      database,
      'shared_activity_messages',
      'chat_message_id',
    )) {
      await database.execute('''
        ALTER TABLE shared_activity_messages
        ADD COLUMN chat_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL
      ''');
    }
    if (await _columnExists(
      database,
      'shared_activity_messages',
      'chat_message_id',
    )) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_activity_messages_chat_message
        ON shared_activity_messages(chat_message_id)
        WHERE chat_message_id IS NOT NULL
      ''');
    }

    final legacyRows = await database.rawQuery('''
      SELECT messages.*
      FROM shared_activity_messages AS messages
      INNER JOIN shared_activities AS activities
        ON activities.activity_id = messages.activity_id
      WHERE activities.activity_type = 'together_listen'
        AND messages.chat_message_id IS NULL
        AND TRIM(messages.content) <> ''
      ORDER BY messages.created_at ASC, messages.message_id ASC
    ''');
    for (final row in legacyRows) {
      final legacyId = row['message_id']! as String;
      final conversationId = row['conversation_id']! as String;
      final role = row['role']! as String;
      final content = row['content']! as String;
      var chatMessageId = legacyId;
      var suffix = 0;
      while (true) {
        final existing = await database.query(
          'messages',
          columns: const ['conversation_id', 'role', 'content'],
          where: 'id = ?',
          whereArgs: [chatMessageId],
          limit: 1,
        );
        if (existing.isEmpty ||
            (existing.single['conversation_id'] == conversationId &&
                existing.single['role'] == role &&
                existing.single['content'] == content)) {
          break;
        }
        suffix += 1;
        chatMessageId = 'together_listen_${legacyId}_$suffix';
      }
      await database.insert('messages', {
        'id': chatMessageId,
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        'answer_status': row['answer_status'],
        'visible': row['visible'],
        'context_visible': 0,
        'is_deleted': 0,
        'created_at': row['created_at'],
        'updated_at': row['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await database.update(
        'shared_activity_messages',
        {'chat_message_id': chatMessageId},
        where: 'message_id = ? AND chat_message_id IS NULL',
        whereArgs: [legacyId],
      );
    }
  }

  Future<void> _migrateToVersion67(Database database) async {
    await _createTogetherWatchSchema(database);
    await _createTogetherListenSchema(database);
    final activitySchema = await database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'shared_activities'",
    );
    final activitySql = activitySchema.isEmpty
        ? ''
        : activitySchema.single['sql'] as String? ?? '';
    if (!activitySql.contains("'together_play'") ||
        !activitySql.contains("'third_party_game'")) {
      await database.execute(
        'ALTER TABLE together_listen_track_occurrences '
        'RENAME TO together_listen_track_occurrences_v59',
      );
      await database.execute(
        'ALTER TABLE shared_activity_messages '
        'RENAME TO shared_activity_messages_v59',
      );
      await database.execute(
        'ALTER TABLE shared_activity_cards '
        'RENAME TO shared_activity_cards_v59',
      );
      await database.execute(
        'ALTER TABLE shared_activities RENAME TO shared_activities_v59',
      );
      for (final index in const [
        'idx_together_listen_track_activity',
        'idx_together_listen_track_fingerprint',
        'idx_shared_activity_messages_context',
        'idx_shared_activity_messages_chat_message',
        'idx_shared_activity_cards_timeline',
        'idx_shared_activity_one_active_per_session',
        'idx_shared_activity_scope_time',
        'idx_shared_activity_source',
      ]) {
        await database.execute('DROP INDEX IF EXISTS $index');
      }
      await _createTogetherWatchSchema(database);
      await _createTogetherListenSchema(database);
      await database.rawInsert('''
        INSERT INTO shared_activities SELECT * FROM shared_activities_v59
      ''');
      await database.rawInsert('''
        INSERT INTO shared_activity_messages (
          message_id, chat_message_id, activity_id, assistant_id,
          conversation_id, role, origin, content, answer_status, visible,
          created_at
        )
        SELECT
          message_id, chat_message_id, activity_id, assistant_id,
          conversation_id, role, origin, content, answer_status, visible,
          created_at
        FROM shared_activity_messages_v59
      ''');
      await database.rawInsert('''
        INSERT INTO shared_activity_cards
        SELECT * FROM shared_activity_cards_v59
      ''');
      await database.rawInsert('''
        INSERT INTO together_listen_track_occurrences
        SELECT * FROM together_listen_track_occurrences_v59
      ''');
      await database.execute(
        'DROP TABLE together_listen_track_occurrences_v59',
      );
      await database.execute('DROP TABLE shared_activity_messages_v59');
      await database.execute('DROP TABLE shared_activity_cards_v59');
      await database.execute('DROP TABLE shared_activities_v59');
    }
    await _createTogetherPlaySchema(database);
  }

  Future<void> _migrateToVersion68(Database database) async {
    await _createTogetherPlayFrozenMessagesSchema(database);
  }

  Future<void> _migrateToVersion69(Database database) async {
    await _createConfigurationHelpSchema(database);
  }

  Future<void> _migrateToVersion70(Database database) async {
    await _createToolAuthoringSchema(database);
  }

  Future<void> _migrateToVersion71(Database database) async {
    await _createMyDevicesSchema(database);
  }

  Future<void> _migrateToVersion72(Database database) async {
    // v57-v65 曾在并行工作区承载两套不同迁移。最终兼容迁移必须
    // 幂等补齐心跳与互动/设备两侧，确保任一历史数据库都不会漏表。
    await _migrateToVersion63(database);
    await _createTogetherWatchSchema(database);
    await _createTogetherListenSchema(database);
    await _createTogetherPlaySchema(database);
    await _createConfigurationHelpSchema(database);
    await _createToolAuthoringSchema(database);
    await _createMyDevicesSchema(database);
    if (await _tableExists(database, 'together_play_events')) {
      await database.execute(
        'ALTER TABLE together_play_events RENAME TO together_play_events_v64',
      );
      await database.execute(
        'DROP INDEX IF EXISTS idx_together_play_events_activity',
      );
      await database.execute('''
        CREATE TABLE together_play_events (
          event_id TEXT PRIMARY KEY,
          activity_id TEXT NOT NULL,
          assistant_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          event_type TEXT NOT NULL CHECK (event_type IN (
            'session_started', 'activity_started', 'paused', 'resumed',
            'control_to_user', 'control_to_assistant', 'target_app_left',
            'target_app_returned', 'action_verified', 'action_accepted',
            'action_failed', 'safety_blocked', 'permission_lost', 'ended',
            'interrupted'
          )),
          summary TEXT NOT NULL,
          occurred_at TEXT NOT NULL,
          FOREIGN KEY (activity_id) REFERENCES shared_activities(activity_id)
            ON DELETE CASCADE,
          FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
          FOREIGN KEY (conversation_id) REFERENCES conversations(id)
            ON DELETE CASCADE
        )
      ''');
      final retainedRows =
          Sqflite.firstIntValue(
            await database.rawQuery(
              'SELECT COUNT(*) FROM together_play_events_v64',
            ),
          ) ??
          0;
      if (retainedRows > 0) {
        await database.execute('''
          INSERT INTO together_play_events (
            event_id, activity_id, assistant_id, conversation_id,
            event_type, summary, occurred_at
          )
          SELECT event_id, activity_id, assistant_id, conversation_id,
            event_type, summary, occurred_at
          FROM together_play_events_v64
        ''');
      }
      await database.execute('DROP TABLE together_play_events_v64');
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_together_play_events_activity
        ON together_play_events(activity_id, occurred_at, event_id)
      ''');
    }
    await _createToolConfirmationSchema(database);
  }

  Future<void> _migrateToVersion73(Database database) async {
    await _createMemoryV2Schema(database);
    if (!await _columnExists(
      database,
      'memory_continuity_state',
      'relationship_state',
    )) {
      await database.execute('''
        ALTER TABLE memory_continuity_state
        ADD COLUMN relationship_state TEXT NOT NULL DEFAULT ''
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_continuity_state',
      'relationship_state_status',
    )) {
      await database.execute('''
        ALTER TABLE memory_continuity_state
        ADD COLUMN relationship_state_status TEXT NOT NULL DEFAULT 'current'
          CHECK (relationship_state_status IN ('current', 'needs_refresh'))
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_continuity_state',
      'relationship_state_pending_message_ids_json',
    )) {
      await database.execute('''
        ALTER TABLE memory_continuity_state
        ADD COLUMN relationship_state_pending_message_ids_json
          TEXT NOT NULL DEFAULT '[]'
      ''');
    }
    // 旧双字段仅用于一次性迁移。优先保留原“关系看法”，为空时才回退到
    // “用户印象”；迁移后业务代码只读取 relationship_state。
    await database.execute('''
      UPDATE memory_continuity_state
      SET relationship_state = CASE
        WHEN TRIM(current_relationship_view) <> ''
          THEN TRIM(current_relationship_view)
        ELSE TRIM(current_user_impression)
      END
      WHERE TRIM(relationship_state) = ''
        AND (
          TRIM(current_relationship_view) <> '' OR
          TRIM(current_user_impression) <> ''
        )
    ''');
  }

  Future<void> _migrateToVersion74(Database database) async {
    if (!await _tableExists(database, 'board_posts') ||
        !await _tableExists(database, 'board_comments')) {
      await _createMindBoardSchema(database);
    }
    await _createMessageBoardV2Schema(database);
    if (!await _columnExists(database, 'board_comments', 'parent_comment_id')) {
      await database.execute(
        'ALTER TABLE board_comments ADD COLUMN parent_comment_id TEXT',
      );
    }
    for (final table in const ['board_posts', 'board_comments']) {
      if (!await _columnExists(database, table, 'generation_task_id')) {
        await database.execute(
          'ALTER TABLE $table ADD COLUMN generation_task_id TEXT',
        );
      }
      if (!await _columnExists(database, table, 'generation_kind')) {
        await database.execute(
          'ALTER TABLE $table ADD COLUMN generation_kind TEXT',
        );
      }
    }
    await _createMessageBoardV2Indexes(database);
  }

  Future<void> _migrateToVersion75(Database database) async {
    // 兼容曾由并行施工产生的 v74 数据库：先幂等补齐留言板 v2
    // 的表和基础字段，再追加租约字段与索引，避免升级中断。
    if (!await _tableExists(database, 'board_posts') ||
        !await _tableExists(database, 'board_comments')) {
      await _createMindBoardSchema(database);
    }
    await _createMessageBoardV2Schema(database);
    if (!await _columnExists(database, 'board_comments', 'parent_comment_id')) {
      await database.execute(
        'ALTER TABLE board_comments ADD COLUMN parent_comment_id TEXT',
      );
    }
    for (final table in const ['board_posts', 'board_comments']) {
      if (!await _columnExists(database, table, 'generation_task_id')) {
        await database.execute(
          'ALTER TABLE $table ADD COLUMN generation_task_id TEXT',
        );
      }
      if (!await _columnExists(database, table, 'generation_kind')) {
        await database.execute(
          'ALTER TABLE $table ADD COLUMN generation_kind TEXT',
        );
      }
    }
    if (!await _columnExists(database, 'board_tasks', 'lease_owner')) {
      await database.execute(
        'ALTER TABLE board_tasks ADD COLUMN lease_owner TEXT',
      );
    }
    if (!await _columnExists(database, 'board_tasks', 'lease_until')) {
      await database.execute(
        'ALTER TABLE board_tasks ADD COLUMN lease_until TEXT',
      );
    }
    await _createMessageBoardV2Indexes(database);
  }

  Future<void> _createMessageBoardV2Schema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS board_tasks (
        task_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        task_type TEXT NOT NULL CHECK (task_type IN (
          'auto_post', 'comment_user_post', 'reply_user_comment'
        )),
        source_post_id TEXT,
        source_comment_id TEXT,
        due_at TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN (
          'pending', 'running', 'retry_wait', 'succeeded', 'cancelled'
        )),
        dedupe_key TEXT NOT NULL UNIQUE,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT NOT NULL,
        last_error_code TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        lease_owner TEXT,
        lease_until TEXT,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (source_post_id) REFERENCES board_posts(post_id),
        FOREIGN KEY (source_comment_id) REFERENCES board_comments(comment_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_board_runtime (
        assistant_id TEXT PRIMARY KEY,
        last_auto_post_message_cursor TEXT,
        last_auto_post_at TEXT,
        pending_auto_task_id TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (pending_auto_task_id) REFERENCES board_tasks(task_id)
          ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _createMessageBoardV2Indexes(DatabaseExecutor database) async {
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_comments_parent
      ON board_comments(parent_comment_id)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_board_posts_generation_task
      ON board_posts(generation_task_id)
      WHERE generation_task_id IS NOT NULL
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_board_comments_generation_task
      ON board_comments(generation_task_id)
      WHERE generation_task_id IS NOT NULL
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_tasks_due
      ON board_tasks(status, next_attempt_at, due_at)
    ''');
    if (await _columnExists(database, 'board_tasks', 'lease_until')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_board_tasks_lease
        ON board_tasks(status, lease_until)
      ''');
    }
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_board_one_pending_auto
      ON board_tasks(assistant_id)
      WHERE task_type = 'auto_post'
        AND status IN ('pending', 'running', 'retry_wait')
    ''');
  }

  Future<void> _migrateToVersion76(Database database) async {
    if (!await _tableExists(database, 'assistant_heartbeat_settings')) {
      await _createHeartbeatSettingsSchema(database);
    }
    if (!await _tableExists(database, 'global_notes') ||
        !await _tableExists(database, 'calendar_events')) {
      await _createMindBoardSchema(database);
    }
    if (!await _columnExists(
      database,
      'assistant_heartbeat_settings',
      'calendar_enabled',
    )) {
      await database.execute('''
        ALTER TABLE assistant_heartbeat_settings
        ADD COLUMN calendar_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (calendar_enabled IN (0, 1))
      ''');
    }

    const noteColumns = <String, String>{
      'title': 'TEXT',
      'note_type':
          "TEXT NOT NULL DEFAULT 'text' CHECK (note_type IN ('text', 'checklist'))",
      'completion_state':
          "TEXT NOT NULL DEFAULT 'open' CHECK (completion_state IN ('open', 'completed'))",
      'completion_reason':
          "TEXT CHECK (completion_reason IS NULL OR completion_reason IN ('completed', 'cancelled', 'expired'))",
      'completed_at': 'TEXT',
      'pinned': 'INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1))',
      'palette_key': 'INTEGER NOT NULL DEFAULT 0',
      'origin_conversation_id': 'TEXT',
      'updated_at': "TEXT NOT NULL DEFAULT ''",
    };
    for (final entry in noteColumns.entries) {
      if (!await _columnExists(database, 'global_notes', entry.key)) {
        await database.execute(
          'ALTER TABLE global_notes ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }

    const eventColumns = <String, String>{
      'title': "TEXT NOT NULL DEFAULT ''",
      'notes': 'TEXT',
      'start_at': "TEXT NOT NULL DEFAULT ''",
      'end_at': 'TEXT',
      'is_all_day': 'INTEGER NOT NULL DEFAULT 0 CHECK (is_all_day IN (0, 1))',
      'recurrence_kind':
          "TEXT NOT NULL DEFAULT 'none' CHECK (recurrence_kind IN ('none', 'daily', 'weekly', 'monthly', 'yearly'))",
      'recurrence_interval':
          'INTEGER NOT NULL DEFAULT 1 CHECK (recurrence_interval > 0)',
      'recurrence_weekdays': 'TEXT',
      'recurrence_until': 'TEXT',
      'custom_advance_minutes':
          'INTEGER CHECK (custom_advance_minutes IS NULL OR custom_advance_minutes >= 0)',
      'origin_conversation_id': 'TEXT',
      'updated_at': "TEXT NOT NULL DEFAULT ''",
    };
    for (final entry in eventColumns.entries) {
      if (!await _columnExists(database, 'calendar_events', entry.key)) {
        await database.execute(
          'ALTER TABLE calendar_events ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }

    await _createStickyCalendarV74Tables(database);

    // 旧软删除纸条按新硬删除规则清理，同时移除其可读连续性派生记录。
    if (await _tableExists(database, 'continuity_events')) {
      await database.execute('''
        DELETE FROM continuity_events
        WHERE object_type = 'note'
          AND object_id IN (SELECT id FROM global_notes WHERE status = 'deleted')
      ''');
    }
    await database.execute("DELETE FROM global_notes WHERE status = 'deleted'");
    await database.execute('''
      UPDATE global_notes
      SET updated_at = CASE WHEN updated_at = '' THEN created_at ELSE updated_at END,
          palette_key = ABS(
            LENGTH(id) * 31 +
            COALESCE(UNICODE(SUBSTR(id, 1, 1)), 0) +
            COALESCE(UNICODE(SUBSTR(id, -1, 1)), 0)
          ) % 6
    ''');
    await database.execute(
      '''
      UPDATE global_notes
      SET completion_state = 'completed',
          completion_reason = 'expired',
          completed_at = COALESCE(completed_at, expires_at, updated_at),
          status = 'expired'
      WHERE status = 'expired'
         OR (expires_at IS NOT NULL AND expires_at <= ?)
    ''',
      [DateTime.now().toUtc().toIso8601String()],
    );

    await database.execute('''
      UPDATE calendar_events
      SET title = CASE WHEN title = '' THEN content ELSE title END,
          start_at = CASE WHEN start_at = '' THEN event_time ELSE start_at END,
          updated_at = CASE WHEN updated_at = '' THEN created_at ELSE updated_at END
    ''');
  }

  Future<void> _migrateToVersion77(Database database) async {
    if (!await _tableExists(database, 'board_posts')) {
      await _createMindBoardSchema(database);
    }
    await _createBoardPostLikesSchema(database);
  }

  Future<void> _migrateToVersion78(Database database) async {
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'failure_hint')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN failure_hint TEXT',
      );
    }
    await _createConversationReadStateSchema(database);
    if (await _tableExists(database, 'conversations') &&
        await _tableExists(database, 'messages')) {
      await database.execute('''
        INSERT OR IGNORE INTO conversation_read_state (conversation_id, last_read_at)
        SELECT c.id, COALESCE(
          (SELECT MAX(m.created_at) FROM messages m
           WHERE m.conversation_id = c.id),
          c.created_at
        )
        FROM conversations c
      ''');
    }
  }

  Future<void> _migrateToVersion79(Database database) async {
    if (await _tableExists(database, 'messages') &&
        !await _columnExists(database, 'messages', 'tool_used')) {
      await database.execute(
        'ALTER TABLE messages ADD COLUMN tool_used INTEGER NOT NULL DEFAULT 0 '
        'CHECK (tool_used IN (0, 1))',
      );
    }
    if (await _tableExists(database, 'answer_versions') &&
        !await _columnExists(database, 'answer_versions', 'tool_used')) {
      await database.execute(
        'ALTER TABLE answer_versions ADD COLUMN tool_used INTEGER NOT NULL '
        'DEFAULT 0 CHECK (tool_used IN (0, 1))',
      );
    }
  }

  Future<void> _migrateToVersion80(Database database) async {
    if (await _tableExists(database, 'calendar_events') &&
        !await _columnExists(database, 'calendar_events', 'category_id')) {
      await database.execute(
        "ALTER TABLE calendar_events ADD COLUMN category_id TEXT NOT NULL DEFAULT 'daily'",
      );
    }
    if (await _tableExists(database, 'calendar_event_exceptions') &&
        !await _columnExists(
          database,
          'calendar_event_exceptions',
          'override_category',
        )) {
      await database.execute(
        'ALTER TABLE calendar_event_exceptions ADD COLUMN override_category TEXT',
      );
    }
    await _createCalendarCreatorColorsSchema(database);
  }

  Future<void> _migrateToVersion81(Database database) async {
    if (!await _tableExists(database, 'global_notes')) {
      await _createMindBoardSchema(database);
    }
    const columns = <String, String>{
      'tape_style': 'INTEGER NOT NULL DEFAULT 0',
      'wall_order': 'INTEGER NOT NULL DEFAULT 0',
      'is_displayed':
          'INTEGER NOT NULL DEFAULT 0 CHECK (is_displayed IN (0, 1))',
    };
    for (final entry in columns.entries) {
      if (!await _columnExists(database, 'global_notes', entry.key)) {
        await database.execute(
          'ALTER TABLE global_notes ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
    await database.execute('''
      UPDATE global_notes
      SET tape_style = ABS(
            LENGTH(id) + COALESCE(UNICODE(SUBSTR(id, -1, 1)), 0)
          ) % 2,
          wall_order = -rowid
      WHERE wall_order = 0
    ''');
    if (await _columnExists(database, 'global_notes', 'is_displayed')) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_global_notes_single_displayed
        ON global_notes(is_displayed)
        WHERE is_displayed = 1
      ''');
    }
  }

  Future<void> _migrateToVersion82(Database database) async {
    await _createGroupChatSchema(database);
  }

  Future<void> _migrateToVersion83(Database database) async {
    if (!await _tableExists(database, 'memory_group_evidence') ||
        !await _tableExists(database, 'group_memory_organize_message_state') ||
        !await _tableExists(database, 'memory_items') ||
        !await _tableExists(database, 'memory_evidence')) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      await txn.update('memory_group_evidence', {
        'invalidated': 1,
        'invalidated_reason': 'legacy_direct_group_memory_v82',
        'invalidated_at': now,
      }, where: "rebuild_run_id = ''");
      await txn.rawUpdate(
        '''
        UPDATE memory_items
        SET status = 'archived', updated_at = ?
        WHERE memory_id IN (
          SELECT memory_id FROM memory_group_evidence
          WHERE invalidated_reason = 'legacy_direct_group_memory_v82'
        )
        AND NOT EXISTS (
          SELECT 1 FROM memory_evidence ordinary
          WHERE ordinary.memory_id = memory_items.memory_id
            AND ordinary.invalidated = 0
        )
        AND NOT EXISTS (
          SELECT 1 FROM memory_group_evidence grouped
          WHERE grouped.memory_id = memory_items.memory_id
            AND grouped.invalidated = 0
        )
        ''',
        [now],
      );
      await txn.rawUpdate(
        '''
        UPDATE group_memory_organize_message_state
        SET status = CASE WHEN EXISTS (
              SELECT 1 FROM group_messages message
              WHERE message.message_id = group_message_id
                AND message.is_deleted = 0
                AND (message.visible = 1 OR message.context_visible = 1)
                AND TRIM(message.content) != ''
                AND (
                  message.speaker_type != 'assistant'
                  OR (
                    message.answer_status = 'completed'
                    AND message.upstream_status = 'current'
                  )
                )
            ) THEN 'waiting_stability' ELSE 'discarded' END,
            stable_after = ?, claimed_run_id = NULL, processed_at = NULL,
            updated_at = ?
        WHERE group_message_id IN (
          SELECT group_message_id FROM memory_group_evidence
          WHERE invalidated_reason = 'legacy_direct_group_memory_v82'
        )
        ''',
        [now, now],
      );
    });
  }

  Future<void> _migrateToVersion84(Database database) async {
    if (!await _tableExists(database, 'group_answer_versions') ||
        !await _tableExists(database, 'group_messages')) {
      return;
    }
    await database.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE group_answer_versions
        SET branch_active = CASE WHEN answer_version_id = (
          SELECT message.current_answer_version_id
          FROM group_messages message
          WHERE message.message_id = group_answer_versions.message_id
        ) THEN 1 ELSE 0 END
      ''');
      await txn.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_group_answer_versions_one_active
        ON group_answer_versions(message_id)
        WHERE branch_active = 1
      ''');
    });
  }

  /// 每助手唯一世界的数据底座。迁移保持幂等，以兼容并行分支数据库。
  Future<void> _migrateToVersion85(Database database) async {
    await _createWorldSchema(database);
    if (await _tableExists(database, 'memory_items') &&
        !await _columnExists(database, 'memory_items', 'display_origin')) {
      await database.execute(
        "ALTER TABLE memory_items ADD COLUMN display_origin TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<void> _migrateToVersion86(Database database) async {
    if (await _tableExists(database, 'answer_versions') &&
        !await _columnExists(database, 'answer_versions', 'reasoning')) {
      await database.execute(
        'ALTER TABLE answer_versions ADD COLUMN reasoning TEXT',
      );
    }
  }

  Future<void> _migrateToVersion87(Database database) async {
    await _createSingleChatAnswerBranchSchema(database);
    if (!await _tableExists(database, 'answer_versions') ||
        !await _tableExists(database, 'messages')) {
      return;
    }
    await database.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE answer_versions
        SET branch_active = CASE WHEN answer_version_id = (
          SELECT message.current_answer_version_id
          FROM messages message
          WHERE message.id = answer_versions.message_id
        ) THEN 1 ELSE 0 END
      ''');
      await txn.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_answer_versions_one_active
        ON answer_versions(message_id)
        WHERE branch_active = 1
      ''');
    });
  }

  Future<void> _migrateToVersion88(Database database) async {
    await _createGroupChatExtensionSchema(database);
    if (await _tableExists(database, 'group_rooms')) {
      await database.update('group_rooms', {
        'manual_mention_enabled': 1,
      }, where: "status = 'active' AND manual_mention_enabled != 1");
    }
  }

  Future<void> _migrateToVersion89(Database database) async {
    if (!await _tableExists(database, 'memory_rebuild_jobs')) {
      await _createMemoryOrganizeQueueSchema(database);
    }
    if (!await _columnExists(
      database,
      'memory_rebuild_jobs',
      'desired_state',
    )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_jobs
        ADD COLUMN desired_state TEXT NOT NULL DEFAULT 'running'
      ''');
    }
    await database.rawUpdate('''
      UPDATE memory_rebuild_jobs
      SET desired_state = 'paused'
      WHERE status IN ('pause_requested', 'paused')
    ''');
  }

  Future<void> _migrateToVersion90(Database database) async {
    if (await _tableExists(database, 'messages')) {
      final columns = await database.rawQuery('PRAGMA table_info(messages)');
      if (!columns.any((column) => column['name'] == 'elapsed_ms')) {
        await database.execute(
          'ALTER TABLE messages ADD COLUMN elapsed_ms INTEGER',
        );
      }
    }
    if (await _tableExists(database, 'answer_versions')) {
      final columns = await database.rawQuery(
        'PRAGMA table_info(answer_versions)',
      );
      if (!columns.any((column) => column['name'] == 'elapsed_ms')) {
        await database.execute(
          'ALTER TABLE answer_versions ADD COLUMN elapsed_ms INTEGER',
        );
      }
    }
  }

  Future<void> _migrateToVersion91(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS feature_read_state (
        feature_key TEXT PRIMARY KEY
          CHECK (feature_key IN ('sticky_note', 'message_board', 'calendar')),
        last_read_at TEXT NOT NULL
      )
    ''');

    // v55 起已经预留通话轮次与隐藏消息的关联字段，但旧实现未写入。
    // 用当时确定性的时间戳和内容补齐可唯一确认的旧记录，供完整删除使用。
    if (await _tableExists(database, 'call_sessions') &&
        await _tableExists(database, 'call_turns') &&
        await _columnExists(database, 'call_turns', 'user_message_id') &&
        await _columnExists(database, 'call_turns', 'assistant_message_id') &&
        await _columnExists(database, 'call_turns', 'user_transcript') &&
        await _columnExists(database, 'call_turns', 'heard_assistant_text') &&
        await _tableExists(database, 'messages')) {
      final sessions = await database.query(
        'call_sessions',
        columns: const ['session_id', 'conversation_id', 'started_at'],
      );
      for (final session in sessions) {
        final startedAt = DateTime.tryParse(session['started_at']! as String);
        if (startedAt == null) continue;
        final turns = await database.query(
          'call_turns',
          where: 'session_id = ?',
          whereArgs: <Object?>[session['session_id']],
          orderBy: 'turn_index ASC',
        );
        for (final turn in turns) {
          final index = turn['turn_index']! as int;
          final updates = <String, Object?>{};
          final userText = (turn['user_transcript'] as String? ?? '').trim();
          if (turn['user_message_id'] == null && userText.isNotEmpty) {
            final content = index == 0 ? '【通话内容】\n$userText' : userText;
            final matches = await database.query(
              'messages',
              columns: const ['id'],
              where:
                  'conversation_id = ? AND role = ? AND content = ? '
                  'AND created_at = ? AND context_visible = 1',
              whereArgs: <Object?>[
                session['conversation_id'],
                'user',
                content,
                startedAt
                    .add(Duration(milliseconds: index * 2 + 1))
                    .toUtc()
                    .toIso8601String(),
              ],
            );
            if (matches.length == 1) {
              updates['user_message_id'] = matches[0]['id'];
            }
          }
          final assistantText = (turn['heard_assistant_text'] as String? ?? '')
              .trim();
          if (turn['assistant_message_id'] == null &&
              assistantText.isNotEmpty) {
            final matches = await database.query(
              'messages',
              columns: const ['id'],
              where:
                  'conversation_id = ? AND role = ? AND content = ? '
                  'AND created_at = ? AND context_visible = 1',
              whereArgs: <Object?>[
                session['conversation_id'],
                'assistant',
                assistantText,
                startedAt
                    .add(Duration(milliseconds: index * 2 + 2))
                    .toUtc()
                    .toIso8601String(),
              ],
            );
            if (matches.length == 1) {
              updates['assistant_message_id'] = matches[0]['id'];
            }
          }
          if (updates.isNotEmpty) {
            await database.update(
              'call_turns',
              updates,
              where: 'turn_id = ?',
              whereArgs: <Object?>[turn['turn_id']],
            );
          }
        }
      }
    }
  }

  Future<void> _migrateToVersion92(Database database) async {
    await _createConversationChangeStateSchema(database);
    await _migrateTokenUsageRecordsToVersion92(database);
    if (await _tableExists(database, 'conversations') &&
        await _tableExists(database, 'assistants')) {
      await database.execute('''
        UPDATE conversations
        SET title = (
          SELECT a.name FROM assistants a WHERE a.id = conversations.assistant_id
        )
        WHERE kind = 'single'
          AND title = '与 ' || (
            SELECT a.name FROM assistants a WHERE a.id = conversations.assistant_id
          ) || ' 的对话'
      ''');
    }
  }

  Future<void> _createWorldOversizedSourceRecoverySchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_oversized_source_recovery (
        assistant_id TEXT PRIMARY KEY,
        source_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createWorldOrganizationDraftSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_organization_drafts (
        run_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        result_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'applied', 'discarded')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        applied_at TEXT,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_world_organization_drafts_assistant
      ON world_organization_drafts(assistant_id, status, updated_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_organization_chunks (
        run_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        candidate_text TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (run_id, chunk_index),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createConversationChangeStateSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS conversation_change_state (
        conversation_id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _migrateTokenUsageRecordsToVersion92(Database database) async {
    if (!await _tableExists(database, 'token_usage_records')) {
      await _createTokenUsageRecordsV92(database);
      return;
    }
    await database.transaction((transaction) async {
      await transaction.execute(
        'DROP INDEX IF EXISTS idx_token_usage_assistant_time',
      );
      await transaction.execute(
        'DROP INDEX IF EXISTS idx_token_usage_task_type',
      );
      await transaction.execute(
        'ALTER TABLE token_usage_records RENAME TO token_usage_records_v91',
      );
      await _createTokenUsageRecordsV92(transaction);
      await transaction.execute('''
        INSERT INTO token_usage_records (
          record_id, assistant_id, task_type, task_subtype,
          input_tokens, output_tokens, total_tokens,
          request_id, conversation_id, message_id, job_id, created_at
        )
        SELECT
          record_id, assistant_id, task_type, task_subtype,
          input_tokens, output_tokens, total_tokens,
          request_id, conversation_id, message_id, job_id, created_at
        FROM token_usage_records_v91
      ''');
      await transaction.execute('DROP TABLE token_usage_records_v91');
    });
  }

  Future<void> _createTokenUsageRecordsV92(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS token_usage_records (
        record_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        task_type TEXT NOT NULL,
        task_subtype TEXT,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        request_count INTEGER NOT NULL DEFAULT 1,
        model_service_id TEXT,
        model TEXT,
        protocol_type TEXT,
        is_estimated INTEGER NOT NULL DEFAULT 0 CHECK (is_estimated IN (0, 1)),
        request_id TEXT,
        conversation_id TEXT,
        message_id TEXT,
        job_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_token_usage_assistant_time
      ON token_usage_records(assistant_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_token_usage_task_type
      ON token_usage_records(task_type, created_at DESC)
    ''');
  }

  Future<void> _createGroupChatExtensionSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_message_attachments (
        message_id TEXT NOT NULL,
        attachment_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        original_name TEXT NOT NULL,
        source_path TEXT,
        source_url TEXT,
        status TEXT NOT NULL,
        PRIMARY KEY (message_id, position),
        FOREIGN KEY (message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE,
        FOREIGN KEY (attachment_id) REFERENCES attachments(id)
          ON DELETE RESTRICT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_message_attachments_message
      ON group_message_attachments(message_id, position)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_message_voice_assets (
        asset_id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        answer_version_id TEXT,
        assistant_id TEXT,
        segment_index INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL CHECK (kind IN (
          'user_recording', 'assistant_reply', 'manual_readout'
        )),
        relative_path TEXT NOT NULL DEFAULT '',
        audio_format TEXT NOT NULL DEFAULT 'wav',
        duration_ms INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'generating'
          CHECK (state IN ('generating', 'ready', 'failed', 'invalidated')),
        source_text_hash TEXT NOT NULL DEFAULT '',
        director_revision INTEGER NOT NULL DEFAULT 0,
        service_revision INTEGER NOT NULL DEFAULT 0,
        voice_id TEXT NOT NULL DEFAULT '',
        model_id TEXT NOT NULL DEFAULT '',
        transcript TEXT,
        transcript_state TEXT NOT NULL DEFAULT 'none'
          CHECK (transcript_state IN ('none', 'recognizing', 'ready', 'failed')),
        transcript_visible INTEGER NOT NULL DEFAULT 0
          CHECK (transcript_visible IN (0, 1)),
        display_mode TEXT NOT NULL DEFAULT 'voice_text'
          CHECK (display_mode IN ('voice', 'voice_text')),
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE,
        FOREIGN KEY (answer_version_id)
          REFERENCES group_answer_versions(answer_version_id) ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_voice_message_version_segment
      ON group_message_voice_assets(
        message_id, answer_version_id, segment_index, state
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_channel_switch_anchors (
        assistant_id TEXT NOT NULL,
        room_id TEXT NOT NULL,
        direction TEXT NOT NULL CHECK (
          direction IN ('private_to_group', 'group_to_private')
        ),
        source_cutoff TEXT NOT NULL,
        target_anchor TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, room_id, direction),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createSingleChatAnswerBranchSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_answer_branch_messages (
        root_message_id TEXT NOT NULL,
        answer_version_id TEXT NOT NULL,
        downstream_message_id TEXT NOT NULL,
        visible INTEGER NOT NULL CHECK (visible IN (0, 1)),
        context_visible INTEGER NOT NULL CHECK (context_visible IN (0, 1)),
        PRIMARY KEY (root_message_id, answer_version_id, downstream_message_id),
        FOREIGN KEY (root_message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (answer_version_id) REFERENCES answer_versions(answer_version_id)
          ON DELETE CASCADE,
        FOREIGN KEY (downstream_message_id) REFERENCES messages(id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_answer_branch_restore
      ON chat_answer_branch_messages(root_message_id, answer_version_id)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_answer_version_segments (
        answer_version_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL,
        content TEXT NOT NULL,
        PRIMARY KEY (answer_version_id, segment_index),
        FOREIGN KEY (answer_version_id) REFERENCES answer_versions(answer_version_id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createWorldSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_worlds (
        assistant_id TEXT PRIMARY KEY,
        world_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (world_enabled IN (0, 1)),
        publication_status TEXT NOT NULL DEFAULT 'empty'
          CHECK (publication_status IN ('empty', 'published', 'needs_review')),
        visible_world_setting TEXT NOT NULL DEFAULT '',
        world_core TEXT NOT NULL DEFAULT '',
        world_rules TEXT NOT NULL DEFAULT '',
        assistant_identity_mode TEXT NOT NULL DEFAULT 'unset'
          CHECK (assistant_identity_mode IN ('unset', 'none', 'narrator', 'custom')),
        assistant_identity_custom TEXT NOT NULL DEFAULT '',
        user_identity_mode TEXT NOT NULL DEFAULT 'unset'
          CHECK (user_identity_mode IN ('unset', 'none', 'custom')),
        user_identity_custom TEXT NOT NULL DEFAULT '',
        story_start_mode TEXT NOT NULL DEFAULT 'unset'
          CHECK (story_start_mode IN ('unset', 'start', 'end', 'custom')),
        story_start_custom TEXT NOT NULL DEFAULT '',
        assistant_setting TEXT NOT NULL DEFAULT '',
        assistant_setting_enabled INTEGER NOT NULL DEFAULT 1
          CHECK (assistant_setting_enabled IN (0, 1)),
        user_setting TEXT NOT NULL DEFAULT '',
        user_setting_enabled INTEGER NOT NULL DEFAULT 1
          CHECK (user_setting_enabled IN (0, 1)),
        visible_setting_user_edited INTEGER NOT NULL DEFAULT 0
          CHECK (visible_setting_user_edited IN (0, 1)),
        source_hash TEXT NOT NULL DEFAULT '',
        core_source_hash TEXT NOT NULL DEFAULT '',
        organize_revision INTEGER NOT NULL DEFAULT 0,
        last_generation_run_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_source_materials (
        material_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        source_type TEXT NOT NULL CHECK (source_type IN ('manual', 'file')),
        original_file_name TEXT NOT NULL DEFAULT '',
        source_format TEXT NOT NULL DEFAULT 'text',
        original_file_path TEXT NOT NULL DEFAULT '',
        normalized_text_path TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        workspace_status TEXT NOT NULL DEFAULT 'staged'
          CHECK (workspace_status IN (
            'staged', 'organizing', 'interrupted', 'review_ready', 'applied'
          )),
        last_job_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_world_source_one_active
      ON world_source_materials(assistant_id) WHERE is_active = 1
    ''');
    await _createWorldOversizedSourceRecoverySchema(database);
    await _createWorldOrganizationDraftSchema(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_characters (
        character_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        normalized_key TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        aliases_json TEXT NOT NULL DEFAULT '[]',
        origin_type TEXT NOT NULL CHECK (origin_type IN ('generated', 'manual')),
        user_edited INTEGER NOT NULL DEFAULT 0 CHECK (user_edited IN (0, 1)),
        generation_run_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_world_characters_assistant
      ON world_characters(assistant_id, normalized_key)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_spaces (
        space_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        normalized_key TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        origin_type TEXT NOT NULL CHECK (origin_type IN ('generated', 'manual')),
        user_edited INTEGER NOT NULL DEFAULT 0 CHECK (user_edited IN (0, 1)),
        generation_run_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_world_spaces_assistant
      ON world_spaces(assistant_id, normalized_key)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_schedules (
        schedule_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        normalized_key TEXT NOT NULL,
        start_date TEXT,
        end_date TEXT,
        weekdays_json TEXT NOT NULL DEFAULT '[]',
        start_time TEXT,
        end_time TEXT,
        has_fixed_time INTEGER NOT NULL DEFAULT 1 CHECK (has_fixed_time IN (0, 1)),
        spans_midnight INTEGER NOT NULL DEFAULT 0 CHECK (spans_midnight IN (0, 1)),
        recurrence_rule TEXT NOT NULL DEFAULT 'none',
        context_mode TEXT NOT NULL DEFAULT 'auto'
          CHECK (context_mode IN ('auto', 'topic', 'always')),
        space_id TEXT,
        origin_type TEXT NOT NULL CHECK (origin_type IN ('generated', 'manual')),
        user_edited INTEGER NOT NULL DEFAULT 0 CHECK (user_edited IN (0, 1)),
        generation_run_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (space_id) REFERENCES world_spaces(space_id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_world_schedules_assistant
      ON world_schedules(assistant_id, normalized_key)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS world_lore_items (
        lore_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        lore_type TEXT NOT NULL,
        name TEXT NOT NULL,
        normalized_key TEXT NOT NULL,
        aliases_json TEXT NOT NULL DEFAULT '[]',
        content TEXT NOT NULL,
        story_stage TEXT NOT NULL DEFAULT '',
        knowledge_scope TEXT NOT NULL DEFAULT '',
        source_chunk TEXT NOT NULL DEFAULT '',
        organize_revision INTEGER NOT NULL DEFAULT 0,
        origin_type TEXT NOT NULL DEFAULT 'generated'
          CHECK (origin_type IN ('generated', 'manual', 'projection')),
        user_edited INTEGER NOT NULL DEFAULT 0 CHECK (user_edited IN (0, 1)),
        generation_run_id TEXT NOT NULL DEFAULT '',
        searchable INTEGER NOT NULL DEFAULT 1 CHECK (searchable IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_world_lore_lookup
      ON world_lore_items(assistant_id, searchable, normalized_key)
    ''');
    if (await _tableExists(database, 'memory_items') &&
        !await _columnExists(database, 'memory_items', 'display_origin')) {
      await database.execute(
        "ALTER TABLE memory_items ADD COLUMN display_origin TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<void> _createGroupChatSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_rooms (
        room_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        room_instruction TEXT NOT NULL DEFAULT '',
        sequential_enabled INTEGER NOT NULL DEFAULT 1
          CHECK (sequential_enabled IN (0, 1)),
        manual_mention_enabled INTEGER NOT NULL DEFAULT 1
          CHECK (manual_mention_enabled IN (0, 1)),
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'archived', 'deleted')),
        next_sequence INTEGER NOT NULL DEFAULT 1 CHECK (next_sequence >= 1),
        draft_text TEXT NOT NULL DEFAULT '',
        draft_updated_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (sequential_enabled = 1 OR manual_mention_enabled = 1)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_rooms_status_updated
      ON group_rooms(status, updated_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_participants (
        room_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        speak_order INTEGER NOT NULL CHECK (speak_order >= 0),
        created_at TEXT NOT NULL,
        PRIMARY KEY (room_id, assistant_id),
        UNIQUE (room_id, speak_order),
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_participants_assistant
      ON group_participants(assistant_id, room_id)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_messages (
        message_id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        sequence INTEGER NOT NULL CHECK (sequence >= 1),
        speaker_type TEXT NOT NULL
          CHECK (speaker_type IN ('user', 'assistant', 'system_event')),
        speaker_assistant_id TEXT,
        content TEXT NOT NULL DEFAULT '',
        reasoning TEXT,
        reply_to_message_id TEXT,
        root_trigger_message_id TEXT,
        round_position INTEGER,
        request_type TEXT NOT NULL DEFAULT 'system'
          CHECK (request_type IN (
            'sequential', 'manual_mention', 'system', 'future_handoff'
          )),
        revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
        current_message_version_id TEXT,
        current_answer_version_id TEXT,
        current_answer_version_number INTEGER,
        answer_version_count INTEGER NOT NULL DEFAULT 0
          CHECK (answer_version_count >= 0),
        answer_status TEXT CHECK (answer_status IS NULL OR answer_status IN (
          'queued', 'streaming', 'completed', 'failed', 'cancelled'
        )),
        failure_hint TEXT,
        tool_used INTEGER NOT NULL DEFAULT 0 CHECK (tool_used IN (0, 1)),
        visible INTEGER NOT NULL DEFAULT 1 CHECK (visible IN (0, 1)),
        context_visible INTEGER NOT NULL DEFAULT 1
          CHECK (context_visible IN (0, 1)),
        is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
        content_hash TEXT,
        upstream_revision_hash TEXT NOT NULL DEFAULT '',
        upstream_status TEXT NOT NULL DEFAULT 'current'
          CHECK (upstream_status IN ('current', 'stale', 'missing')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (room_id, sequence),
        CHECK (
          (speaker_type = 'assistant' AND speaker_assistant_id IS NOT NULL) OR
          (speaker_type != 'assistant' AND speaker_assistant_id IS NULL)
        ),
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE,
        FOREIGN KEY (room_id, speaker_assistant_id)
          REFERENCES group_participants(room_id, assistant_id),
        FOREIGN KEY (reply_to_message_id)
          REFERENCES group_messages(message_id) ON DELETE SET NULL,
        FOREIGN KEY (root_trigger_message_id)
          REFERENCES group_messages(message_id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_messages_room_sequence
      ON group_messages(room_id, sequence DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_messages_root
      ON group_messages(root_trigger_message_id, round_position)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_message_versions (
        version_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        version_number INTEGER NOT NULL CHECK (version_number >= 1),
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        edited_by TEXT,
        created_at TEXT NOT NULL,
        UNIQUE (message_id, version_number),
        FOREIGN KEY (message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_message_versions_message
      ON group_message_versions(message_id, version_number DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_answer_versions (
        answer_version_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        version_number INTEGER NOT NULL CHECK (version_number >= 1),
        content TEXT NOT NULL DEFAULT '',
        reasoning TEXT,
        answer_status TEXT NOT NULL DEFAULT 'queued'
          CHECK (answer_status IN (
            'queued', 'streaming', 'completed', 'failed', 'cancelled'
          )),
        failure_hint TEXT,
        prompt_tokens INTEGER,
        completion_tokens INTEGER,
        tool_used INTEGER NOT NULL DEFAULT 0 CHECK (tool_used IN (0, 1)),
        upstream_revision_hash TEXT NOT NULL DEFAULT '',
        context_cutoff_sequence INTEGER NOT NULL DEFAULT 0,
        branch_active INTEGER NOT NULL DEFAULT 1
          CHECK (branch_active IN (0, 1)),
        created_at TEXT NOT NULL,
        completed_at TEXT,
        UNIQUE (message_id, version_number),
        FOREIGN KEY (message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_answer_versions_message
      ON group_answer_versions(message_id, version_number DESC)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_group_answer_versions_one_active
      ON group_answer_versions(message_id)
      WHERE branch_active = 1
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_message_segments (
        message_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL CHECK (segment_index >= 0),
        content TEXT NOT NULL,
        PRIMARY KEY (message_id, segment_index),
        FOREIGN KEY (message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_rounds (
        round_id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        root_trigger_message_id TEXT,
        trigger_message_version_id TEXT,
        request_type TEXT NOT NULL
          CHECK (request_type IN (
            'sequential', 'manual_mention', 'system', 'future_handoff'
          )),
        branch_parent_round_id TEXT,
        branch_active INTEGER NOT NULL DEFAULT 1
          CHECK (branch_active IN (0, 1)),
        participant_order_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued'
          CHECK (status IN (
            'queued', 'running', 'completed', 'partial_failed',
            'cancel_requested', 'cancelled', 'failed'
          )),
        active_job_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE,
        FOREIGN KEY (root_trigger_message_id)
          REFERENCES group_messages(message_id) ON DELETE SET NULL,
        FOREIGN KEY (trigger_message_version_id)
          REFERENCES group_message_versions(version_id) ON DELETE SET NULL,
        FOREIGN KEY (branch_parent_round_id)
          REFERENCES group_rounds(round_id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_rounds_room_status
      ON group_rounds(room_id, status, created_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_round_steps (
        round_id TEXT NOT NULL,
        position INTEGER NOT NULL CHECK (position >= 0),
        assistant_id TEXT NOT NULL,
        logical_message_id TEXT NOT NULL,
        job_request_id TEXT,
        status TEXT NOT NULL DEFAULT 'queued'
          CHECK (status IN (
            'queued', 'running', 'completed', 'failed', 'cancelled',
            'skipped_unavailable'
          )),
        error_code TEXT,
        started_at TEXT,
        completed_at TEXT,
        PRIMARY KEY (round_id, position),
        UNIQUE (round_id, assistant_id),
        FOREIGN KEY (round_id) REFERENCES group_rounds(round_id) ON DELETE CASCADE,
        FOREIGN KEY (logical_message_id)
          REFERENCES group_messages(message_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_round_steps_status
      ON group_round_steps(round_id, status, position)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_room_read_state (
        room_id TEXT PRIMARY KEY,
        last_read_sequence INTEGER NOT NULL DEFAULT 0,
        last_read_at TEXT NOT NULL,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_channel_continuity (
        assistant_id TEXT PRIMARY KEY,
        last_channel_type TEXT NOT NULL DEFAULT 'private'
          CHECK (last_channel_type IN ('private', 'group')),
        last_group_room_id TEXT,
        last_left_group_at TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (last_group_room_id) REFERENCES group_rooms(room_id)
          ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_memory_organize_message_state (
        assistant_id TEXT NOT NULL,
        group_message_id TEXT NOT NULL,
        room_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'waiting_stability'
          CHECK (status IN (
            'waiting_stability', 'pending', 'processing', 'processed',
            'discarded', 'retryable_failed'
          )),
        stable_after TEXT NOT NULL,
        observed_revision_key TEXT NOT NULL,
        observed_content_hash TEXT NOT NULL DEFAULT '',
        claimed_run_id TEXT,
        processed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, group_message_id),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE,
        FOREIGN KEY (claimed_run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_memory_organize_claim
      ON group_memory_organize_message_state(
        assistant_id, status, stable_after, room_id
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_group_scope_messages (
        run_id TEXT NOT NULL,
        frozen_order INTEGER NOT NULL,
        group_message_id TEXT NOT NULL,
        room_id TEXT NOT NULL,
        block_id TEXT NOT NULL DEFAULT '',
        snapshot_revision_key TEXT NOT NULL DEFAULT '',
        snapshot_content_hash TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, frozen_order),
        UNIQUE (run_id, group_message_id),
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE RESTRICT,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_group_evidence (
        evidence_id TEXT PRIMARY KEY,
        memory_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        group_message_id TEXT NOT NULL,
        room_id TEXT NOT NULL,
        type TEXT NOT NULL
          CHECK (type IN ('explicit_fact', 'weak_signal', 'counter_example')),
        strength REAL NOT NULL CHECK (strength >= 0 AND strength <= 1),
        content TEXT NOT NULL,
        source_role TEXT NOT NULL,
        speaker_relation TEXT NOT NULL
          CHECK (speaker_relation IN (
            'user', 'current_assistant', 'other_assistant'
          )),
        source_message_time TEXT,
        processed_order INTEGER NOT NULL DEFAULT 0,
        rebuild_run_id TEXT NOT NULL DEFAULT '',
        message_version_id TEXT,
        answer_version_id TEXT,
        revision_key TEXT,
        source_content_hash TEXT,
        invalidated INTEGER NOT NULL DEFAULT 0
          CHECK (invalidated IN (0, 1)),
        invalidated_reason TEXT,
        invalidated_at TEXT,
        created_at TEXT NOT NULL,
        UNIQUE (memory_id, assistant_id, group_message_id, type),
        FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE RESTRICT,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_group_evidence_source
      ON memory_group_evidence(assistant_id, group_message_id, invalidated)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_group_recheck_tasks (
        task_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        memory_id TEXT NOT NULL,
        group_message_id TEXT NOT NULL,
        expected_version_id TEXT NOT NULL,
        change_type TEXT NOT NULL
          CHECK (change_type IN ('edit', 'delete', 'answer_version_switch')),
        not_before TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'waiting_stability'
          CHECK (status IN (
            'waiting_stability', 'processing', 'waiting_confirmation',
            'completed', 'superseded', 'cancelled', 'failed'
          )),
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        suggestion_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id)
          ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_group_recheck_status
      ON memory_group_recheck_tasks(assistant_id, status, not_before)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_group_message_coverage (
        assistant_id TEXT NOT NULL,
        group_message_id TEXT NOT NULL,
        run_id TEXT NOT NULL,
        processed_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, group_message_id),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE,
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_auto_journal_message_state (
        assistant_id TEXT NOT NULL,
        group_message_id TEXT NOT NULL,
        eligibility TEXT NOT NULL,
        reason TEXT,
        settled_by TEXT,
        settled_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, group_message_id),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_auto_journal_eligibility
      ON group_auto_journal_message_state(assistant_id, eligibility)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS journal_group_message_links (
        diary_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        group_message_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        usage_type TEXT NOT NULL DEFAULT 'auto',
        revision_key TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (diary_id, assistant_id, group_message_id),
        FOREIGN KEY (diary_id) REFERENCES diary_entries(diary_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_journal_group_links_message
      ON journal_group_message_links(assistant_id, group_message_id, diary_id)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS diary_group_origins (
        diary_id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (diary_id) REFERENCES diary_entries(diary_id)
          ON DELETE CASCADE,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_shared_facts (
        fact_id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        content TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'superseded', 'invalidated')),
        current_version INTEGER NOT NULL DEFAULT 1 CHECK (current_version >= 1),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (room_id) REFERENCES group_rooms(room_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_shared_facts_room_status
      ON group_shared_facts(room_id, status, updated_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_shared_fact_versions (
        fact_id TEXT NOT NULL,
        version INTEGER NOT NULL CHECK (version >= 1),
        content TEXT NOT NULL,
        source_revision_set_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (fact_id, version),
        FOREIGN KEY (fact_id) REFERENCES group_shared_facts(fact_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS group_shared_fact_evidence (
        fact_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        group_message_id TEXT NOT NULL,
        revision_key TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (fact_id, version, group_message_id),
        FOREIGN KEY (fact_id, version)
          REFERENCES group_shared_fact_versions(fact_id, version)
          ON DELETE CASCADE,
        FOREIGN KEY (group_message_id) REFERENCES group_messages(message_id)
          ON DELETE RESTRICT
      )
    ''');
  }

  Future<void> _createConversationReadStateSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS conversation_read_state (
        conversation_id TEXT PRIMARY KEY,
        last_read_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createBoardPostLikesSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS board_post_likes (
        post_id TEXT NOT NULL,
        actor_type TEXT NOT NULL
          CHECK (actor_type IN ('user', 'assistant')),
        actor_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, actor_type, actor_id),
        FOREIGN KEY (post_id) REFERENCES board_posts(post_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_post_likes_post
      ON board_post_likes(post_id, created_at)
    ''');
  }

  Future<void> _createToolConfirmationSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_confirmation_requests (
        request_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        source_kind TEXT NOT NULL CHECK (source_kind IN (
          'tool_authoring', 'device_action'
        )),
        tool_id TEXT NOT NULL,
        call_id TEXT NOT NULL,
        target_id TEXT NOT NULL,
        target_revision TEXT NOT NULL,
        arguments_digest TEXT NOT NULL,
        safe_arguments_json TEXT NOT NULL DEFAULT '{}',
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN (
          'pending', 'confirmed', 'cancelled', 'expired', 'executed', 'failed'
        )),
        message_id TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        confirmed_at TEXT,
        executed_at TEXT,
        result_summary TEXT,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
          ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_confirmation_scope
      ON tool_confirmation_requests(
        assistant_id, conversation_id, status, created_at DESC
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_tool_confirmation_pending_action
      ON tool_confirmation_requests(
        assistant_id, conversation_id, tool_id, target_id,
        target_revision, arguments_digest
      ) WHERE status = 'pending'
    ''');
  }

  Future<void> _createMyDevicesSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS device_bindings (
        device_id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        external_locator_ref TEXT NOT NULL DEFAULT '',
        device_fingerprint TEXT NOT NULL,
        display_name TEXT NOT NULL,
        local_alias TEXT NOT NULL DEFAULT '',
        room_alias TEXT NOT NULL DEFAULT '',
        source_display_name TEXT NOT NULL,
        source_kind TEXT NOT NULL CHECK (source_kind IN (
          'bluetooth', 'companion', 'home_assistant', 'adapter', 'app'
        )),
        mapped_package TEXT,
        mapped_app_display_name TEXT NOT NULL DEFAULT '',
        connection_state TEXT NOT NULL DEFAULT 'unknown' CHECK (
          connection_state IN (
            'online', 'offline', 'unknown', 'permission_required',
            'repair_required', 'unsupported'
          )
        ),
        capability_revision_id TEXT NOT NULL,
        last_verified_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (source_id) REFERENCES tool_sources(source_id)
          ON DELETE CASCADE,
        UNIQUE (source_id, device_fingerprint)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS device_capabilities (
        device_id TEXT NOT NULL,
        capability_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        can_read INTEGER NOT NULL DEFAULT 0 CHECK (can_read IN (0, 1)),
        can_control INTEGER NOT NULL DEFAULT 0 CHECK (can_control IN (0, 1)),
        risk_class TEXT NOT NULL DEFAULT 'unknown' CHECK (risk_class IN (
          'read', 'low', 'high', 'unknown'
        )),
        route_json TEXT NOT NULL DEFAULT '{}',
        revision_id TEXT NOT NULL,
        PRIMARY KEY (device_id, capability_id),
        FOREIGN KEY (device_id) REFERENCES device_bindings(device_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS device_capability_grants (
        assistant_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        capability_id TEXT NOT NULL,
        allow_read INTEGER NOT NULL DEFAULT 0 CHECK (allow_read IN (0, 1)),
        allow_control INTEGER NOT NULL DEFAULT 0 CHECK (allow_control IN (0, 1)),
        granted_revision_id TEXT NOT NULL,
        granted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, device_id, capability_id),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (device_id, capability_id)
          REFERENCES device_capabilities(device_id, capability_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_device_bindings_state
      ON device_bindings(connection_state, updated_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_device_grants_assistant
      ON device_capability_grants(assistant_id, device_id)
    ''');
  }

  Future<void> _createToolAuthoringSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_authoring_drafts (
        draft_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK (kind IN ('game', 'device', 'tool')),
        display_name TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'declarative'
          CHECK (source_type IN ('declarative', 'http', 'mcp')),
        target_display_name TEXT NOT NULL DEFAULT '',
        target_fingerprint TEXT NOT NULL DEFAULT '',
        spec_json TEXT NOT NULL DEFAULT '{}',
        secret_refs_json TEXT NOT NULL DEFAULT '[]',
        state TEXT NOT NULL DEFAULT 'draft' CHECK (state IN (
          'draft', 'validated', 'connection_tested', 'read_tested',
          'write_tested', 'published'
        )),
        validation_json TEXT NOT NULL DEFAULT '{}',
        last_test_summary TEXT NOT NULL DEFAULT '',
        private_channel_proven INTEGER NOT NULL DEFAULT 0
          CHECK (private_channel_proven IN (0, 1)),
        revision INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_authoring_revisions (
        revision_id TEXT PRIMARY KEY,
        draft_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        tool_source_id TEXT NOT NULL UNIQUE,
        version INTEGER NOT NULL,
        descriptor_json TEXT NOT NULL,
        spec_json TEXT NOT NULL,
        target_display_name TEXT NOT NULL DEFAULT '',
        target_fingerprint TEXT NOT NULL DEFAULT '',
        private_channel_proven INTEGER NOT NULL DEFAULT 0,
        published_at TEXT NOT NULL,
        FOREIGN KEY (draft_id) REFERENCES tool_authoring_drafts(draft_id)
          ON DELETE CASCADE,
        UNIQUE (draft_id, version)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_authoring_assistant_grants (
        revision_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
        confirmed_at TEXT NOT NULL,
        PRIMARY KEY (revision_id, assistant_id),
        FOREIGN KEY (revision_id) REFERENCES tool_authoring_revisions(revision_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_authoring_kind_state
      ON tool_authoring_drafts(kind, state, updated_at DESC)
    ''');
  }

  Future<void> _createConfigurationHelpSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS configuration_help_attachments (
        attachment_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL UNIQUE,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        feature_type TEXT NOT NULL,
        current_step TEXT,
        payload_json TEXT NOT NULL,
        user_note TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'sent'
          CHECK (status IN ('sent', 'failed')),
        created_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_configuration_help_scope
      ON configuration_help_attachments(
        assistant_id, conversation_id, created_at DESC
      )
    ''');
  }

  Future<void> _createTogetherWatchSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS shared_sessions (
        session_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        session_type TEXT NOT NULL CHECK (session_type IN (
          'together_watch', 'together_listen', 'together_play'
        )),
        status TEXT NOT NULL CHECK (status IN (
          'invited', 'active', 'ended', 'interrupted'
        )),
        playback_revision INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        ended_at TEXT,
        updated_at TEXT NOT NULL,
        stop_reason TEXT,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_session_one_open
      ON shared_sessions((1))
      WHERE status IN ('invited', 'active')
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_shared_session_scope
      ON shared_sessions(
        assistant_id, conversation_id, session_type, updated_at DESC
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_watch_sessions (
        session_id TEXT PRIMARY KEY,
        observation_interval_seconds INTEGER NOT NULL CHECK (
          observation_interval_seconds IN (5, 10, 20, 30)
        ),
        background_paused INTEGER NOT NULL DEFAULT 0
          CHECK (background_paused IN (0, 1)),
        FOREIGN KEY (session_id) REFERENCES shared_sessions(session_id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS shared_activities (
        activity_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        activity_type TEXT NOT NULL CHECK (activity_type IN (
          'together_watch', 'together_listen', 'together_play'
        )),
        status TEXT NOT NULL CHECK (status IN (
          'active', 'completed', 'interrupted'
        )),
        stop_reason TEXT,
        source_kind TEXT NOT NULL CHECK (source_kind IN (
          'local_document', 'cloud_document', 'direct_url',
          'own_player', 'third_party', 'third_party_game'
        )),
        source_label TEXT NOT NULL,
        source_fingerprint TEXT NOT NULL,
        source_locator TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
        start_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (start_position_ms >= 0),
        last_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (last_position_ms >= 0),
        furthest_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (furthest_position_ms >= 0),
        played_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (played_duration_ms >= 0),
        started_at TEXT NOT NULL,
        stopped_at TEXT,
        updated_at TEXT NOT NULL,
        summary TEXT,
        carryover_turns_remaining INTEGER NOT NULL DEFAULT 5
          CHECK (carryover_turns_remaining BETWEEN 0 AND 5),
        card_id TEXT UNIQUE,
        FOREIGN KEY (session_id) REFERENCES shared_sessions(session_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_activity_one_active_per_session
      ON shared_activities(session_id)
      WHERE status = 'active'
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_shared_activity_scope_time
      ON shared_activities(
        assistant_id, conversation_id, started_at DESC, activity_id DESC
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_shared_activity_source
      ON shared_activities(
        assistant_id, conversation_id, source_fingerprint, started_at DESC
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS shared_activity_messages (
        message_id TEXT PRIMARY KEY,
        chat_message_id TEXT,
        activity_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
        origin TEXT NOT NULL CHECK (origin IN (
          'user_input', 'automatic_observation', 'automatic_track_event'
        )),
        content TEXT NOT NULL,
        answer_status TEXT NOT NULL CHECK (answer_status IN (
          'completed', 'failed'
        )),
        visible INTEGER NOT NULL DEFAULT 1 CHECK (visible IN (0, 1)),
        created_at TEXT NOT NULL,
        FOREIGN KEY (activity_id) REFERENCES shared_activities(activity_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        ,FOREIGN KEY (chat_message_id) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_shared_activity_messages_context
      ON shared_activity_messages(activity_id, visible, answer_status, created_at)
    ''');
    if (await _columnExists(
      database,
      'shared_activity_messages',
      'chat_message_id',
    )) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_activity_messages_chat_message
        ON shared_activity_messages(chat_message_id)
        WHERE chat_message_id IS NOT NULL
      ''');
    }

    await database.execute('''
      CREATE TABLE IF NOT EXISTS shared_activity_cards (
        card_id TEXT PRIMARY KEY,
        activity_id TEXT NOT NULL UNIQUE,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN (
          'active', 'completed', 'interrupted'
        )),
        title TEXT NOT NULL,
        source_label TEXT NOT NULL,
        start_position_ms INTEGER NOT NULL DEFAULT 0,
        last_position_ms INTEGER NOT NULL DEFAULT 0,
        played_duration_ms INTEGER NOT NULL DEFAULT 0,
        summary TEXT,
        occurred_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (activity_id) REFERENCES shared_activities(activity_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_shared_activity_cards_timeline
      ON shared_activity_cards(conversation_id, occurred_at, card_id)
    ''');
  }

  Future<void> _createTogetherListenSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_listen_sessions (
        session_id TEXT PRIMARY KEY,
        source_mode TEXT CHECK (source_mode IN (
          'own_player', 'third_party'
        )),
        selected_source_key TEXT,
        available_actions TEXT NOT NULL DEFAULT '',
        capture_state TEXT NOT NULL DEFAULT 'off' CHECK (capture_state IN (
          'off', 'requested', 'active', 'unavailable', 'revoked'
        )),
        source_locator TEXT,
        FOREIGN KEY (session_id) REFERENCES shared_sessions(session_id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_listen_track_occurrences (
        occurrence_id TEXT PRIMARY KEY,
        activity_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal > 0),
        source_mode TEXT NOT NULL CHECK (source_mode IN (
          'own_player', 'third_party'
        )),
        source_package TEXT,
        track_fingerprint TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT,
        album TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
        start_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (start_position_ms >= 0),
        last_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (last_position_ms >= 0),
        furthest_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (furthest_position_ms >= 0),
        played_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (played_duration_ms >= 0),
        started_at TEXT NOT NULL,
        stopped_at TEXT,
        updated_at TEXT NOT NULL,
        stop_reason TEXT,
        FOREIGN KEY (activity_id) REFERENCES shared_activities(activity_id)
          ON DELETE CASCADE,
        UNIQUE (activity_id, ordinal)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_together_listen_track_activity
      ON together_listen_track_occurrences(
        activity_id, ordinal ASC, occurrence_id ASC
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_together_listen_track_fingerprint
      ON together_listen_track_occurrences(
        track_fingerprint, started_at DESC, occurrence_id DESC
      )
    ''');
  }

  Future<void> _createTogetherPlaySchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_play_sessions (
        session_id TEXT PRIMARY KEY,
        mode TEXT NOT NULL CHECK (mode IN (
          'assistant_play', 'same_screen', 'dual_account'
        )),
        control_state TEXT NOT NULL CHECK (control_state IN (
          'preparing', 'observing', 'assistant_control', 'user_control',
          'paused', 'needs_attention', 'ending', 'ended', 'interrupted'
        )),
        control_revision INTEGER NOT NULL DEFAULT 0 CHECK (control_revision >= 0),
        game_display_name TEXT NOT NULL,
        game_package_fingerprint TEXT NOT NULL,
        active_package_name TEXT,
        game_version_code INTEGER NOT NULL DEFAULT 0 CHECK (game_version_code >= 0),
        user_goal TEXT,
        compatibility_state TEXT NOT NULL DEFAULT 'pending',
        capture_state TEXT NOT NULL DEFAULT 'off',
        gesture_state TEXT NOT NULL DEFAULT 'off',
        overlay_state TEXT NOT NULL DEFAULT 'off',
        adapter_id TEXT,
        last_observed_at TEXT,
        last_action_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES shared_sessions(session_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_play_activities (
        activity_id TEXT PRIMARY KEY,
        mode TEXT NOT NULL CHECK (mode IN (
          'assistant_play', 'same_screen', 'dual_account'
        )),
        user_goal TEXT,
        game_display_name TEXT NOT NULL,
        game_package_fingerprint TEXT NOT NULL,
        assistant_control_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (assistant_control_duration_ms >= 0),
        user_control_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (user_control_duration_ms >= 0),
        verified_action_count INTEGER NOT NULL DEFAULT 0
          CHECK (verified_action_count >= 0),
        failed_action_count INTEGER NOT NULL DEFAULT 0
          CHECK (failed_action_count >= 0),
        takeover_count INTEGER NOT NULL DEFAULT 0 CHECK (takeover_count >= 0),
        adapter_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (activity_id) REFERENCES shared_activities(activity_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_play_events (
        event_id TEXT PRIMARY KEY,
        activity_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        event_type TEXT NOT NULL CHECK (event_type IN (
          'session_started', 'activity_started', 'paused', 'resumed',
          'control_to_user', 'control_to_assistant', 'target_app_left',
          'target_app_returned', 'action_verified', 'action_accepted',
          'action_failed',
          'safety_blocked', 'permission_lost', 'ended', 'interrupted'
        )),
        summary TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        FOREIGN KEY (activity_id) REFERENCES shared_activities(activity_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_together_play_events_activity
      ON together_play_events(activity_id, occurred_at, event_id)
    ''');
    await _createTogetherPlayFrozenMessagesSchema(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_play_compatibility (
        package_fingerprint TEXT NOT NULL,
        app_version_code INTEGER NOT NULL CHECK (app_version_code >= 0),
        device_api_fingerprint TEXT NOT NULL,
        capture_result TEXT NOT NULL,
        gesture_result TEXT NOT NULL,
        orientation_result TEXT NOT NULL,
        overlay_result TEXT NOT NULL,
        overall_state TEXT NOT NULL,
        checked_at TEXT NOT NULL,
        sanitized_note TEXT,
        PRIMARY KEY (
          package_fingerprint, app_version_code, device_api_fingerprint
        )
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_together_play_compatibility_checked
      ON together_play_compatibility(checked_at DESC)
    ''');
  }

  Future<void> _createTogetherPlayFrozenMessagesSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS together_play_frozen_messages (
        session_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        message_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
        content TEXT NOT NULL,
        answer_status TEXT,
        frozen_at TEXT NOT NULL,
        PRIMARY KEY (session_id, ordinal),
        UNIQUE (session_id, message_id),
        FOREIGN KEY (session_id) REFERENCES shared_sessions(session_id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createVoiceSchema(DatabaseExecutor database) async {
    if (await _tableExists(database, 'conversations')) {
      if (!await _columnExists(database, 'conversations', 'voice_reply_mode')) {
        await database.execute('''
          ALTER TABLE conversations ADD COLUMN voice_reply_mode TEXT NOT NULL
            DEFAULT 'text' CHECK (voice_reply_mode IN ('text', 'voice', 'voice_text'))
        ''');
      }
      if (!await _columnExists(database, 'conversations', 'voice_auto_play')) {
        await database.execute('''
          ALTER TABLE conversations ADD COLUMN voice_auto_play INTEGER NOT NULL
            DEFAULT 0 CHECK (voice_auto_play IN (0, 1))
        ''');
      }
      if (!await _columnExists(
        database,
        'conversations',
        'director_text_enabled',
      )) {
        await database.execute('''
          ALTER TABLE conversations ADD COLUMN director_text_enabled INTEGER
            NOT NULL DEFAULT 0 CHECK (director_text_enabled IN (0, 1))
        ''');
      }
      if (!await _columnExists(
        database,
        'conversations',
        'director_call_enabled',
      )) {
        await database.execute('''
          ALTER TABLE conversations ADD COLUMN director_call_enabled INTEGER
            NOT NULL DEFAULT 0 CHECK (director_call_enabled IN (0, 1))
        ''');
      }
    }

    if (await _tableExists(database, 'answer_versions')) {
      if (!await _columnExists(database, 'answer_versions', 'tts_script')) {
        await database.execute(
          'ALTER TABLE answer_versions ADD COLUMN tts_script TEXT',
        );
      }
      if (!await _columnExists(
        database,
        'answer_versions',
        'tts_script_status',
      )) {
        await database.execute('''
          ALTER TABLE answer_versions ADD COLUMN tts_script_status TEXT NOT NULL
            DEFAULT 'none' CHECK (tts_script_status IN ('none', 'pending', 'done', 'failed'))
        ''');
      }
      if (!await _columnExists(
        database,
        'answer_versions',
        'tts_script_revision',
      )) {
        await database.execute('''
          ALTER TABLE answer_versions ADD COLUMN tts_script_revision INTEGER
            NOT NULL DEFAULT 0
        ''');
      }
      if (!await _columnExists(
        database,
        'answer_versions',
        'tts_script_mode',
      )) {
        await database.execute(
          'ALTER TABLE answer_versions ADD COLUMN tts_script_mode TEXT',
        );
      }
      if (!await _columnExists(
        database,
        'answer_versions',
        'tts_script_source_hash',
      )) {
        await database.execute(
          'ALTER TABLE answer_versions ADD COLUMN tts_script_source_hash TEXT',
        );
      }
    }

    await database.execute('''
      CREATE TABLE IF NOT EXISTS voice_service_config (
        config_id INTEGER PRIMARY KEY CHECK (config_id = 1),
        api_base_url TEXT NOT NULL DEFAULT '',
        api_key_ref TEXT NOT NULL DEFAULT '',
        remote_stt_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (remote_stt_enabled IN (0, 1)),
        local_stt_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (local_stt_enabled IN (0, 1)),
        tts_model_id TEXT NOT NULL DEFAULT '',
        tts_model_name TEXT NOT NULL DEFAULT '',
        director_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (director_enabled IN (0, 1)),
        director_mode TEXT NOT NULL DEFAULT 'normal'
          CHECK (director_mode IN ('normal', 'affectionate', 'comforting', 'lively', 'serious')),
        director_min_chars INTEGER NOT NULL DEFAULT 6
          CHECK (director_min_chars BETWEEN 1 AND 200),
        verified INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0, 1)),
        service_revision INTEGER NOT NULL DEFAULT 0,
        verified_at TEXT,
        updated_at TEXT NOT NULL,
        CHECK (local_stt_enabled = 0 OR remote_stt_enabled = 0)
      )
    ''');
    await database.insert('voice_service_config', {
      'config_id': 1,
      'updated_at': DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await database.execute('''
      CREATE TABLE IF NOT EXISTS voice_local_models (
        model_id TEXT PRIMARY KEY,
        model_version TEXT NOT NULL,
        relative_path TEXT NOT NULL DEFAULT '',
        expected_bytes INTEGER,
        sha256 TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'not_downloaded'
          CHECK (status IN ('not_downloaded', 'downloading', 'ready', 'failed')),
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_voice_bindings (
        assistant_id TEXT PRIMARY KEY,
        voice_id TEXT NOT NULL,
        voice_name TEXT NOT NULL DEFAULT '',
        service_revision INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'valid'
          CHECK (status IN ('valid', 'invalid')),
        verified_at TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS message_voice_assets (
        asset_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        answer_version_id TEXT,
        segment_index INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL CHECK (kind IN (
          'user_recording', 'assistant_reply', 'manual_readout', 'preview', 'call_temp'
        )),
        relative_path TEXT NOT NULL DEFAULT '',
        audio_format TEXT NOT NULL DEFAULT 'wav',
        duration_ms INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'generating'
          CHECK (state IN ('generating', 'ready', 'failed', 'invalidated')),
        source_text_hash TEXT NOT NULL DEFAULT '',
        director_revision INTEGER NOT NULL DEFAULT 0,
        service_revision INTEGER NOT NULL DEFAULT 0,
        voice_id TEXT NOT NULL DEFAULT '',
        model_id TEXT NOT NULL DEFAULT '',
        generation_key TEXT NOT NULL DEFAULT '',
        transcript TEXT,
        transcript_state TEXT NOT NULL DEFAULT 'none'
          CHECK (transcript_state IN ('none', 'recognizing', 'ready', 'failed')),
        transcript_visible INTEGER NOT NULL DEFAULT 0
          CHECK (transcript_visible IN (0, 1)),
        display_mode TEXT NOT NULL DEFAULT 'voice_text'
          CHECK (display_mode IN ('voice', 'voice_text')),
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (answer_version_id) REFERENCES answer_versions(answer_version_id)
          ON DELETE CASCADE
      )
    ''');
    if (!await _columnExists(
      database,
      'message_voice_assets',
      'display_mode',
    )) {
      await database.execute('''
        ALTER TABLE message_voice_assets ADD COLUMN display_mode TEXT NOT NULL
          DEFAULT 'voice_text' CHECK (display_mode IN ('voice', 'voice_text'))
      ''');
    }
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_voice_assets_message_version_segment
      ON message_voice_assets(message_id, answer_version_id, segment_index, state)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_voice_assets_assistant_conversation
      ON message_voice_assets(assistant_id, conversation_id, created_at)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_voice_assets_active_generation
      ON message_voice_assets(generation_key)
      WHERE generation_key <> '' AND state IN ('generating', 'ready')
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS message_director_scripts (
        script_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
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
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (answer_version_id) REFERENCES answer_versions(answer_version_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_director_scripts_current
      ON message_director_scripts(message_id, answer_scope_id, segment_index, status)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS call_sessions (
        session_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'completed', 'interrupted')),
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        card_message_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY (card_message_id) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_call_sessions_conversation_started
      ON call_sessions(conversation_id, started_at DESC)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS call_turns (
        turn_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        turn_index INTEGER NOT NULL,
        user_message_id TEXT,
        assistant_message_id TEXT,
        user_transcript TEXT NOT NULL DEFAULT '',
        assistant_text TEXT NOT NULL DEFAULT '',
        heard_assistant_text TEXT NOT NULL DEFAULT '',
        voice_metrics_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'completed', 'discarded')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES call_sessions(session_id) ON DELETE CASCADE,
        FOREIGN KEY (user_message_id) REFERENCES messages(id) ON DELETE SET NULL,
        FOREIGN KEY (assistant_message_id) REFERENCES messages(id) ON DELETE SET NULL,
        UNIQUE (session_id, turn_index),
        UNIQUE (assistant_message_id)
      )
    ''');
  }

  Future<void> _createMemoryOrganizeQueueSchema(
    DatabaseExecutor database,
  ) async {
    // Some historical databases were stamped with a later schema version while
    // optional memory-rebuild tables had never been created. Keep this migration
    // self-contained so upgrading those installations does not fail on ALTER.
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_jobs (
        run_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT,
        import_job_id TEXT,
        scope TEXT NOT NULL CHECK (scope IN ('recent', 'all')),
        recent_count INTEGER,
        idempotency_key TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'queued'
          CHECK (status IN (
            'queued', 'running', 'pause_requested', 'paused',
            'completed', 'failed', 'cancelled'
          )),
        desired_state TEXT NOT NULL DEFAULT 'running'
          CHECK (desired_state IN ('running', 'paused')),
        frozen_message_count INTEGER NOT NULL DEFAULT 0,
        total_chunks INTEGER NOT NULL DEFAULT 0,
        processed_chunks INTEGER NOT NULL DEFAULT 0,
        committed_memories INTEGER NOT NULL DEFAULT 0,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        partial_kept INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        retryable INTEGER NOT NULL DEFAULT 0,
        error_code TEXT NOT NULL DEFAULT '',
        worker_token TEXT,
        lease_expires_at TEXT,
        heartbeat_at TEXT,
        trigger_source TEXT NOT NULL DEFAULT 'manual',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
          ON DELETE SET NULL,
        FOREIGN KEY (import_job_id) REFERENCES import_jobs(job_id)
          ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_rebuild_scope_messages (
        run_id TEXT NOT NULL,
        frozen_order INTEGER NOT NULL,
        message_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        block_id TEXT NOT NULL DEFAULT '',
        snapshot_revision_key TEXT NOT NULL DEFAULT '',
        snapshot_content_hash TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, frozen_order),
        UNIQUE (run_id, message_id),
        FOREIGN KEY (run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE RESTRICT
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_organize_message_state (
        message_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'waiting_stability'
          CHECK (status IN (
            'waiting_stability', 'pending', 'processing',
            'processed', 'discarded', 'retryable_failed'
          )),
        stable_after TEXT NOT NULL,
        observed_revision_key TEXT NOT NULL,
        observed_content_hash TEXT NOT NULL DEFAULT '',
        imported_stable INTEGER NOT NULL DEFAULT 0
          CHECK (imported_stable IN (0, 1)),
        claimed_run_id TEXT,
        processed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
          ON DELETE CASCADE,
        FOREIGN KEY (claimed_run_id) REFERENCES memory_rebuild_jobs(run_id)
          ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_organize_state_assistant
      ON memory_organize_message_state(
        assistant_id, status, stable_after, conversation_id
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_organize_state_conversation
      ON memory_organize_message_state(conversation_id, status, stable_after)
    ''');
    if (!await _columnExists(
      database,
      'memory_rebuild_scope_messages',
      'block_id',
    )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_scope_messages
        ADD COLUMN block_id TEXT NOT NULL DEFAULT ''
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_rebuild_scope_messages',
      'snapshot_revision_key',
    )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_scope_messages
        ADD COLUMN snapshot_revision_key TEXT NOT NULL DEFAULT ''
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_rebuild_scope_messages',
      'snapshot_content_hash',
    )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_scope_messages
        ADD COLUMN snapshot_content_hash TEXT NOT NULL DEFAULT ''
      ''');
    }
    if (!await _columnExists(
      database,
      'memory_rebuild_jobs',
      'trigger_source',
    )) {
      await database.execute('''
        ALTER TABLE memory_rebuild_jobs
        ADD COLUMN trigger_source TEXT NOT NULL DEFAULT 'manual'
      ''');
    }
  }

  Future<void> _createMemorySearchIndexSchema(DatabaseExecutor database) async {
    if (!await _tableExists(database, 'memory_items')) return;
    final memoryColumns = (await database.rawQuery(
      'PRAGMA table_info(memory_items)',
    )).map((row) => row['name']).whereType<String>().toSet();
    String existingColumn(String name, String fallback) =>
        memoryColumns.contains(name) ? name : fallback;
    String newColumn(String name, String fallback) =>
        memoryColumns.contains(name) ? 'NEW.$name' : fallback;
    String searchTextExpression(String prefix) {
      String column(String name, String fallback) =>
          memoryColumns.contains(name) ? '$prefix.$name' : fallback;
      final content = column('content', "''");
      final subjectScope = column('subject_scope', "'other'");
      final assistantSelfKind = column('assistant_self_kind', 'NULL');
      final eventTime = column('event_time', 'NULL');
      final timePrecision = column('time_precision', "'unknown'");
      return '''
        TRIM(
          COALESCE($content, '') ||
          CASE $subjectScope
            WHEN 'user' THEN ' 用户 用户相关 关于用户'
            WHEN 'assistant' THEN ' 助手 助手相关 关于助手'
            WHEN 'relationship' THEN ' 关系 双方关系'
            WHEN 'shared' THEN ' 共同经历 共同记忆'
            ELSE ''
          END ||
          CASE $assistantSelfKind
            WHEN 'identity' THEN ' 身份 名字 名称 角色'
            WHEN 'commitment' THEN ' 承诺 约定'
            WHEN 'preference' THEN ' 偏好 喜欢 讨厌'
            WHEN 'opinion' THEN ' 观点 看法'
            WHEN 'trait' THEN ' 性格 特征'
            WHEN 'other' THEN ' 助手其他信息'
            ELSE ''
          END ||
          CASE
            WHEN $eventTime IS NULL OR $eventTime = '' THEN ''
            ELSE ' 事件 时间 ' || $eventTime ||
              ' ' || SUBSTR($eventTime, 1, 4) || '年' ||
              ' ' || SUBSTR($eventTime, 6, 2) || '月' ||
              ' ' || SUBSTR($eventTime, 9, 2) || '日'
          END ||
          CASE $timePrecision
            WHEN 'exact' THEN ' 精确时间'
            WHEN 'partial' THEN ' 大致时间 部分时间'
            ELSE ''
          END
        )
      ''';
    }

    final activeNew = memoryColumns.contains('status')
        ? "NEW.status = 'active'"
        : '1 = 1';
    final activeRow = memoryColumns.contains('status')
        ? "status = 'active'"
        : '1 = 1';
    final watchedColumns = [
      'content',
      'status',
      'event_time',
      'time_precision',
      'importance',
      'reinforcement_count',
      'subject_scope',
      'assistant_self_kind',
      'updated_at',
    ].where(memoryColumns.contains).join(', ');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS memory_search_index (
        memory_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        search_text TEXT NOT NULL,
        subject_scope TEXT NOT NULL DEFAULT 'other',
        assistant_self_kind TEXT,
        event_time TEXT,
        time_precision TEXT NOT NULL DEFAULT 'unknown',
        importance REAL NOT NULL DEFAULT 0.5,
        reinforcement_count INTEGER NOT NULL DEFAULT 0,
        source_updated_at TEXT NOT NULL,
        FOREIGN KEY (memory_id) REFERENCES memory_items(memory_id)
          ON DELETE CASCADE,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_search_index_assistant
      ON memory_search_index(assistant_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_search_index_subject
      ON memory_search_index(assistant_id, subject_scope)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_search_index_event_time
      ON memory_search_index(assistant_id, event_time)
    ''');
    await database.execute(
      'DROP TRIGGER IF EXISTS trg_memory_search_index_insert',
    );
    await database.execute(
      'DROP TRIGGER IF EXISTS trg_memory_search_index_update',
    );
    await database.execute('''
      CREATE TRIGGER trg_memory_search_index_insert
      AFTER INSERT ON memory_items
      WHEN $activeNew
      BEGIN
        INSERT OR REPLACE INTO memory_search_index (
          memory_id,
          assistant_id,
          search_text,
          subject_scope,
          assistant_self_kind,
          event_time,
          time_precision,
          importance,
          reinforcement_count,
          source_updated_at
        ) VALUES (
          NEW.memory_id,
          NEW.assistant_id,
          ${searchTextExpression('NEW')},
          ${newColumn('subject_scope', "'other'")},
          ${newColumn('assistant_self_kind', 'NULL')},
          ${newColumn('event_time', 'NULL')},
          ${newColumn('time_precision', "'unknown'")},
          ${newColumn('importance', '0.5')},
          ${newColumn('reinforcement_count', '0')},
          ${newColumn('updated_at', 'CURRENT_TIMESTAMP')}
        );
      END
    ''');
    await database.execute('''
      CREATE TRIGGER trg_memory_search_index_update
      AFTER UPDATE OF $watchedColumns ON memory_items
      BEGIN
        DELETE FROM memory_search_index
        WHERE memory_id = NEW.memory_id AND NOT ($activeNew);

        INSERT OR REPLACE INTO memory_search_index (
          memory_id,
          assistant_id,
          search_text,
          subject_scope,
          assistant_self_kind,
          event_time,
          time_precision,
          importance,
          reinforcement_count,
          source_updated_at
        )
        SELECT
          NEW.memory_id,
          NEW.assistant_id,
          ${searchTextExpression('NEW')},
          ${newColumn('subject_scope', "'other'")},
          ${newColumn('assistant_self_kind', 'NULL')},
          ${newColumn('event_time', 'NULL')},
          ${newColumn('time_precision', "'unknown'")},
          ${newColumn('importance', '0.5')},
          ${newColumn('reinforcement_count', '0')},
          ${newColumn('updated_at', 'CURRENT_TIMESTAMP')}
        WHERE $activeNew;
      END
    ''');
    await database.execute('''
      INSERT OR REPLACE INTO memory_search_index (
        memory_id,
        assistant_id,
        search_text,
        subject_scope,
        assistant_self_kind,
        event_time,
        time_precision,
        importance,
        reinforcement_count,
        source_updated_at
      )
      SELECT
        memory_id,
        assistant_id,
        ${searchTextExpression('memory_items')},
        ${existingColumn('subject_scope', "'other'")},
        ${existingColumn('assistant_self_kind', 'NULL')},
        ${existingColumn('event_time', 'NULL')},
        ${existingColumn('time_precision', "'unknown'")},
        ${existingColumn('importance', '0.5')},
        ${existingColumn('reinforcement_count', '0')},
        ${existingColumn('updated_at', 'CURRENT_TIMESTAMP')}
      FROM memory_items
      WHERE $activeRow
    ''');
  }

  Future<void> _createLocalGameSchema(DatabaseExecutor database) async {
    if (await _tableExists(database, 'conversations')) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_id_assistant
        ON conversations(id, assistant_id)
      ''');
    }
    await database.execute('''
      CREATE TABLE IF NOT EXISTS game_invitations (
        invitation_id TEXT PRIMARY KEY,
        request_key TEXT NOT NULL UNIQUE,
        source TEXT NOT NULL CHECK (source IN ('chat', 'game_center')),
        game_type TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        inviter_actor TEXT NOT NULL DEFAULT 'user'
          CHECK (inviter_actor IN ('user', 'assistant')),
        invitee_actor TEXT NOT NULL DEFAULT 'assistant'
          CHECK (invitee_actor IN ('user', 'assistant')),
        assistant_play_mode TEXT CHECK (
          assistant_play_mode IS NULL OR assistant_play_mode IN (
            'intentional_let_win',
            'held_back',
            'normal',
            'serious',
            'full_strength'
          )
        ),
        status TEXT NOT NULL CHECK (
          status IN (
            'deciding',
            'accepted_pending_user',
            'rejected',
            'decision_failed',
            'cancelled',
            'consumed'
          )
        ),
        trigger_message_id TEXT,
        created_at TEXT NOT NULL,
        decided_at TEXT,
        cancelled_at TEXT,
        version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id, assistant_id)
          REFERENCES conversations(id, assistant_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS game_sessions (
        session_id TEXT PRIMARY KEY,
        invitation_id TEXT UNIQUE,
        game_type TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('active', 'completed')),
        current_round_id TEXT,
        user_wins INTEGER NOT NULL DEFAULT 0 CHECK (user_wins >= 0),
        assistant_wins INTEGER NOT NULL DEFAULT 0 CHECK (assistant_wins >= 0),
        draws INTEGER NOT NULL DEFAULT 0 CHECK (draws >= 0),
        context_turns_remaining INTEGER NOT NULL DEFAULT 0 CHECK (
          context_turns_remaining >= 0 AND context_turns_remaining <= 5
        ),
        started_at TEXT NOT NULL,
        ended_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
        UNIQUE (session_id, assistant_id, conversation_id),
        FOREIGN KEY (invitation_id)
          REFERENCES game_invitations(invitation_id) ON DELETE SET NULL,
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id, assistant_id)
          REFERENCES conversations(id, assistant_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS game_rounds (
        round_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        round_index INTEGER NOT NULL CHECK (round_index > 0),
        status TEXT NOT NULL CHECK (status IN ('active', 'completed')),
        ruleset_version TEXT NOT NULL,
        first_player TEXT NOT NULL CHECK (first_player IN ('user', 'assistant')),
        assistant_play_mode TEXT NOT NULL CHECK (
          assistant_play_mode IN (
            'intentional_let_win',
            'held_back',
            'normal',
            'serious',
            'full_strength'
          )
        ),
        engine_profile_id TEXT NOT NULL,
        engine_version TEXT NOT NULL,
        winner TEXT CHECK (winner IN ('user', 'assistant', 'draw')),
        termination_reason TEXT,
        final_state_json TEXT,
        undo_used_count INTEGER NOT NULL DEFAULT 0 CHECK (undo_used_count >= 0),
        undo_limit INTEGER NOT NULL DEFAULT 3 CHECK (undo_limit >= 0),
        started_at TEXT NOT NULL,
        ended_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
        UNIQUE (session_id, round_index),
        UNIQUE (round_id, assistant_id, conversation_id),
        FOREIGN KEY (session_id, assistant_id, conversation_id)
          REFERENCES game_sessions(
            session_id,
            assistant_id,
            conversation_id
          ) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS game_events (
        event_id TEXT PRIMARY KEY,
        round_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        event_index INTEGER NOT NULL CHECK (event_index > 0),
        actor TEXT NOT NULL CHECK (actor IN ('user', 'assistant', 'system')),
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        state_hash_after TEXT,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'undone')),
        client_action_id TEXT,
        undo_batch_id TEXT,
        created_at TEXT NOT NULL,
        UNIQUE (round_id, event_index),
        FOREIGN KEY (round_id, assistant_id, conversation_id)
          REFERENCES game_rounds(
            round_id,
            assistant_id,
            conversation_id
          ) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS game_card_projections (
        card_id TEXT PRIMARY KEY,
        game_type TEXT NOT NULL DEFAULT 'gomoku',
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        invitation_id TEXT,
        session_id TEXT,
        state TEXT NOT NULL CHECK (
          state IN ('pending', 'rejected', 'cancelled', 'in_game', 'completed')
        ),
        display_title TEXT NOT NULL,
        display_summary TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
        updated_at TEXT NOT NULL,
        CHECK (
          (invitation_id IS NOT NULL AND session_id IS NULL)
          OR (invitation_id IS NULL AND session_id IS NOT NULL)
        ),
        FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
        FOREIGN KEY (conversation_id, assistant_id)
          REFERENCES conversations(id, assistant_id) ON DELETE CASCADE,
        FOREIGN KEY (invitation_id)
          REFERENCES game_invitations(invitation_id) ON DELETE CASCADE,
        FOREIGN KEY (session_id)
          REFERENCES game_sessions(session_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_game_sessions_assistant_started
      ON game_sessions(assistant_id, started_at DESC)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_game_sessions_one_active
      ON game_sessions(assistant_id, game_type)
      WHERE status = 'active'
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_game_sessions_conversation_started
      ON game_sessions(conversation_id, started_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_game_rounds_session_index
      ON game_rounds(session_id, round_index ASC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_game_events_round_index
      ON game_events(round_id, event_index ASC)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_game_events_client_action
      ON game_events(round_id, client_action_id, actor, event_type)
      WHERE client_action_id IS NOT NULL
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_game_invitations_conversation
      ON game_invitations(conversation_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_game_cards_invitation
      ON game_card_projections(invitation_id)
      WHERE invitation_id IS NOT NULL
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_game_cards_session
      ON game_card_projections(session_id)
      WHERE session_id IS NOT NULL
    ''');
    if (await _columnExists(database, 'messages', 'game_invitation_id')) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_game_invitation
        ON messages(game_invitation_id)
        WHERE game_invitation_id IS NOT NULL
      ''');
    }
    await _createPictionaryFoundationSchema(database);
    await _createPictionaryUserGuessesSchema(database);
  }

  Future<void> _createPictionaryFoundationSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pictionary_sessions (
        session_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'ready'
          CHECK (state IN (
            'ready', 'active', 'settling', 'completed',
            'retryable_failure', 'failed'
          )),
        current_round_index INTEGER NOT NULL DEFAULT 0
          CHECK (current_round_index BETWEEN 0 AND 4),
        user_correct INTEGER NOT NULL DEFAULT 0 CHECK (user_correct >= 0),
        assistant_correct INTEGER NOT NULL DEFAULT 0
          CHECK (assistant_correct >= 0),
        recoverable_failure_code TEXT,
        recoverable_failure_details TEXT,
        end_reason TEXT NOT NULL DEFAULT 'normal'
          CHECK (end_reason IN ('normal', 'aborted', 'technical_failure')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
        UNIQUE (session_id, assistant_id, conversation_id),
        FOREIGN KEY (session_id, assistant_id, conversation_id)
          REFERENCES game_sessions(session_id, assistant_id, conversation_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pictionary_rounds (
        round_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        round_index INTEGER NOT NULL CHECK (round_index BETWEEN 1 AND 4),
        drawer TEXT NOT NULL CHECK (drawer IN ('user', 'assistant')),
        word_id TEXT NOT NULL,
        answer TEXT NOT NULL,
        aliases_json TEXT NOT NULL DEFAULT '[]',
        category_hint TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ready'
          CHECK (status IN (
            'ready', 'active', 'settling', 'completed',
            'retryable_failure', 'aborted'
          )),
        result TEXT CHECK (result IS NULL OR result IN (
          'correct', 'missed', 'technical_failure', 'aborted'
        )),
        started_at TEXT,
        deadline_at TEXT,
        hint_revealed_at TEXT,
        ended_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
        UNIQUE (session_id, round_index),
        FOREIGN KEY (session_id, assistant_id, conversation_id)
          REFERENCES pictionary_sessions(
            session_id, assistant_id, conversation_id
          ) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pictionary_guess_attempts (
        attempt_id TEXT PRIMARY KEY,
        round_id TEXT NOT NULL,
        attempt_index INTEGER NOT NULL CHECK (attempt_index BETWEEN 1 AND 3),
        target_second INTEGER NOT NULL CHECK (target_second IN (15, 35, 55)),
        media_id TEXT,
        hint_included INTEGER NOT NULL DEFAULT 0 CHECK (hint_included IN (0, 1)),
        candidates_json TEXT NOT NULL DEFAULT '[]',
        primary_guess TEXT,
        matched_alias TEXT,
        route TEXT,
        model_service_id TEXT,
        technical_status TEXT NOT NULL DEFAULT 'pending',
        visual_description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (round_id, attempt_index),
        FOREIGN KEY (round_id) REFERENCES pictionary_rounds(round_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pictionary_drawing_plans (
        plan_id TEXT PRIMARY KEY,
        round_id TEXT NOT NULL UNIQUE,
        raw_response TEXT,
        normalized_plan_json TEXT,
        contract_version INTEGER NOT NULL DEFAULT 1,
        model_service_id TEXT,
        validation_errors_json TEXT NOT NULL DEFAULT '[]',
        repair_count INTEGER NOT NULL DEFAULT 0 CHECK (repair_count >= 0),
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (round_id) REFERENCES pictionary_rounds(round_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pictionary_canvas_drafts (
        round_id TEXT PRIMARY KEY,
        commands_json TEXT NOT NULL DEFAULT '[]',
        undo_cursor INTEGER NOT NULL DEFAULT 0 CHECK (undo_cursor >= 0),
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
        FOREIGN KEY (round_id) REFERENCES pictionary_rounds(round_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS game_media (
        media_id TEXT PRIMARY KEY,
        game_type TEXT NOT NULL,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        round_id TEXT,
        purpose TEXT NOT NULL,
        relative_path TEXT NOT NULL UNIQUE,
        sha256 TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        width INTEGER NOT NULL CHECK (width > 0),
        height INTEGER NOT NULL CHECK (height > 0),
        byte_length INTEGER NOT NULL CHECK (byte_length >= 0),
        visual_description TEXT,
        description_source TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id, assistant_id, conversation_id)
          REFERENCES game_sessions(session_id, assistant_id, conversation_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_pictionary_rounds_session
      ON pictionary_rounds(session_id, round_index)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_game_media_session_round
      ON game_media(session_id, round_id, created_at)
    ''');
  }

  /// 迁移到 v42：创建 session_tool_grants 表（§52/§67）
  ///
  /// Session 临时授权持久化，用于 Together Session 临时工具授权。
  Future<void> _createPictionaryUserGuessesSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pictionary_user_guesses (
        attempt_id TEXT PRIMARY KEY,
        round_id TEXT NOT NULL,
        attempt_index INTEGER NOT NULL CHECK (attempt_index > 0),
        guess TEXT NOT NULL,
        matched_alias TEXT,
        is_correct INTEGER NOT NULL DEFAULT 0 CHECK (is_correct IN (0, 1)),
        created_at TEXT NOT NULL,
        UNIQUE (round_id, attempt_index),
        FOREIGN KEY (round_id) REFERENCES pictionary_rounds(round_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_pictionary_user_guesses_round
      ON pictionary_user_guesses(round_id, attempt_index)
    ''');
  }

  /// 迁移到 v42：创建 session_tool_grants 表（§52/§67）
  ///
  /// Session 临时授权持久化，用于 Together Session 临时工具授权。

  Future<void> _migrateToVersion42(Database database) async {
    await _createSessionToolGrantsSchema(database);
  }

  /// 迁移到 v43：创建 tool_artifacts 表（§26）
  ///
  /// 工具产物生命周期持久化。
  Future<void> _migrateToVersion43(Database database) async {
    await _createToolArtifactsSchema(database);
  }

  /// 创建持续心智批次 1 表（M4 §17）
  Future<void> _createMindBoardSchema(DatabaseExecutor database) async {
    // 全局小纸条（§4）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS global_notes (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        title TEXT,
        note_type TEXT NOT NULL DEFAULT 'text'
          CHECK (note_type IN ('text', 'checklist')),
        author_type TEXT NOT NULL DEFAULT 'user'
          CHECK (author_type IN ('user', 'assistant', 'system')),
        author_assistant_id TEXT,
        source_type TEXT,
        source_id TEXT,
        origin_conversation_id TEXT,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'deleted', 'expired')),
        completion_state TEXT NOT NULL DEFAULT 'open'
          CHECK (completion_state IN ('open', 'completed')),
        completion_reason TEXT
          CHECK (completion_reason IS NULL OR completion_reason IN (
            'completed', 'cancelled', 'expired'
          )),
        completed_at TEXT,
        pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
        palette_key INTEGER NOT NULL DEFAULT 0,
        tape_style INTEGER NOT NULL DEFAULT 0,
        wall_order INTEGER NOT NULL DEFAULT 0,
        is_displayed INTEGER NOT NULL DEFAULT 0
          CHECK (is_displayed IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        effective_at TEXT,
        expires_at TEXT,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_global_notes_status
      ON global_notes(status)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_global_notes_created
      ON global_notes(created_at DESC)
    ''');
    if (await _columnExists(database, 'global_notes', 'is_displayed')) {
      await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_global_notes_single_displayed
        ON global_notes(is_displayed)
        WHERE is_displayed = 1
      ''');
    }

    // 留言板帖子（§6）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS board_posts (
        post_id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        author_type TEXT NOT NULL DEFAULT 'user'
          CHECK (author_type IN ('user', 'assistant')),
        author_assistant_id TEXT,
        generation_task_id TEXT,
        generation_kind TEXT CHECK (generation_kind IN (
          'auto_post', 'user_event_reply'
        )),
        created_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_posts_created
      ON board_posts(created_at DESC)
    ''');

    // 留言板评论（§6）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS board_comments (
        comment_id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        content TEXT NOT NULL,
        author_type TEXT NOT NULL DEFAULT 'user'
          CHECK (author_type IN ('user', 'assistant')),
        author_assistant_id TEXT,
        target_assistant_id TEXT,
        parent_comment_id TEXT,
        generation_task_id TEXT,
        generation_kind TEXT CHECK (generation_kind IN (
          'auto_post', 'user_event_reply'
        )),
        created_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (post_id) REFERENCES board_posts(post_id) ON DELETE CASCADE,
        FOREIGN KEY (parent_comment_id) REFERENCES board_comments(comment_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_comments_post
      ON board_comments(post_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_comments_created
      ON board_comments(created_at DESC)
    ''');
    await _createMessageBoardV2Schema(database);
    await _createMessageBoardV2Indexes(database);
    await _createBoardPostLikesSchema(database);

    // 日历事件（§5）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS calendar_events (
        event_id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
        category_id TEXT NOT NULL DEFAULT 'daily',
        author_type TEXT NOT NULL DEFAULT 'user'
          CHECK (author_type IN ('user', 'assistant', 'system')),
        author_assistant_id TEXT,
        event_time TEXT NOT NULL,
        start_at TEXT NOT NULL,
        end_at TEXT,
        is_all_day INTEGER NOT NULL DEFAULT 0 CHECK (is_all_day IN (0, 1)),
        recurrence_kind TEXT NOT NULL DEFAULT 'none'
          CHECK (recurrence_kind IN ('none', 'daily', 'weekly', 'monthly', 'yearly')),
        recurrence_interval INTEGER NOT NULL DEFAULT 1
          CHECK (recurrence_interval > 0),
        recurrence_weekdays TEXT,
        recurrence_until TEXT,
        custom_advance_minutes INTEGER
          CHECK (custom_advance_minutes IS NULL OR custom_advance_minutes >= 0),
        time_precision TEXT NOT NULL DEFAULT 'day'
          CHECK (time_precision IN ('exact', 'day', 'month', 'year', 'unknown')),
        source_type TEXT,
        source_id TEXT,
        origin_conversation_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_calendar_events_time
      ON calendar_events(event_time)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_calendar_events_source
      ON calendar_events(source_type, source_id)
    ''');
    await _createStickyCalendarV74Tables(database);
  }

  Future<void> _createStickyCalendarV74Tables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sticky_note_items (
        item_id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        content TEXT NOT NULL,
        position INTEGER NOT NULL,
        checked INTEGER NOT NULL DEFAULT 0 CHECK (checked IN (0, 1)),
        checked_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (note_id, position),
        FOREIGN KEY (note_id) REFERENCES global_notes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_sticky_note_mentions (
        assistant_id TEXT NOT NULL,
        note_id TEXT NOT NULL,
        channel TEXT NOT NULL CHECK (channel IN ('chat', 'proactive', 'patrol')),
        last_success_at TEXT NOT NULL,
        PRIMARY KEY (assistant_id, note_id, channel),
        FOREIGN KEY (note_id) REFERENCES global_notes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS calendar_event_exceptions (
        exception_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        occurrence_key TEXT NOT NULL,
        action TEXT NOT NULL CHECK (action IN ('modified', 'deleted')),
        override_title TEXT,
        override_notes TEXT,
        override_category TEXT,
        override_start_at TEXT,
        override_end_at TEXT,
        override_is_all_day INTEGER
          CHECK (override_is_all_day IS NULL OR override_is_all_day IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (event_id, occurrence_key),
        FOREIGN KEY (event_id) REFERENCES calendar_events(event_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_calendar_mentions (
        assistant_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        occurrence_key TEXT NOT NULL,
        last_success_at TEXT NOT NULL,
        final_two_hour_used_at TEXT,
        PRIMARY KEY (assistant_id, event_id, occurrence_key),
        FOREIGN KEY (event_id) REFERENCES calendar_events(event_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sticky_note_items_note_position
      ON sticky_note_items(note_id, position)
    ''');
    if (await _columnExists(database, 'calendar_events', 'start_at')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS idx_calendar_events_start
        ON calendar_events(start_at)
      ''');
    }
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_calendar_event_exceptions_event
      ON calendar_event_exceptions(event_id, occurrence_key)
    ''');
    await _createCalendarCreatorColorsSchema(database);
  }

  Future<void> _createCalendarCreatorColorsSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS calendar_creator_colors (
        creator_key TEXT PRIMARY KEY,
        color_value INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// 创建 tool_artifacts 表（§26）
  Future<void> _createToolArtifactsSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS tool_artifacts (
        artifact_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        local_uri TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        lifecycle TEXT NOT NULL DEFAULT 'call',
        model_input_allowed INTEGER NOT NULL DEFAULT 0,
        conversation_id TEXT,
        session_id TEXT,
        activity_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_artifacts_lifecycle
      ON tool_artifacts(lifecycle)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_artifacts_conversation
      ON tool_artifacts(conversation_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_artifacts_session
      ON tool_artifacts(session_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_tool_artifacts_activity
      ON tool_artifacts(activity_id)
    ''');
  }

  /// 创建 session_tool_grants 表（§52/§67）
  Future<void> _createSessionToolGrantsSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS session_tool_grants (
        session_id TEXT PRIMARY KEY,
        assistant_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        session_type TEXT NOT NULL DEFAULT 'custom',
        allowed_tools_json TEXT NOT NULL DEFAULT '[]',
        allowed_scope_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_tool_grants_assistant
      ON session_tool_grants(assistant_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_tool_grants_conversation
      ON session_tool_grants(conversation_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_tool_grants_expires
      ON session_tool_grants(expires_at)
    ''');
  }

  /// 创建持续心智批次 2 表（M4 §7/§8/§17）
  Future<void> _createContinuityAwarenessSchema(
    DatabaseExecutor database,
  ) async {
    // 连续性事件（§7）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS continuity_events (
        event_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        actor_type TEXT NOT NULL CHECK (actor_type IN ('user', 'assistant', 'system')),
        actor_assistant_id TEXT,
        object_type TEXT NOT NULL,
        object_id TEXT NOT NULL,
        target_assistant_id TEXT,
        occurred_at TEXT NOT NULL,
        payload_summary TEXT NOT NULL DEFAULT '',
        visibility_scope TEXT NOT NULL DEFAULT 'all'
          CHECK (visibility_scope IN ('all', 'assistant_only', 'user_only'))
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_continuity_events_occurred
      ON continuity_events(occurred_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_continuity_events_object
      ON continuity_events(object_type, object_id)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_continuity_events_target
      ON continuity_events(target_assistant_id)
    ''');

    // 每助手已知状态（§8）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_awareness (
        assistant_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending'
          CHECK (state IN ('pending', 'known', 'suppressed', 'expired')),
        eligible_at TEXT NOT NULL,
        known_at TEXT,
        last_activated_at TEXT,
        PRIMARY KEY (assistant_id, event_id),
        FOREIGN KEY (event_id) REFERENCES continuity_events(event_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_assistant_awareness_state
      ON assistant_awareness(assistant_id, state)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_assistant_awareness_event
      ON assistant_awareness(event_id)
    ''');
  }

  /// 创建持续心智批次 5 表（M4 §9）
  Future<void> _createAttentionSchema(DatabaseExecutor database) async {
    // 每助手注意力状态（§9.2 known_active / settled）
    await database.execute('''
      CREATE TABLE IF NOT EXISTS assistant_attention (
        assistant_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'known_active'
          CHECK (state IN ('known_active', 'settled')),
        first_known_at TEXT NOT NULL,
        last_activated_at TEXT NOT NULL,
        last_proactive_mention_at TEXT,
        next_allowed_at TEXT NOT NULL,
        is_closed INTEGER NOT NULL DEFAULT 0,
        has_follow_up INTEGER NOT NULL DEFAULT 0,
        settled_at TEXT,
        settled_reason TEXT,
        PRIMARY KEY (assistant_id, event_id),
        FOREIGN KEY (event_id) REFERENCES continuity_events(event_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_assistant_attention_state
      ON assistant_attention(assistant_id, state, next_allowed_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_assistant_attention_event
      ON assistant_attention(event_id)
    ''');
  }
}
