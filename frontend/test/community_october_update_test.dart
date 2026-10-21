import 'dart:convert';
import 'dart:typed_data';
import 'package:azruiyoi_community/local_core/import/parsers/parser_models.dart';
import 'package:azruiyoi_community/local_core/import/parsers/parser_registry.dart';
import 'package:azruiyoi_community/local_core/import/parsers/dated_speaker_text.dart';
import 'package:azruiyoi_community/services/model_endpoint.dart';
import 'package:azruiyoi_community/services/provider_adapters/protocol_types.dart';
import 'package:azruiyoi_community/widgets/asone_chat_composer_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('协议选择优先显式偏好，并按Gemini地址确定自动候选', () {
    expect(
      modelProtocolCandidates(
        baseUrl: 'https://relay.test/v1beta',
        modelId: 'gemini-test',
      ).first,
      ProtocolType.gemini,
    );
    expect(
      modelProtocolCandidates(
        baseUrl: 'https://relay.test/v1beta',
        modelId: 'gemini-test',
        preference: ProtocolType.openaiChat,
      ),
      [ProtocolType.openaiChat],
    );
    expect(
      modelProtocolCandidates(
        baseUrl: 'https://relay.test/v1',
        modelId: 'gemini-test',
      ).first,
      ProtocolType.openaiChat,
    );
    expect(
      () => modelProtocolCandidates(
        baseUrl: 'https://relay.test',
        modelId: 'test',
        preference: 'invalid',
      ),
      throwsA(isA<ModelEndpointException>()),
    );
  });

  test('日期说话人记录保持正文标记与多行内容，具名角色需要确认', () async {
    const body =
        '示例聊天\n\n2026年10月14日 12:00:01 · 小明\n\n'
        '你好\n## User:\n▶ ASSISTANT:\n姓名：这是正文\n\n'
        '2026年10月14日 12:01:02 · 小悠\n\n回复\n第二行';
    final source = ImportFileSource(
      name: 'history.txt',
      bytes: Uint8List.fromList(utf8.encode(body)),
    );
    final parser = ParserRegistry.defaults().select(source);
    final parsed = await parser.parse(
      source,
      limits: const ImportParserLimits(),
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.uncertainRoles, {'小明', '小悠'});
    final messages = parsed.bundle.conversations.single.messages;
    expect(messages, hasLength(2));
    expect(messages.first.content, '你好\n## User:\n▶ ASSISTANT:\n姓名：这是正文');
    expect(messages.last.content, '回复\n第二行');
    expect(messages.first.createdAt, DateTime.utc(2026, 10, 14, 12, 0, 1));
    expect(parseDatedSpeakerTextHeader('2026年2月30日 12:00:00 · 小明'), isNull);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('窄屏字体倍率$scale 多行输入左侧固定底部，发送仍然可用', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: '一行文字');
      var sent = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AsOneChatInputBar(
                  controller: controller,
                  busy: false,
                  voiceEnabled: false,
                  attachmentMenuOpen: false,
                  onSend: () => sent++,
                  onStop: () {},
                  onAdd: () {},
                  onVoiceStart: () async => false,
                  onVoiceFinish: () async {},
                  onVoiceToText: () async {},
                  onVoiceCancel: () async {},
                  onVoiceAmplitude: () => const Stream<double>.empty(),
                  addButtonKey: GlobalKey(),
                ),
              ),
            ),
          ),
        ),
      );
      final add = find.byKey(const Key('chat-add-button'));
      final before = tester.getRect(add);
      controller.text = List.filled(8, '多行聊天内容').join('\n');
      await tester.pump();
      final after = tester.getRect(add);
      expect(after.bottom, closeTo(before.bottom, .1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('chat-send-button')));
      expect(sent, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
