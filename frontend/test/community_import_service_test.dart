import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/local_core/import/import_job.dart';
import 'package:azruiyoi_community/local_core/import/import_plan.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('社区版将 JSON 聊天记录预检、计划并持久化到本地会话', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('community-import-');
    final database = CoreDatabase.forTesting(
      databaseFactory: databaseFactoryFfi,
      supportDirectoryProvider: () async => root,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final core = PublicCore(
      database: database,
      fallback: DemoCore.withDemoSeed(),
    );
    await core.open();

    final created = await core.imports.createImportFromBytes(
      'history.json',
      Uint8List.fromList(
        utf8.encode(
          '{"title":"迁移的聊天","messages":['
          '{"id":"m-1","role":"user","content":"你好","created_at":"2026-09-01T08:00:00Z"},'
          '{"id":"m-2","role":"assistant","content":"欢迎来到社区版","created_at":"2026-09-01T08:01:00Z"}'
          ']}',
        ),
      ),
    );

    expect(created.preview.canStart, isTrue);
    expect(created.preview.parserSummary?.parserId, 'json-records');
    expect(created.preview.messageCount, 2);
    await core.imports.submitGroupedImportPlan(
      created.job.jobId,
      const GroupedImportPlan(
        groups: [
          ImportPlanGroup(
            groupId: 'history',
            sourceConversationIds: ['conversation-0'],
            assistantName: '导入助手',
            conversationTitle: '迁移的聊天',
          ),
        ],
        conversationOrder: ['conversation-0'],
      ),
    );
    await core.imports.startImport(created.job.jobId);
    final completed = await _waitForCompletion(core, created.job.jobId);

    expect(completed.status, 'completed');
    final conversation = (await core.conversations.getConversations()).single;
    expect(conversation.title, '迁移的聊天');
    final messages = await core.messages.getMessages(conversation.id);
    expect(messages.map((message) => message.content), ['你好', '欢迎来到社区版']);
    expect(messages.map((message) => message.role.name), ['user', 'assistant']);
  });

  test('社区版可在确认文本角色映射后导入保守解析的记录', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp(
      'community-text-import-',
    );
    final database = CoreDatabase.forTesting(
      databaseFactory: databaseFactoryFfi,
      supportDirectoryProvider: () async => root,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final core = PublicCore(
      database: database,
      fallback: DemoCore.withDemoSeed(),
    );
    await core.open();

    final created = await core.imports.createImportFromBytes(
      'old-history.txt',
      Uint8List.fromList(
        utf8.encode('[2026-09-01 08:00] 小明：早上好\n[2026-09-01 08:01] 小悠：早上好！'),
      ),
    );

    expect(created.preview.canStart, isFalse);
    expect(
      created.preview.uncertainRoles.map((role) => role.sourceRole),
      containsAll(['小明', '小悠']),
    );
    await core.imports.submitGroupedImportPlan(
      created.job.jobId,
      const GroupedImportPlan(
        groups: [
          ImportPlanGroup(
            groupId: 'text-history',
            sourceConversationIds: ['conversation-0'],
            assistantName: '导入助手',
            conversationTitle: '旧聊天',
          ),
        ],
        roleMappings: {'小明': 'user', '小悠': 'assistant'},
        conversationOrder: ['conversation-0'],
      ),
    );
    await core.imports.startImport(created.job.jobId);
    await _waitForCompletion(core, created.job.jobId);

    final conversation = (await core.conversations.getConversations()).single;
    final messages = await core.messages.getMessages(conversation.id);
    expect(messages.map((message) => message.role.name), ['user', 'assistant']);
    expect(messages.map((message) => message.content), ['早上好', '早上好！']);
  });
}

Future<ImportJob> _waitForCompletion(PublicCore core, String jobId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final job = await core.imports.getImportStatus(jobId);
    if (job == null) throw StateError('import job disappeared');
    if (job.isTerminal) return job;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('import job did not finish in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}
