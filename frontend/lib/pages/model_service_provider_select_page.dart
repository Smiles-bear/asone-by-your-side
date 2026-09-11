import 'package:flutter/material.dart';

import '../services/provider_definition.dart';
import '../services/provider_registry.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_surface.dart';
import 'model_service_new_page.dart';

/// 选择模型服务页：只显示 11 个服务商按钮。
class ModelServiceProviderSelectPage extends StatelessWidget {
  const ModelServiceProviderSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AsOneAppBar(
        title: '选择模型服务',
        leading: AsOneIconButton(
          icon: AsOneIconName.close,
          tooltip: '关闭',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          const AsOneSectionTitle(
            '选择服务商',
            subtitle: '选择 API Key 所属的服务，下一步填写连接信息。',
          ),
          AsOneSurface(
            padding: const EdgeInsets.all(10),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ProviderRegistry.all.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.7,
              ),
              itemBuilder: (context, index) {
                final provider = ProviderRegistry.all[index];
                return OutlinedButton(
                  onPressed: () => _selectProvider(context, provider),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AsOneTheme.textPrimary,
                    side: const BorderSide(color: Color(0xFFF0E5E0)),
                    backgroundColor: Colors.white,
                  ),
                  child: Text(
                    provider.displayName,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _selectProvider(BuildContext context, ProviderDefinition provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModelServiceNewPage(provider: provider),
      ),
    ).then((saved) {
      if (saved == true && context.mounted) {
        Navigator.pop(context, true);
      }
    });
  }
}
