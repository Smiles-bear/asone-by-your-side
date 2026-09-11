import 'package:asone_contracts/asone_contracts.dart';
import 'package:asone_demo_core/asone_demo_core.dart';
import 'package:azruiyoi_community/pages/legal_consent_page.dart';
import 'package:azruiyoi_community/services/legal_consent_service.dart';
import 'package:azruiyoi_community/community_open_core.dart';
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

  testWidgets('已同意协议进入功能页并可打开留言板看到种子数据', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(DemoCore.withDemoSeed());
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('功能'), findsWidgets);

    await tester.tap(find.byKey(const Key('feature-message-board-hit-target')));
    await tester.pumpAndSettle();
    expect(find.textContaining('欢迎使用留言板'), findsOneWidget);
  });

  testWidgets('我的页列出公开入口', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(DemoCore.withDemoSeed());
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('demo-profile-user-profile')), findsOneWidget);
    expect(find.byKey(const Key('demo-profile-token-usage')), findsOneWidget);
    expect(
      find.byKey(const Key('demo-profile-model-services')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('demo-profile-privacy')), findsOneWidget);
    expect(find.byKey(const Key('demo-profile-about')), findsOneWidget);
    expect(find.byKey(const Key('demo-profile-version')), findsOneWidget);
    expect(find.textContaining('社区演示版'), findsOneWidget);
  });

  testWidgets('我的页可进入模型服务并看到演示配置', (tester) async {
    SharedPreferences.setMockInitialValues({
      'legal.accepted_version': LegalConsentService.currentVersion,
    });
    OpenCoreBinding.attach(CommunityOpenCore(demo: DemoCore.withDemoSeed()));
    addTearDown(OpenCoreBinding.detach);

    await tester.pumpWidget(const CommunityPreviewApp());
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('demo-profile-model-services')));
    await tester.pumpAndSettle();

    expect(find.text('演示模型服务'), findsOneWidget);
  });
}
