import 'dart:convert';
import 'package:flutter/material.dart';
import 'asone_dialog.dart';

/// Guards explicit-save forms without changing their successful save/pop path.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.snapshot,
    required this.onSave,
    required this.child,
    this.ready = true,
    this.saving = false,
  });
  final Object? Function() snapshot;
  final Future<void> Function() onSave;
  final bool ready;
  final bool saving;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  String? _baseline;
  bool _handling = false;
  bool _allowPop = false;

  Future<void> _leave() async {
    if (_handling || widget.saving) return;
    _handling = true;
    try {
      final dirty =
          _baseline != null && jsonEncode(widget.snapshot()) != _baseline;
      final action = !dirty
          ? 'discard'
          : await showDialog<String>(
              context: context,
              builder: (context) => AsOneDialog(
                title: '保存这次修改？',
                content: const Text('离开前可以保存，或直接退出放弃修改。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'discard'),
                    child: const Text('直接退出'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, 'save'),
                    child: const Text('保存并退出'),
                  ),
                ],
              ),
            );
      if (!mounted) return;
      if (action == 'save') {
        await widget.onSave();
      } else if (action == 'discard') {
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ready) _baseline ??= jsonEncode(widget.snapshot());
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: widget.child,
    );
  }
}
