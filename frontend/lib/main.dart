import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart' show OpenCoreBinding;
import 'pages/feature_page.dart';
import 'pages/legal_consent_page.dart';
import 'pages/conversation_list_page.dart';
import 'services/legal_consent_service.dart';
import 'theme/asone_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'community_conversation_routes.dart';
import 'community_assistant_page.dart';
import 'demo_profile_page.dart';
import 'public_core.dart';

/// 社区版入口（阶段 C 快照中将成为公共仓库的 main.dart）。
///
/// 公开聊天、模型服务与基础本地数据绑定 [PublicCore]；无后台任务与通知
/// 服务初始化，导航保留正式版的“聊天 + 助手 + 功能 + 我的”四个页签。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final core = PublicCore();
  await core.open();
  OpenCoreBinding.attach(core);
  attachCommunityConversationRoutes();
  runApp(const CommunityPreviewApp());
}

enum _PreviewPhase { loading, awaitingConsent, ready }

class CommunityPreviewApp extends StatefulWidget {
  const CommunityPreviewApp({super.key});

  @override
  State<CommunityPreviewApp> createState() => _CommunityPreviewAppState();
}

class _CommunityPreviewAppState extends State<CommunityPreviewApp> {
  _PreviewPhase _phase = _PreviewPhase.loading;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final accepted = await LegalConsentService.hasAcceptedCurrentVersion();
    if (!mounted) return;
    setState(() {
      _phase = accepted ? _PreviewPhase.ready : _PreviewPhase.awaitingConsent;
    });
  }

  Future<void> _acceptLegalDocuments() async {
    await LegalConsentService.acceptCurrentVersion();
    if (!mounted) return;
    setState(() => _phase = _PreviewPhase.ready);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Azruiyoi 社区演示版',
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AsOneTheme.light(AsOneTheme.accentFor('default')),
      home: switch (_phase) {
        _PreviewPhase.awaitingConsent => LegalConsentPage(
          onAgree: _acceptLegalDocuments,
          onDecline: SystemNavigator.pop,
        ),
        _PreviewPhase.ready => const PreviewShell(),
        _PreviewPhase.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class PreviewShell extends StatefulWidget {
  const PreviewShell({super.key});

  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 测试与嵌入式启动也可能直接挂载壳层，此处确保正式版列表路由始终完成接线。
    attachCommunityConversationRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          ConversationListPage(),
          CommunityAssistantListPage(),
          FeaturePage(routes: FeaturePageRoutes()),
          DemoProfilePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AsOneTheme.pageBg,
        selectedItemColor: AsOneTheme.accentFor('default'),
        unselectedItemColor: AsOneTheme.tabInactive,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          BottomNavigationBarItem(
            icon: _NavigationAssetIcon(
              path: _currentIndex == 0
                  ? 'assets/navigation/conversation_selected.png'
                  : 'assets/navigation/conversation_unselected.png',
            ),
            label: '对话',
          ),
          BottomNavigationBarItem(
            icon: _NavigationAssetIcon(
              path: _currentIndex == 1
                  ? 'assets/navigation/assistant_selected.png'
                  : 'assets/navigation/assistant_unselected.png',
            ),
            label: '助手',
          ),
          BottomNavigationBarItem(
            icon: _NavigationAssetIcon(
              path: _currentIndex == 2
                  ? 'assets/navigation/feature_selected.png'
                  : 'assets/navigation/feature_unselected.png',
            ),
            label: '功能',
          ),
          BottomNavigationBarItem(
            icon: _NavigationAssetIcon(
              path: _currentIndex == 3
                  ? 'assets/navigation/profile_selected.png'
                  : 'assets/navigation/profile_unselected.png',
            ),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _NavigationAssetIcon extends StatelessWidget {
  const _NavigationAssetIcon({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: 26,
      height: 26,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
