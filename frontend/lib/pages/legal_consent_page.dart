import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/asone_theme.dart';
import '../widgets/asone_button.dart';
import '../widgets/asone_surface.dart';
import 'legal_document_page.dart';

class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({
    super.key,
    required this.onAgree,
    required this.onDecline,
  });

  final Future<void> Function() onAgree;
  final VoidCallback onDecline;

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  bool _agreeing = false;

  void _open(LegalDocumentDefinition document) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(document: document),
      ),
    );
  }

  Future<void> _agree() async {
    if (_agreeing) return;
    setState(() => _agreeing = true);
    await widget.onAgree();
    if (mounted) setState(() => _agreeing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Center(
                      child: SizedBox(
                        width: 150,
                        height: 72,
                        child: SvgPicture.asset(
                          'assets/icons/如一AsOne APP图标切图-24.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '欢迎使用 Azruiyoi',
                      textAlign: TextAlign.center,
                      style: AsOneTheme.displayTitleStyle,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '在开始前，请了解我们如何保护你的信息。',
                      textAlign: TextAlign.center,
                      style: AsOneTheme.secondaryStyle,
                    ),
                    const SizedBox(height: 24),
                    AsOneSurface(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '隐私说明',
                            style: AsOneTheme.sectionTitleStyle,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Azruiyoi 以手机本地处理为主。使用第三方模型、远程语音或远程工具时，必要内容会由你的设备发送给你选择的服务。麦克风、健康、通知、屏幕等权限只在对应功能中按需使用。',
                            style: AsOneTheme.bodyStyle,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              _LegalLink(
                                label: '《用户协议》',
                                onTap: () =>
                                    _open(LegalDocuments.userAgreement),
                              ),
                              _LegalLink(
                                label: '《隐私政策》',
                                onTap: () =>
                                    _open(LegalDocuments.privacyPolicy),
                              ),
                              _LegalLink(
                                label: '《未成年人个人信息保护规则》',
                                onTap: () =>
                                    _open(LegalDocuments.childrenPrivacyRules),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '不满十四周岁的未成年人，请由监护人阅读并同意后使用。',
                            style: AsOneTheme.captionStyle.copyWith(
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AsOneButton(
                label: '同意并继续',
                onPressed: _agreeing ? null : _agree,
                loading: _agreeing,
                expand: true,
              ),
              const SizedBox(height: 8),
              AsOneButton(
                label: '不同意并退出',
                onPressed: _agreeing ? null : widget.onDecline,
                tone: AsOneButtonTone.ghost,
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
