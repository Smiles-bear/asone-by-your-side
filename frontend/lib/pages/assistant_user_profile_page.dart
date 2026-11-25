import '../widgets/unsaved_changes_guard.dart';
import 'package:asone_contracts/asone_contracts.dart'
    show Assistant, AssistantRepositoryApi, OpenCoreBinding;
import 'package:flutter/material.dart';

import '../widgets/asone_app_bar.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';

import '../theme/asone_theme.dart';

class AssistantUserProfilePage extends StatefulWidget {
  final Assistant assistant;
  final AssistantRepositoryApi? assistants;

  const AssistantUserProfilePage({
    super.key,
    required this.assistant,
    this.assistants,
  });

  @override
  State<AssistantUserProfilePage> createState() =>
      _AssistantUserProfilePageState();
}

class _AssistantUserProfilePageState extends State<AssistantUserProfilePage> {
  late final AssistantRepositoryApi _api =
      widget.assistants ?? OpenCoreBinding.instance.assistants;
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final profile = await _api.getUserProfile(widget.assistant.id);
      if (!mounted) return;
      setState(() {
        _controller.text = profile;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
        _toast('加载失败');
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || _loadFailed) return;
    setState(() => _saving = true);
    try {
      await _api.updateUserProfile(
        widget.assistant.id,
        userProfile: _controller.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      _toast('保存失败，请稍后重试');
      setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    AsOneToast.show(context, message, icon: AsOneIconName.warning);
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      snapshot: () => [_controller.text],
      ready: !_loading && !_loadFailed,
      saving: _saving,
      onSave: _save,
      child: Scaffold(
        appBar: AsOneAppBar(
          title: '用户资料',
          actions: [
            TextButton(
              onPressed: _saving || _loading || _loadFailed ? null : _save,
              child: const Text('保存'),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
            ? Center(
                child: TextButton(onPressed: _load, child: const Text('加载失败')),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.assistant.name} 会在对话中参考这里的信息。',
                      style: AsOneTheme.secondaryStyle,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: '写下希望助手了解的个人资料…',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
