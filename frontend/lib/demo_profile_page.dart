import 'package:asone_contracts/asone_contracts.dart';
import 'pages/model_service_list_page.dart';
import 'package:flutter/material.dart';

import 'public_core.dart';
import 'community_diary_page.dart';
import 'community_import_page.dart';

/// 社区演示版"我的"页：只包含公开域入口。
class DemoProfilePage extends StatelessWidget {
  const DemoProfilePage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  void _openImport(BuildContext context) {
    final core = OpenCoreBinding.instance;
    if (core is! PublicCore) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导入功能需要社区版本地核心。')));
      return;
    }
    _open(context, CommunityImportPage(core: core));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('我的')),
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
              '社区版：聊天、群聊、模型服务和导入数据保存在本机；'
              '不包含记忆、语音、设备控制和后台主动能力。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('demo-profile-model-services'),
            title: const Text('模型服务'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const ModelServiceListPage()),
          ),
          ListTile(
            key: const Key('community-profile-import-chat'),
            title: const Text('导入聊天记录'),
            subtitle: const Text('从本地文件或公开分享链接迁移'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openImport(context),
          ),
          ListTile(
            key: const Key('community-profile-diary'),
            title: const Text('对话日记'),
            subtitle: const Text('仅根据近期对话生成'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const CommunityDiaryPage()),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('本地数据与隐私'),
            subtitle: Text('API 密钥由系统安全存储保管；聊天数据仅保存在本机。'),
          ),
        ],
      ),
    );
  }
}
