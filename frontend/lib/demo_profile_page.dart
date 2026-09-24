import 'package:asone_contracts/asone_contracts.dart';
import 'pages/model_service_list_page.dart';
import 'pages/token_usage_page.dart';
import 'pages/user_profile_edit_page.dart';
import 'services/user_identity_service.dart';
import 'theme/asone_theme.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_avatar.dart';
import 'widgets/asone_icons.dart';
import 'widgets/asone_settings_section.dart';
import 'widgets/asone_surface.dart';
import 'package:flutter/material.dart';

import 'public_core.dart';
import 'community_diary_page.dart';
import 'community_import_page.dart';

/// 社区版"我的"页：沿用正式版的个人信息卡片和设置分组，只展示公开能力。
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
      backgroundColor: AsOneTheme.mainPageBg,
      appBar: const AsOneAppBar(title: '我的', mainPage: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          ValueListenableBuilder<UserIdentity>(
            valueListenable: UserIdentityService.instance.notifier,
            builder: (context, identity, child) => AsOneSurface(
              padding: EdgeInsets.zero,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _open(context, const UserProfileEditPage()),
                  child: SizedBox(
                    height: 92,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          AsOneAvatar(
                            imagePath: identity.avatarPath,
                            size: 58,
                            borderRadius: 14,
                            fallbackIcon: Icons.person,
                            fallbackColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            backgroundColor: AsOneTheme.cardBg,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  identity.nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 20,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '账号：${identity.accountNumber}',
                                  style: AsOneTheme.secondaryStyle,
                                ),
                              ],
                            ),
                          ),
                          const AsOneIcon(
                            AsOneIconName.forward,
                            color: AsOneTheme.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '聊天、群聊、模型服务和导入数据保存在本机；记忆、语音、设备控制和后台主动能力暂未开放。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          AsOneSettingsSection(
            label: '服务与数据',
            children: [
              AsOneSettingsTile(
                key: const Key('demo-profile-model-services'),
                icon: AsOneIconName.sliders,
                title: '模型服务',
                subtitle: '管理多个 API 模型配置',
                onTap: () => _open(context, const ModelServiceListPage()),
              ),
              AsOneSettingsTile(
                key: const Key('community-profile-import-chat'),
                icon: AsOneIconName.download,
                title: '导入聊天记录',
                subtitle: '从本地文件或公开分享链接迁移',
                onTap: () => _openImport(context),
              ),
              AsOneSettingsTile(
                key: const Key('community-profile-diary'),
                icon: AsOneIconName.edit,
                title: '对话日记',
                subtitle: '仅根据近期对话生成',
                onTap: () => _open(context, const CommunityDiaryPage()),
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.data,
                title: '用量统计',
                subtitle: '查看本机 API 调用用量',
                onTap: () => _open(context, const TokenUsagePage()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AsOneSettingsSection(
            label: '社区版范围',
            children: [
              const AsOneSettingsTile(
                icon: AsOneIconName.key,
                title: '本地数据与隐私',
                subtitle: 'API 密钥由系统安全存储保管；聊天数据仅保存在本机。',
                onTap: null,
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.settings,
                title: '设置',
                subtitle: '部分系统设置暂未开放',
                onTap: () => _open(context, const CommunitySettingsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CommunitySettingsPage extends StatelessWidget {
  const CommunitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.mainPageBg,
      appBar: const AsOneAppBar(title: '设置'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          AsOneSettingsSection(
            label: '社区版已开放',
            children: [
              AsOneSettingsTile(
                icon: AsOneIconName.sliders,
                title: '模型服务',
                subtitle: '管理多个 API 模型配置',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const ModelServiceListPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const AsOneSettingsSection(
            label: '暂未开放',
            children: [
              AsOneSettingsTile(
                icon: AsOneIconName.voice,
                title: '语音服务',
                subtitle: '社区版暂未开放',
                enabled: false,
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.data,
                title: '后台主动能力与设备控制',
                subtitle: '社区版暂未开放',
                enabled: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
