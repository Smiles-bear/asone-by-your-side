import 'pages/about_azruiyoi_page.dart';
import 'pages/privacy_and_agreements_page.dart';
import 'pages/token_usage_page.dart';
import 'pages/user_profile_edit_page.dart';
import 'pages/version_info_page.dart';
import 'theme/asone_theme.dart';
import 'package:flutter/material.dart';

/// 社区演示版"我的"页：只包含公开域入口。
class DemoProfilePage extends StatelessWidget {
  const DemoProfilePage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.pageBg,
      appBar: AppBar(
        backgroundColor: AsOneTheme.pageBg,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text('我的'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF6EC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '社区演示版：数据为内存演示种子，重启后重置；'
              '聊天、记忆等完整能力请使用正式版。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('demo-profile-user-profile'),
            title: const Text('用户资料'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const UserProfileEditPage()),
          ),
          ListTile(
            key: const Key('demo-profile-token-usage'),
            title: const Text('Token 统计'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const TokenUsagePage()),
          ),
          ListTile(
            key: const Key('demo-profile-privacy'),
            title: const Text('隐私与协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const PrivacyAndAgreementsPage()),
          ),
          ListTile(
            key: const Key('demo-profile-about'),
            title: const Text('关于 Azruiyoi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const AboutAzruiyoiPage()),
          ),
          ListTile(
            key: const Key('demo-profile-version'),
            title: const Text('版本信息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const VersionInfoPage()),
          ),
        ],
      ),
    );
  }
}
