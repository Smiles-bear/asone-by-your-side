import 'dart:io';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/local_core/group_chat/group_round_handler.dart';
import 'package:azruiyoi_community/community_group_round_engine.dart';
import 'package:azruiyoi_community/community_group_service.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FixedGroupRunner implements GroupAssistantTurnRunner {
  @override
  Future<void> cancelRoom(String roomId) async {}

  @override
  Future<void> run({
    required GroupTurnRequest request,
    required void Function(String delta) onDelta,
    required void Function() onSegmentBoundary,
    required GroupTurnCommitter commit,
  }) async {
    final content = '正式轮次：${request.step.assistantId}';
    onDelta(content);
    await commit(GroupTurnResult(content: content, segments: [content]));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('社区群聊公共引擎通过正式轮次状态机提交全部成员回复', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('community-round-');
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
    final first = await core.modelServices.createModelService({
      'name': '甲模型',
      'base_url': 'https://a.example.com/v1',
      'api_key': 'key-a',
      'model': 'model-a',
      'protocol_type': ProtocolType.openaiChat,
    });
    final second = await core.modelServices.createModelService({
      'name': '乙模型',
      'base_url': 'https://b.example.com/v1',
      'api_key': 'key-b',
      'model': 'model-b',
      'protocol_type': ProtocolType.openaiChat,
    });
    final engine = CommunityGroupRoundEngine(
      database: database,
      chat: core.chat,
      contextBuilder: core.groupContext,
      rooms: core.groupRooms,
      messages: core.groupMessages,
      turnRunner: _FixedGroupRunner(),
    );
    addTearDown(engine.dispose);
    final groups = CommunityGroupService(
      assistants: core.repository,
      modelServices: core.repository,
      rooms: core.groupRooms,
      messages: core.groupMessages,
      roundEngine: engine,
    );
    final room = await groups.createRoom(
      title: '状态机群聊',
      serviceIds: [first.id, second.id],
    );

    final messages = await groups.sendUserMessage(
      roomId: room.roomId,
      content: '请依次回复',
    );

    expect(messages, hasLength(3));
    expect(messages.first.content, '请依次回复');
    expect(
      messages.skip(1).every((item) => item.answerStatus == 'completed'),
      isTrue,
    );
    expect(
      messages.skip(1).every((item) => item.content.startsWith('正式轮次：')),
      isTrue,
    );

    final participants = await groups.participantsForRoom(room.roomId);
    final mentioned = await groups.sendUserMessageToAssistant(
      roomId: room.roomId,
      assistantId: participants.first.assistantId,
      content: '只请一位成员回复',
    );
    expect(mentioned, hasLength(5));
    expect(mentioned[3].content, '只请一位成员回复');
    expect(mentioned[4].speakerAssistantId, participants.first.assistantId);
    expect(mentioned[4].answerStatus, 'completed');

    final regenerated = await groups.regenerateAssistantMessage(
      messages[1].messageId,
    );
    expect(
      regenerated
          .where((item) => item.speakerType == 'assistant')
          .every((item) => item.answerStatus == 'completed'),
      isTrue,
    );
  });
}
