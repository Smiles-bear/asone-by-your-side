import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_surface.dart';

class VersionInfoPage extends StatefulWidget {
  const VersionInfoPage({super.key});

  @override
  State<VersionInfoPage> createState() => _VersionInfoPageState();
}

class _VersionInfoPageState extends State<VersionInfoPage> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AsOneAppBar(title: '版本信息'),
      body: _packageInfo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                // 应用图标
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
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _packageInfo!.appName,
                    style: AsOneTheme.displayTitleStyle,
                  ),
                ),
                const SizedBox(height: 32),

                // 版本信息
                const AsOneSectionTitle('应用信息'),
                _buildInfoCard([
                  _buildInfoRow('应用名称', _packageInfo!.appName),
                  _buildInfoRow('包名', _packageInfo!.packageName),
                  _buildInfoRow('版本号', _packageInfo!.version),
                  _buildInfoRow('构建号', _packageInfo!.buildNumber),
                ]),

                const SizedBox(height: 20),

                // 系统信息
                const AsOneSectionTitle('运行环境'),
                _buildInfoCard([
                  _buildInfoRow('Flutter版本', '3.22.0+'),
                  _buildInfoRow('Dart SDK', '3.4.0+'),
                ]),

                const SizedBox(height: 20),

                // 项目信息
                const AsOneSectionTitle('项目信息'),
                _buildInfoCard([
                  _buildInfoRow('项目名称', 'Azruiyoi'),
                  _buildInfoRow('版本', '1.0.0'),
                  _buildInfoRow('描述', 'Azruiyoi'),
                ]),

                const SizedBox(height: 32),

                // 版权信息
                const Center(
                  child: Text(
                    '© 2024 Azruiyoi',
                    style: AsOneTheme.secondaryStyle,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return AsOneSurface(
      padding: const EdgeInsets.all(16),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AsOneTheme.secondaryStyle),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: value));
                AsOneToast.show(context, '已复制到剪贴板', icon: AsOneIconName.copy);
              },
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
