import 'package:flutter/material.dart';

import '../models/assistant.dart';
import '../services/debug_logger.dart';
import '../theme/asone_theme.dart';
import '../widgets/mind_source_identity.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';

class StickyNoteEditorPage extends StatefulWidget {
  const StickyNoteEditorPage({
    super.key,
    required this.repository,
    this.detail,
    this.assistants = const {},
  });

  final StickyNoteRepositoryApi repository;
  final StickyNoteDetail? detail;
  final Map<String, Assistant> assistants;

  @override
  State<StickyNoteEditorPage> createState() => _StickyNoteEditorPageState();
}

class _ChecklistDraft {
  _ChecklistDraft(String text, {this.checked = false})
    : controller = TextEditingController(text: text);

  final TextEditingController controller;
  bool checked;
}

class _StickyNoteEditorPageState extends State<StickyNoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final List<_ChecklistDraft> _items = [];
  late String _type;
  DateTime? _expiresAt;
  bool _dirty = false;
  bool _saving = false;

  bool get _editing => widget.detail != null;

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    _title = TextEditingController(text: detail?.note.title ?? '');
    _body = TextEditingController(text: detail?.note.content ?? '');
    _type = detail?.note.noteType ?? 'text';
    _expiresAt = detail?.note.expiresAt?.toLocal();
    if (detail?.items.isNotEmpty == true) {
      _items.addAll(
        detail!.items.map(
          (item) => _ChecklistDraft(item.content, checked: item.checked),
        ),
      );
    } else {
      _items.add(_ChecklistDraft(''));
    }
    _title.addListener(_changed);
    _body.addListener(_changed);
    for (final item in _items) {
      item.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    for (final item in _items) {
      item.controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saving) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AsOneDialog(
        icon: asOneIconData(AsOneIconName.edit),
        title: '保存这次修改？',
        content: const Text('离开前可以保存，或放弃未保存的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (action == 'discard') return true;
    if (action == 'save') return _save(pop: false);
    return false;
  }

  void _switchType(String type) {
    if (type == _type) return;
    setState(() {
      if (type == 'checklist') {
        final lines = _body.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        for (final item in _items) {
          item.controller.dispose();
        }
        _items
          ..clear()
          ..addAll((lines.isEmpty ? [''] : lines).map(_newDraft));
      } else {
        _body.text = _items
            .map((item) => item.controller.text.trim())
            .where((text) => text.isNotEmpty)
            .join('\n');
      }
      _type = type;
      _dirty = true;
    });
  }

  _ChecklistDraft _newDraft(String text) {
    final draft = _ChecklistDraft(text);
    draft.controller.addListener(_changed);
    return draft;
  }

  void _addItem() => setState(() {
    _items.add(_newDraft(''));
    _dirty = true;
  });

  Future<void> _pickExpiry() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择有效日期',
    );
    if (selected == null) return;
    setState(() {
      _expiresAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        23,
        59,
      );
      _dirty = true;
    });
  }

  Future<bool> _save({bool pop = true}) async {
    final checklist = _items
        .map(
          (item) => StickyNoteChecklistDraft(
            content: item.controller.text,
            checked: item.checked,
          ),
        )
        .where((item) => item.content.trim().isNotEmpty)
        .toList();
    if ((_type == 'text' && _body.text.trim().isEmpty) ||
        (_type == 'checklist' && checklist.isEmpty)) {
      _showMessage('请填写纸条内容');
      return false;
    }
    setState(() => _saving = true);
    try {
      if (_editing) {
        await widget.repository.updateNote(
          noteId: widget.detail!.note.noteId,
          title: _title.text,
          noteType: _type,
          content: _body.text,
          checklistEntries: checklist,
          expiresAt: _expiresAt,
        );
      } else if (_type == 'text') {
        await widget.repository.createTextNote(
          title: _title.text,
          content: _body.text,
          authorType: 'user',
          expiresAt: _expiresAt,
        );
      } else {
        await widget.repository.createChecklistNote(
          title: _title.text,
          items: checklist.map((item) => item.content).toList(),
          checklistEntries: checklist,
          authorType: 'user',
          expiresAt: _expiresAt,
        );
      }
      _dirty = false;
      if (mounted && pop) Navigator.pop(context, true);
      return true;
    } catch (error) {
      DebugLogger.instance.error(
        '保存小纸条失败',
        tag: 'StickyNoteEditor',
        details: error.toString(),
      );
      _showMessage(error is StateError ? '纸条已不存在' : '保存失败，请稍后重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runPersistedAction(String action) async {
    final note = widget.detail!.note;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AsOneDialog(
          icon: asOneIconData(AsOneIconName.delete),
          iconColor: AsOneTheme.danger,
          title: '删除小纸条',
          content: const Text('删除后无法恢复，确定删除这张纸条吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AsOneTheme.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final changed = switch (action) {
        'complete' => await widget.repository.setCompletion(
          note.noteId,
          'completed',
        ),
        'cancel' => await widget.repository.setCompletion(
          note.noteId,
          'cancelled',
        ),
        'restore' => await widget.repository.restore(note.noteId),
        'delete' => await widget.repository.hardDelete(note.noteId),
        _ => false,
      };
      if (!changed) throw StateError('纸条已不存在');
      _dirty = false;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      DebugLogger.instance.error(
        '操作小纸条失败',
        tag: 'StickyNoteEditor',
        details: error.toString(),
      );
      _showMessage(error is StateError ? '纸条已不存在' : '操作失败，请稍后重试');
    }
  }

  void _showMessage(String message) {
    AsOneToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.detail?.note;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.pop(context, true);
        }
      },
      child: Scaffold(
        appBar: AsOneAppBar(
          title: _editing ? '编辑纸条' : '新建纸条',
          leading: AsOneIconButton(
            tooltip: '返回',
            icon: AsOneIconName.back,
            onPressed: () async {
              if (await _confirmLeave() && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
          actions: [
            if (note != null)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: _runPersistedAction,
                itemBuilder: (_) => [
                  if (!note.isCompleted) ...const [
                    PopupMenuItem(value: 'complete', child: Text('完成')),
                    PopupMenuItem(value: 'cancel', child: Text('取消')),
                  ] else
                    const PopupMenuItem(value: 'restore', child: Text('恢复')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除',
                      style: TextStyle(color: AsOneTheme.danger),
                    ),
                  ),
                ],
              ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                maxLength: 60,
                decoration: const InputDecoration(labelText: '标题（可选）'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'text', label: Text('文字')),
                  ButtonSegment(value: 'checklist', label: Text('清单')),
                ],
                selected: {_type},
                onSelectionChanged: (value) => _switchType(value.single),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _type == 'text'
                    ? TextField(
                        key: const ValueKey('text'),
                        controller: _body,
                        minLines: 8,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: '写下想记住的事',
                          alignLabelWithHint: true,
                        ),
                      )
                    : _ChecklistEditor(
                        key: const ValueKey('checklist'),
                        items: _items,
                        onChanged: () => setState(() => _dirty = true),
                        onAdd: _addItem,
                      ),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.event_outlined),
                title: const Text('有效日期'),
                subtitle: Text(
                  _expiresAt == null
                      ? '长期有效'
                      : '${_expiresAt!.year}年${_expiresAt!.month}月${_expiresAt!.day}日',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_expiresAt != null)
                      IconButton(
                        tooltip: '清除有效日期',
                        onPressed: () => setState(() {
                          _expiresAt = null;
                          _dirty = true;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      tooltip: '选择有效日期',
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              if (note != null) ...[
                const Divider(height: 28),
                Text('来源', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                MindSourceIdentity(
                  authorType: note.authorType,
                  authorAssistantId: note.authorAssistantId,
                  assistants: widget.assistants,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistEditor extends StatelessWidget {
  const _ChecklistEditor({
    super.key,
    required this.items,
    required this.onChanged,
    required this.onAdd,
  });

  final List<_ChecklistDraft> items;
  final VoidCallback onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          onReorderItem: (oldIndex, newIndex) {
            final item = items.removeAt(oldIndex);
            items.insert(newIndex, item);
            onChanged();
          },
          itemBuilder: (context, index) {
            final item = items[index];
            return Row(
              key: ObjectKey(item),
              children: [
                Checkbox(
                  value: item.checked,
                  onChanged: (value) {
                    item.checked = value ?? false;
                    onChanged();
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: item.controller,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => onAdd(),
                    decoration: InputDecoration(hintText: '清单项 ${index + 1}'),
                  ),
                ),
                IconButton(
                  tooltip: '删除清单项',
                  onPressed: items.length == 1
                      ? null
                      : () {
                          final removed = items.removeAt(index);
                          removed.controller.dispose();
                          onChanged();
                        },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                const Icon(Icons.drag_handle, color: AsOneTheme.textTertiary),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('新增项目'),
          ),
        ),
      ],
    );
  }
}
