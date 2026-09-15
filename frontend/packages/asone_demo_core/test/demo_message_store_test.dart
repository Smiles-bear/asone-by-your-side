import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('种子会话消息按时间升序返回且含失败样例', () async {
    final core = DemoCore.withDemoSeed();
    final page = await core.messages.getMessagePage('demo-conversation-xiaoru');
    expect(page.items.length, greaterThanOrEqualTo(4));
    expect(page.items.first.role.name, 'user');
    final timestamps = page.items.map((message) => message.createdAt).toList();
    for (var i = 1; i < timestamps.length; i++) {
      expect(timestamps[i].isBefore(timestamps[i - 1]), isFalse);
    }
    expect(
      page.items.where((message) => message.answerStatus?.name == 'failed'),
      isNotEmpty,
    );
    expect(
      page.items.where((message) => message.attachments.isNotEmpty),
      isNotEmpty,
    );
  });

  test('limit 截取最近消息并给出 hasOlder', () async {
    final core = DemoCore.withDemoSeed();
    final page = await core.messages.getMessagePage(
      'demo-conversation-xiaoru',
      limit: 2,
    );
    expect(page.items, hasLength(2));
    expect(page.hasOlder, isTrue);
    expect(page.hasNewer, isFalse);
  });

  test('before 游标向更早翻页', () async {
    final core = DemoCore.withDemoSeed();
    final all = await core.messages.getMessagePage('demo-conversation-xiaoru');
    final cursor = all.items.last.id;
    final older = await core.messages.getMessagePage(
      'demo-conversation-xiaoru',
      limit: 2,
      beforeMessageId: cursor,
    );
    expect(older.items, hasLength(2));
    expect(older.hasNewer, isTrue);
    expect(older.items.any((message) => message.id == cursor), isFalse);
  });

  test('保存/更新/删除/清空消息', () async {
    final core = DemoCore.withDemoSeed();
    final saved = await core.messages.saveMessage(
      'demo-conversation-alan',
      'user',
      '新消息',
    );
    var page = await core.messages.getMessagePage('demo-conversation-alan');
    expect(page.items.last.id, saved.id);

    await core.messages.updateMessage(saved.id, '改过的消息');
    page = await core.messages.getMessagePage('demo-conversation-alan');
    expect(page.items.last.content, '改过的消息');

    await core.messages.deleteMessage(saved.id);
    await expectLater(core.messages.deleteMessage(saved.id), throwsStateError);

    await core.messages.saveMessage(
      'demo-conversation-alan',
      'assistant',
      '回复',
      answerStatus: 'completed',
    );
    await core.messages.clearMessages('demo-conversation-alan');
    page = await core.messages.getMessagePage('demo-conversation-alan');
    expect(page.items, isEmpty);
  });

  test('非法角色与游标组合被拒绝', () async {
    final core = DemoCore.withDemoSeed();
    await expectLater(
      core.messages.saveMessage('demo-conversation-alan', 'robot', 'x'),
      throwsArgumentError,
    );
    await expectLater(
      core.messages.getMessagePage(
        'demo-conversation-alan',
        beforeMessageId: 'a',
        afterMessageId: 'b',
      ),
      throwsArgumentError,
    );
  });
}
