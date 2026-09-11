import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart' show OpenCoreBinding;
import 'package:asone_demo_core/asone_demo_core.dart';
import 'pages/feature_page.dart';
import 'pages/legal_consent_page.dart';
import 'services/legal_consent_service.dart';
import 'theme/asone_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'community_open_core.dart';
import 'demo_profile_page.dart';

/// 社区演示版入口（阶段 C 快照中将成为公共仓库的 main.dart）。
///
/// 绑定 DemoCore（内存演示数据），无后台任务与通知服务初始化，
/// 导航仅保留"功能 + 我的"两个公开页签。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OpenCoreBinding.attach(CommunityOpenCore(demo: DemoCore.withDemoSeed()));
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [FeaturePage(), DemoProfilePage()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AsOneTheme.pageBg,
        selectedItemColor: AsOneTheme.accentFor('default'),
        unselectedItemColor: AsOneTheme.tabInactive,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: '功能',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
