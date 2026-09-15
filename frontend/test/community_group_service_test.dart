import 'dart:io';

import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/local_core/core_database.dart';
import 'package:azruiyoi_community/community_group_service.dart';
import 'package:azruiyoi_community/public_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('社区群聊按成员顺序持久化用户消息和基础文本回复', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('community-group-');
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

    final room = await core.groupChat.createRoom(
      title: '测试群聊',
      serviceIds: [first.id, second.id],
    );
    final participants = await core.groupChat.participantsForRoom(room.roomId);
    expect(participants, hasLength(2));

    final messages = await core.groupChat.sendUserMessage(
      roomId: room.roomId,
      content: '大家好',
      replyGenerator:
          ({required service, required assistantName, required history}) {
            expect(history.first['content'], '大家好');
            return Future.value(
              CommunityGroupReply.success('$assistantName 已收到'),
            );
          },
    );

    expect(messages.map((message) => message.speakerType), [
      'user',
      'assistant',
      'assistant',
    ]);
    expect(messages.map((message) => message.content), [
      '大家好',
      '甲模型 已收到',
      '乙模型 已收到',
    ]);
    expect(
      messages
          .where((message) => message.speakerType == 'assistant')
          .every((message) => message.answerStatus == 'completed'),
      isTrue,
    );
  });
}
