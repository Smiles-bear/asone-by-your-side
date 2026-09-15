import 'pages/model_service_list_page.dart';
import 'package:flutter/material.dart';

import 'community_diary_page.dart';
import 'community_group_page.dart';

/// 社区版功能页：只展示已经公开且可在本地独立运行的功能。
class CommunityFeaturePage extends StatelessWidget {
  const CommunityFeaturePage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('功能'), automaticallyImplyLeading: false),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '社区版功能',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text('所有公开数据保存在本机；不包含记忆、语音、设备控制或后台主动能力。'),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            key: const Key('community-feature-group-chat'),
            leading: const Icon(Icons.groups_outlined),
            title: const Text('API 群聊'),
            subtitle: const Text('多个已配置模型按顺序参与对话'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const CommunityGroupPage()),
          ),
        ),
        Card(
          child: ListTile(
            key: const Key('community-feature-diary'),
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('对话日记'),
            subtitle: const Text('仅根据近期对话生成'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const CommunityDiaryPage()),
          ),
        ),
        Card(
          child: ListTile(
            key: const Key('community-feature-model-services'),
            leading: const Icon(Icons.tune_outlined),
            title: const Text('模型服务'),
            subtitle: const Text('配置你自己的 API'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const ModelServiceListPage()),
          ),
        ),
      ],
    ),
  );
}
