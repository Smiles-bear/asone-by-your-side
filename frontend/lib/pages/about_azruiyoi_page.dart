import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/legal_external_link_service.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_settings_section.dart';
import '../widgets/asone_surface.dart';
import 'legal_document_page.dart';

class AboutAzruiyoiPage extends StatefulWidget {
  const AboutAzruiyoiPage({super.key});

  @override
  State<AboutAzruiyoiPage> createState() => _AboutAzruiyoiPageState();
}

class _AboutAzruiyoiPageState extends State<AboutAzruiyoiPage> {
  static const _filingNumber = '鄂ICP备2026043111号-2A';
  static const _filingUrl = 'https://beian.miit.gov.cn/';
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((value) {
      if (mounted) setState(() => _packageInfo = value);
    });
  }

  void _openDocument(LegalDocumentDefinition document) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(document: document),
      ),
    );
  }

  Future<void> _openFiling() async {
    if (await LegalExternalLinkService.open(_filingUrl)) return;
    await Clipboard.setData(const ClipboardData(text: _filingNumber));
    if (mounted) {
      AsOneToast.show(context, '备案查询页打开失败，备案号已复制', icon: AsOneIconName.copy);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _packageInfo;
    return Scaffold(
      appBar: const AsOneAppBar(title: '关于 Azruiyoi'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Center(
            child: SizedBox(
              width: 166,
              height: 80,
              child: SvgPicture.asset(
                'assets/icons/如一AsOne APP图标切图-24.svg',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Azruiyoi',
            textAlign: TextAlign.center,
            style: AsOneTheme.displayTitleStyle,
          ),
          const SizedBox(height: 6),
          Text(
            info == null
                ? '正在读取版本信息…'
                : '版本 ${info.version} (${info.buildNumber})',
            textAlign: TextAlign.center,
            style: AsOneTheme.secondaryStyle,
          ),
          const SizedBox(height: 26),
          const AsOneSectionTitle('应用信息'),
          AsOneSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const _InfoRow(label: '运营者', value: '京山市如一软件科技有限公司'),
                const Divider(height: 24),
                const _InfoRow(label: '联系邮箱', value: '851591039@qq.com'),
                const Divider(height: 24),
                _InfoRow(
                  label: 'APP备案号',
                  value: _filingNumber,
                  onTap: _openFiling,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          AsOneSettingsSection(
            label: '协议',
            children: [
              AsOneSettingsTile(
                icon: AsOneIconName.document,
                title: '隐私政策',
                onTap: () => _openDocument(LegalDocuments.privacyPolicy),
              ),
              AsOneSettingsTile(
                icon: AsOneIconName.document,
                title: '用户协议',
                onTap: () => _openDocument(LegalDocuments.userAgreement),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Text(
            '© 2026 京山市如一软件科技有限公司',
            textAlign: TextAlign.center,
            style: AsOneTheme.captionStyle,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(label, style: AsOneTheme.secondaryStyle),
            ),
            Expanded(
              child: Text(
                value,
                style: AsOneTheme.bodyStyle.copyWith(
                  color: onTap == null
                      ? null
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: AsOneIcon(
                  AsOneIconName.link,
                  size: 18,
                  color: AsOneTheme.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
