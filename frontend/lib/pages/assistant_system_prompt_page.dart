import 'dart:async';

import 'package:asone_contracts/asone_contracts.dart'
    show Assistant, AssistantRepositoryApi, OpenCoreBinding;
import 'package:flutter/material.dart';

import '../widgets/asone_app_bar.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';

import '../theme/asone_theme.dart';

class AssistantSystemPromptPage extends StatefulWidget {
  final Assistant assistant;
  final AssistantRepositoryApi? assistants;

  const AssistantSystemPromptPage({
    super.key,
    required this.assistant,
    this.assistants,
  });

  @override
  State<AssistantSystemPromptPage> createState() =>
      _AssistantSystemPromptPageState();
}

class _AssistantSystemPromptPageState extends State<AssistantSystemPromptPage>
    with WidgetsBindingObserver {
  late final AssistantRepositoryApi _api =
      widget.assistants ?? OpenCoreBinding.instance.assistants;
  final _instructionsController = TextEditingController();
  final _communicationController = TextEditingController();
  final _boundaryController = TextEditingController();
  bool _saving = false;
  bool _closing = false;
  Timer? _saveTimer;
  late Assistant _latestAssistant;
  late String _lastSaved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _latestAssistant = widget.assistant;
    _instructionsController.text = widget.assistant.systemPrompt;
    _communicationController.text = widget.assistant.communicationStyle;
    _boundaryController.text = widget.assistant.behaviorBoundaries;
    _lastSaved = _snapshot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _instructionsController.dispose();
    _communicationController.dispose();
    _boundaryController.dispose();
    super.dispose();
  }

  String _snapshot() => [
    _instructionsController.text.trim(),
    _communicationController.text.trim(),
    _boundaryController.text.trim(),
  ].join('\u0000');

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveNow());
    });
    if (mounted) setState(() {});
  }

  Future<bool> _saveNow() async {
    final snapshot = _snapshot();
    if (snapshot == _lastSaved) return true;
    if (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return _saveNow();
    }
    if (mounted) setState(() => _saving = true);
    try {
      final updated = await _api.updateAssistant(widget.assistant.id, {
        'system_prompt': _instructionsController.text.trim(),
        'communication_style': _communicationController.text.trim(),
        'behavior_boundaries': _boundaryController.text.trim(),
      });
      _latestAssistant = updated;
      _lastSaved = snapshot;
      if (mounted) setState(() => _saving = false);
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _saving = false);
      AsOneToast.show(context, '系统设定保存失败，请稍后重试', icon: AsOneIconName.warning);
      return false;
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _saveTimer?.cancel();
    final saved = await _saveNow();
    if (!mounted) return;
    _closing = false;
    if (saved) Navigator.pop(context, _latestAssistant);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveTimer?.cancel();
      unawaited(_saveNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AsOneAppBar(
          leading: AsOneIconButton(
            icon: AsOneIconName.back,
            tooltip: '返回',
            onPressed: _close,
          ),
          title: '系统设定',
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _PromptField(
              title: '自定义指令',
              hint: '例如：你是谁、需要长期遵循什么设定',
              controller: _instructionsController,
              onChanged: _scheduleSave,
              onEditingComplete: _saveNow,
            ),
            const SizedBox(height: 18),
            _PromptField(
              title: '沟通偏好',
              hint: '例如：称呼方式、语气、回复长短',
              controller: _communicationController,
              onChanged: _scheduleSave,
              onEditingComplete: _saveNow,
            ),
            const SizedBox(height: 18),
            _PromptField(
              title: '行为边界',
              hint: '例如：哪些事要先确认、哪些内容不要主动提及',
              controller: _boundaryController,
              onChanged: _scheduleSave,
              onEditingComplete: _saveNow,
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptField extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Future<bool> Function() onEditingComplete;

  const _PromptField({
    required this.title,
    required this.hint,
    required this.controller,
    required this.onChanged,
    required this.onEditingComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AsOneTheme.sectionTitleStyle),
        const SizedBox(height: 9),
        TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          onChanged: (_) => onChanged(),
          onEditingComplete: () => unawaited(onEditingComplete()),
          onTapOutside: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            unawaited(onEditingComplete());
          },
          decoration: InputDecoration(hintText: hint, alignLabelWithHint: true),
        ),
      ],
    );
  }
}
