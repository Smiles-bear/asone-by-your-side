import 'package:asone_contracts/asone_contracts.dart';
import 'features/world/world_entries.dart';
import 'local_core/world/world_import_parser.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_feedback.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'community_world_document.dart';
import 'community_world_service.dart';
import 'public_core.dart';

class CommunityWorldPage extends StatefulWidget {
  const CommunityWorldPage({super.key, required this.assistant});
  final Assistant assistant;
  @override
  State<CommunityWorldPage> createState() => _CommunityWorldPageState();
}

class _CommunityWorldPageState extends State<CommunityWorldPage> {
  PublicCore get _core => OpenCoreBinding.instance as PublicCore;
  String? _category;
  List<WorldEntryCategory> _categories = [];
  final _items = <WorldEntry>[];
  bool _busy = false, _loading = true, _more = false;
  String? _error;
  CancelToken? _cancel;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await _core.worlds.categories(widget.assistant.id);
      final category = categories.any((c) => c.name == _category)
          ? _category
          : categories.firstOrNull?.name;
      final rows = category == null
          ? <WorldEntry>[]
          : await _core.worlds.list(
              widget.assistant.id,
              category,
              offset: append ? _items.length : 0,
            );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _category = category;
        if (!append) _items.clear();
        _items.addAll(rows);
        _more = rows.length == 40;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String text) {
    if (mounted) AsOneToast.show(context, text);
  }

  Future<void> _edit([WorldEntry? summary]) async {
    try {
      final entry = summary == null
          ? null
          : await _core.worlds.get(widget.assistant.id, summary.id);
      if (!mounted) return;
      if (summary != null && entry == null) {
        await _load();
        return;
      }
      final draft = await showDialog<WorldEntryDraft>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WorldEditor(entry: entry),
      );
      if (draft == null) return;
      await _core.worlds.save(widget.assistant.id, draft, entryId: entry?.id);
      await _load();
    } catch (_) {
      _toast('保存失败，请重试');
    }
  }

  Future<void> _pickDocument() async {
    setState(() => _busy = true);
    WorldImportResult? document;
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: WorldImportParser.supportedExtensions.toList(),
        withData: false,
      );
      if (selection == null || !mounted) return;
      document = await readCommunityWorldDocument(selection.files.single);
    } on WorldImportFailure catch (e) {
      _toast(e.userMessage);
      return;
    } catch (_) {
      _toast('文件读取失败，请重新选择');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _organize(document.text);
  }

  Future<void> _organize([String initialText = '']) async {
    final source = await showDialog<String>(
      context: context,
      builder: (_) => _WorldInput(initialText: initialText),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    _cancel = CancelToken();
    try {
      final proposal = await _core.worldOrganizer.prepare(
        widget.assistant.id,
        source,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认整理结果'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in proposal.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '${entry.category} · ${entry.title}\n${entry.content}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _core.worldOrganizer.confirm(proposal);
      await _load();
    } catch (_) {
      if (!(_cancel?.isCancelled ?? false)) _toast('整理失败，未保存任何内容');
    } finally {
      _cancel = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sources() async {
    final sources = await _core.worlds.sourceMaterials(widget.assistant.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('原始资料'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              sources.isEmpty ? '暂无资料' : sources.join('\n\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(WorldEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除条目？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _core.worlds.delete(widget.assistant.id, entry.id);
      await _load();
    } catch (_) {
      _toast('删除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AsOneAppBar(
      title: '世界设定',
      actions: [
        IconButton(
          tooltip: '原始资料',
          onPressed: _busy || _loading
              ? null
              : () async {
                  try {
                    await _sources();
                  } catch (_) {
                    _toast('加载失败');
                  }
                },
          icon: const Icon(Icons.description_outlined),
        ),
        IconButton(
          tooltip: '新增条目',
          onPressed: _busy || _loading ? null : () => _edit(),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text('全部启用'),
          value: _categories.any((c) => c.enabledCount > 0),
          onChanged: _busy || _loading
              ? null
              : (value) async {
                  try {
                    await _core.worlds.setAllEnabled(
                      widget.assistant.id,
                      value,
                    );
                    await _load();
                  } catch (_) {
                    _toast('保存失败，请重试');
                  }
                },
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _category,
                  hint: const Text('分类'),
                  items: [
                    for (final c in _categories)
                      DropdownMenuItem(
                        value: c.name,
                        child: Text('${c.name}（${c.count}）'),
                      ),
                  ],
                  onChanged: _busy || _loading
                      ? null
                      : (value) {
                          _category = value;
                          _load();
                        },
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: '导入资料',
                enabled: !_busy && !_loading,
                onSelected: (value) =>
                    value == 'file' ? _pickDocument() : _organize(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'file', child: Text('导入文档')),
                  PopupMenuItem(value: 'text', child: Text('粘贴文本')),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('导入资料'),
                ),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: TextButton(onPressed: _load, child: Text(_error!)),
                )
              : ListView(
                  children: [
                    if (_items.isEmpty) const ListTile(title: Text('暂无条目')),
                    for (final entry in _items)
                      Card(
                        child: ListTile(
                          leading: IconButton(
                            tooltip: '删除条目',
                            onPressed: _busy ? null : () => _delete(entry),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          title: Text(entry.title),
                          subtitle: Text(
                            entry.usageMode == WorldUsageMode.always
                                ? '每轮使用'
                                : '相关时使用',
                          ),
                          onTap: _busy ? null : () => _edit(entry),
                          trailing: Switch(
                            value: entry.enabled,
                            onChanged: _busy
                                ? null
                                : (value) async {
                                    try {
                                      await _core.worlds.setEnabled(
                                        widget.assistant.id,
                                        entry.id,
                                        value,
                                      );
                                      await _load();
                                    } catch (_) {
                                      _toast('保存失败，请重试');
                                    }
                                  },
                          ),
                        ),
                      ),
                    if (_more)
                      TextButton(
                        onPressed: () => _load(append: true),
                        child: const Text('加载更多'),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _WorldInput extends StatefulWidget {
  const _WorldInput({required this.initialText});
  final String initialText;
  @override
  State<_WorldInput> createState() => _WorldInputState();
}

class _WorldInputState extends State<_WorldInput> {
  late final _text = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('整理资料'),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _text,
        minLines: 5,
        maxLines: 12,
        maxLength: CommunityWorldService.maximumSourceLength,
        decoration: const InputDecoration(
          labelText: '原始资料',
          helperText: '发送给当前助手的模型服务，确认结果后保存。',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_text.text.trim().isNotEmpty) Navigator.pop(context, _text.text);
        },
        child: const Text('开始整理'),
      ),
    ],
  );
}

class _WorldEditor extends StatefulWidget {
  const _WorldEditor({this.entry});
  final WorldEntry? entry;
  @override
  State<_WorldEditor> createState() => _WorldEditorState();
}

class _WorldEditorState extends State<_WorldEditor> {
  late final _title = TextEditingController(text: widget.entry?.title);
  late final _body = TextEditingController(text: widget.entry?.content);
  late final _category = TextEditingController(
    text: widget.entry?.category ?? '其他资料',
  );
  late final _keywords = TextEditingController(
    text: widget.entry?.keywords.join('；'),
  );
  late WorldUsageMode _mode =
      widget.entry?.usageMode ?? WorldUsageMode.relevant;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _category.dispose();
    _keywords.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? '新增条目' : '编辑条目'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: '分类'),
            ),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(labelText: '内容'),
            ),
            TextField(
              controller: _keywords,
              decoration: const InputDecoration(labelText: '关键词（分号分隔）'),
            ),
            DropdownButton<WorldUsageMode>(
              isExpanded: true,
              value: _mode,
              items: const [
                DropdownMenuItem(
                  value: WorldUsageMode.always,
                  child: Text('每轮使用'),
                ),
                DropdownMenuItem(
                  value: WorldUsageMode.relevant,
                  child: Text('相关时使用'),
                ),
              ],
              onChanged: (v) => setState(() => _mode = v!),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final value = WorldEntryDraft(
            title: _title.text,
            content: _body.text,
            category: _category.text,
            enabled: widget.entry?.enabled ?? true,
            usageMode: _mode,
            keywords: _keywords.text
                .split(RegExp('[;；]'))
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList(),
          );
          try {
            value.validate();
            Navigator.pop(context, value);
          } on FormatException catch (e) {
            setState(() => _error = e.message);
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
