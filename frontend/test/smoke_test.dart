import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/pages/legal_consent_page.dart';
import 'package:azruiyoi_community/services/legal_consent_service.dart';
import 'package:azruiyoi_community/community_open_core.dart';
import 'package:azruiyoi_community/community_assistant_page.dart';
import 'package:azruiyoi_community/community_chat_page.dart';
import 'package:azruiyoi_community/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('未同意协议时停在法律同意页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OpenCoreBinding.attach(DemoCore.withDemoSeed());
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pump();
    expect(find.byType(LegalConsentPage), findsOneWidget);
  });

  testWidgets('已同意协议后可进入社区版功能页', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(DemoCore.withDemoSeed());
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('对话'), findsWidgets);

    await tester.tap(find.text('助手'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(CommunityAssistantListPage), findsOneWidget);

    await tester.tap(find.text('功能'));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(const Key('feature-tile-message_board')), findsOneWidget);
    expect(find.byKey(const Key('feature-tile-game')), findsOneWidget);
    expect(find.byKey(const Key('feature-tile-heartbeat')), findsOneWidget);
    expect(find.byKey(const Key('feature-tile-more_tools')), findsOneWidget);
  });

  testWidgets('聊天页在未配置真实 API 时引导用户配置模型服务', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(CommunityOpenCore(demo: DemoCore.withDemoSeed()));
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const MaterialApp(home: CommunityChatPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      find.byKey(const Key('community-chat-configure-model')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('community-chat-composer')), findsOneWidget);

    expect(find.byTooltip('更多'), findsOneWidget);
  });

  testWidgets('我的页列出公开入口', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(DemoCore.withDemoSeed());
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      find.byKey(const Key('demo-profile-model-services')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('community-profile-import-chat')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('community-profile-diary')), findsOneWidget);
    expect(find.textContaining('聊天、群聊、模型服务和导入数据保存在本机'), findsOneWidget);
  });

  testWidgets('我的页可进入模型服务并看到演示配置', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(CommunityOpenCore(demo: DemoCore.withDemoSeed()));
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.byKey(const Key('demo-profile-model-services')));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('模型服务'), findsWidgets);
  });
}
