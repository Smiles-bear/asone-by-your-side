import 'package:flutter/material.dart';

import '../models/assistant.dart';
import '../models/sticky_note_item.dart';
import '../services/debug_logger.dart';
import '../theme/asone_theme.dart';
import '../widgets/mind_source_identity.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';
import 'sticky_note_editor_page.dart';

class StickyNoteHistoryPage extends StatefulWidget {
  const StickyNoteHistoryPage({
    super.key,
    required this.repository,
    this.assistants = const {},
  });

  final StickyNoteRepositoryApi repository;
  final Map<String, Assistant> assistants;

  @override
  State<StickyNoteHistoryPage> createState() => _StickyNoteHistoryPageState();
}

class _StickyNoteHistoryPageState extends State<StickyNoteHistoryPage> {
  List<StickyNoteDetail> _details = const [];
  bool _completedOnly = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final notes = await widget.repository.listHistory(
        completedOnly: _completedOnly,
      );
      final details = await Future.wait(
        notes.map((note) => widget.repository.loadDetail(note.noteId)),
      );
      if (!mounted) return;
      setState(() {
        _details = details.whereType<StickyNoteDetail>().toList();
        _loading = false;
      });
    } catch (error) {
      DebugLogger.instance.error(
        '加载历史纸条失败',
        tag: 'StickyNoteHistory',
        details: error.toString(),
      );
      if (!mounted) return;
      setState(() => _loading = false);
      _message('加载失败，请稍后重试');
    }
  }

  Future<void> _restore(StickyNoteItem note) async {
    try {
      if (!await widget.repository.restore(note.noteId)) {
        _message('纸条已不存在');
      }
    } catch (error) {
      DebugLogger.instance.error(
        '恢复历史纸条失败',
        tag: 'StickyNoteHistory',
        details: error.toString(),
      );
      _message(error is StateError ? '纸条已不存在' : '恢复失败，请稍后重试');
    }
    await _load();
  }

  Future<void> _setChecked(String itemId, bool checked) async {
    try {
      await widget.repository.setChecklistItemChecked(itemId, checked);
    } catch (error) {
      DebugLogger.instance.error(
        '勾选历史清单失败',
        tag: 'StickyNoteHistory',
        details: error.toString(),
      );
      _message(error is StateError ? '纸条已不存在' : '操作失败，请稍后重试');
    }
    await _load();
  }

  Future<void> _open(StickyNoteDetail detail) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StickyNoteEditorPage(
          repository: widget.repository,
          detail: detail,
          assistants: widget.assistants,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.pageBg,
      appBar: AsOneAppBar(
        title: '历史纸条',
        leading: AsOneIconButton(
          icon: AsOneIconName.back,
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('全部')),
                ButtonSegment(value: true, label: Text('已完成')),
              ],
              selected: {_completedOnly},
              onSelectionChanged: (value) {
                setState(() {
                  _completedOnly = value.single;
                  _loading = true;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _details.isEmpty
                ? const Center(child: Text('还没有历史纸条'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: _details.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final detail = _details[index];
                        final note = detail.note;
                        return Card(
                          color: AsOneTheme.selectedBg,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _open(detail),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          note.title ??
                                              (note.content.isEmpty
                                                  ? '清单'
                                                  : note.content),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AsOneTheme.listTitleStyle,
                                        ),
                                      ),
                                      _StatusLabel(note: note),
                                      if (note.isCompleted)
                                        IconButton(
                                          tooltip: '恢复纸条',
                                          onPressed: () => _restore(note),
                                          icon: const Icon(Icons.restore),
                                        ),
                                    ],
                                  ),
                                  if (detail.items.isNotEmpty)
                                    ...detail.items
                                        .take(3)
                                        .map(
                                          (item) => Row(
                                            children: [
                                              Checkbox(
                                                value: item.checked,
                                                onChanged: (checked) =>
                                                    _setChecked(
                                                      item.itemId,
                                                      checked ?? false,
                                                    ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  item.content,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: MindSourceIdentity(
                                          authorType: note.authorType,
                                          authorAssistantId:
                                              note.authorAssistantId,
                                          assistants: widget.assistants,
                                          compact: true,
                                        ),
                                      ),
                                      if (note.completedAt != null)
                                        Text(
                                          _date(note.completedAt!),
                                          style: AsOneTheme.microStyle,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }

  void _message(String text) {
    if (!mounted) return;
    AsOneToast.show(context, text);
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.note});

  final StickyNoteItem note;

  @override
  Widget build(BuildContext context) {
    final label = switch (note.completionReason) {
      'cancelled' => '已取消',
      'expired' => '已到期',
      'completed' => '已完成',
      _ => '进行中',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          note.isCompleted ? Icons.check_circle_outline : Icons.schedule,
          size: 16,
          color: AsOneTheme.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(label, style: AsOneTheme.captionStyle),
      ],
    );
  }
}
