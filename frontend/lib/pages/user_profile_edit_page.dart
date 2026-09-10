import 'package:flutter/material.dart';

import '../services/system_photo_picker.dart';
import '../services/user_identity_service.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_avatar.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_bottom_sheet.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_surface.dart';
import 'avatar_crop_page.dart';

class UserProfileEditPage extends StatefulWidget {
  const UserProfileEditPage({super.key});

  @override
  State<UserProfileEditPage> createState() => _UserProfileEditPageState();
}

class _UserProfileEditPageState extends State<UserProfileEditPage> {
  late final TextEditingController _nicknameController;
  String? _selectedAvatarPath;
  bool _restoreDefaultAvatar = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: UserIdentityService.instance.value.nickname,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    final choice = await AsOneBottomSheet.showActions<String>(
      context,
      title: '修改头像',
      actions: const [
        AsOneSheetAction(
          value: 'gallery',
          label: '从相册选择',
          icon: AsOneIconName.image,
        ),
        AsOneSheetAction(
          value: 'reset',
          label: '恢复默认头像',
          icon: AsOneIconName.restore,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'reset') {
      setState(() {
        _selectedAvatarPath = null;
        _restoreDefaultAvatar = true;
      });
      return;
    }
    String? sourcePath;
    try {
      sourcePath = await SystemPhotoPicker.pickImage();
    } catch (_) {
      if (mounted) {
        AsOneToast.show(context, '无法打开系统相册，请稍后重试', icon: AsOneIconName.warning);
      }
      return;
    }
    if (!mounted || sourcePath == null || sourcePath.isEmpty) return;
    final selectedPath = sourcePath;
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarCropPage(sourcePath: selectedPath),
      ),
    );
    if (!mounted || path == null) return;
    setState(() {
      _selectedAvatarPath = path;
      _restoreDefaultAvatar = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await UserIdentityService.instance.update(
        nickname: _nicknameController.text,
        selectedAvatarPath: _selectedAvatarPath,
        restoreDefaultAvatar: _restoreDefaultAvatar,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AsOneToast.show(context, '保存失败，请重新选择头像后再试', icon: AsOneIconName.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = UserIdentityService.instance.value;
    final displayedAvatar = _restoreDefaultAvatar
        ? ''
        : (_selectedAvatarPath ?? identity.avatarPath);
    return Scaffold(
      appBar: AsOneAppBar(
        title: '个人资料',
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                AsOneAvatar(
                  imagePath: displayedAvatar,
                  size: 84,
                  borderRadius: 20,
                  fallbackIcon: Icons.person,
                  fallbackColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: AsOneTheme.cardBg,
                ),
                TextButton(onPressed: _chooseAvatar, child: const Text('修改头像')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(
              labelText: '昵称',
              hintText: 'User',
            ),
          ),
          const SizedBox(height: 16),
          AsOneSurface(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: const Text('账号'),
              subtitle: Text(identity.accountNumber),
              leading: const AsOneIcon(AsOneIconName.user),
            ),
          ),
        ],
      ),
    );
  }
}
