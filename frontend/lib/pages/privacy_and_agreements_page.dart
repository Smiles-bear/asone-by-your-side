import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/legal_consent_service.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_settings_section.dart';
import 'legal_document_page.dart';

class PrivacyAndAgreementsPage extends StatelessWidget {
  const PrivacyAndAgreementsPage({super.key});

  void _open(BuildContext context, LegalDocumentDefinition document) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(document: document),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AsOneDialog(
        icon: Icons.privacy_tip_outlined,
        title: '撤回隐私同意？',
        content: const Text('撤回后应用将退出，并在下次启动时重新询问。已有本地数据不会自动删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不撤回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('撤回并退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LegalConsentService.withdraw();
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AsOneAppBar(title: '隐私与协议'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          AsOneSettingsSection(
            label: '协议与规则',
            children: [
              AsOneSettingsTile(
                icon: AsOneIconName.document,
                title: '隐私政策',
                subtitle: '版本 V1.1 · 2026年9月6日生效',
                onTap: () => _open(context, LegalDocuments.privacyPolicy),
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.document,
                title: '用户协议',
                subtitle: '版本 V1.1 · 2026年9月6日生效',
                onTap: () => _open(context, LegalDocuments.userAgreement),
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.users,
                title: '未成年人个人信息保护规则',
                onTap: () =>
                    _open(context, LegalDocuments.childrenPrivacyRules),
              ),
            ],
          ),
          const SizedBox(height: 22),
          AsOneSettingsSection(
            label: '公开清单',
            children: [
              AsOneSettingsTile(
                icon: AsOneIconName.data,
                title: '个人信息处理清单',
                onTap: () =>
                    _open(context, LegalDocuments.personalInformationList),
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.link,
                title: '第三方服务与组件清单',
                onTap: () => _open(context, LegalDocuments.thirdPartyServices),
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.key,
                title: '权限使用清单',
                onTap: () => _open(context, LegalDocuments.permissionsList),
              ),
            ],
          ),
          const SizedBox(height: 22),
          AsOneSettingsSection(
            label: '隐私选择',
            children: [
              AsOneSettingsTile(
                icon: AsOneIconName.close,
                title: '撤回隐私同意',
                subtitle: '撤回后退出应用，不会自动删除本地数据',
                iconColor: Colors.redAccent,
                iconBackgroundColor: const Color(0xFFFFECEA),
                onTap: () => _withdraw(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
