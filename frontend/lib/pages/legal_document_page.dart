import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';

class LegalDocumentDefinition {
  const LegalDocumentDefinition({required this.title, required this.assetPath});

  final String title;
  final String assetPath;
}

class LegalDocuments {
  const LegalDocuments._();

  static const privacyPolicy = LegalDocumentDefinition(
    title: '隐私政策',
    assetPath: 'assets/legal/privacy_policy.md',
  );
  static const userAgreement = LegalDocumentDefinition(
    title: '用户协议',
    assetPath: 'assets/legal/user_agreement.md',
  );
  static const childrenPrivacyRules = LegalDocumentDefinition(
    title: '未成年人个人信息保护规则',
    assetPath: 'assets/legal/children_privacy_rules.md',
  );
  static const personalInformationList = LegalDocumentDefinition(
    title: '个人信息处理清单',
    assetPath: 'assets/legal/personal_information_list.md',
  );
  static const thirdPartyServices = LegalDocumentDefinition(
    title: '第三方服务与组件清单',
    assetPath: 'assets/legal/third_party_services.md',
  );
  static const permissionsList = LegalDocumentDefinition(
    title: '权限使用清单',
    assetPath: 'assets/legal/permissions_list.md',
  );
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.document});

  final LegalDocumentDefinition document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AsOneAppBar(title: document.title),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(document.assetPath),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('协议内容加载失败，请重新打开'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Markdown(
            data: snapshot.data!,
            selectable: true,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            styleSheet: MarkdownStyleSheet(
              h1: AsOneTheme.displayTitleStyle,
              h2: AsOneTheme.sectionTitleStyle.copyWith(height: 1.8),
              h3: AsOneTheme.listTitleStyle,
              p: AsOneTheme.bodyStyle,
              listBullet: AsOneTheme.bodyStyle,
              blockSpacing: 12,
              listIndent: 22,
            ),
          );
        },
      ),
    );
  }
}
