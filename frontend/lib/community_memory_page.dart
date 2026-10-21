import 'package:asone_contracts/asone_contracts.dart'
    show Assistant, OpenCoreBinding;
import 'models/memory_item.dart';
import 'theme/asone_theme.dart';
import 'widgets/asone_app_bar.dart';
import 'widgets/asone_feedback.dart';
import 'widgets/asone_dialog.dart';
import 'widgets/asone_icons.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'community_memory_service.dart';
import 'public_core.dart';

/// The same local memory concepts as the official app: search, date filters,
/// optimistic editing, manual notes and reviewed model organization.
class CommunityMemoryPage extends StatefulWidget {
  const CommunityMemoryPage({
    super.key,
    required this.assistant,
    this.conversationId,
  });
  final Assistant assistant;
  final String? conversationId;
  @override
  State<CommunityMemoryPage> createState() => _CommunityMemoryPageState();
}

class _CommunityMemoryPageState extends State<CommunityMemoryPage> {
  PublicCore get _core => OpenCoreBinding.instance as PublicCore;
  final _search = TextEditingController();
  List<MemoryItem> _items = const [];
  DateTimeRange? _range;
  bool _loading = true, _busy = false, _enabled = true;
  int _loadVersion = 0;
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
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final items = await _core.memories.list(
        widget.assistant.id,
        keyword: _search.text,
        dateRange: _range == null
            ? null
            : (
                start: _range!.start,
                end: _range!.end.add(const Duration(days: 1)),
              ),
      );
      final enabled = await _core.memories.isRetrievalEnabled(
        widget.assistant.id,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _items = items;
        _enabled = enabled;
        _loading = false;
        _error = null;
      });
      await _core.memories.markReadBatch(
        assistantId: widget.assistant.id,
        memoryIds: items.map((item) => item.memoryId),
      );
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loading = false;
          _error = '记忆加载失败，请重试';
        });
      }
    }
  }

  Future<void> _edit([MemoryItem? item]) async {
    final result = await showDialog<({String content, DateTime? time})>(
      context: context,
      builder: (_) => _MemoryEditor(item: item),
    );
    if (result == null || !mounted) return;
    try {
      if (item == null) {
        await _core.memories.createUserMemory(
          assistantId: widget.assistant.id,
          content: result.content,
          sourceTime: result.time,
        );
      } else {
        await _core.memories.update(
          memoryId: item.memoryId,
          assistantId: widget.assistant.id,
          content: result.content,
          expectedVersion: item.editVersion,
          sourceTime: result.time,
          sourceTimeChanged: result.time != item.sourceTime,
        );
      }
      await _load();
    } catch (_) {
      _toast('记忆已变化或保存失败，请刷新后重试');
    }
  }

  Future<void> _delete(MemoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: const Text('删除后不再用于聊天检索，也不会被相同的整理候选自动恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _core.memories.delete(
        memoryId: item.memoryId,
        assistantId: widget.assistant.id,
      );
      await _load();
    } catch (_) {
      _toast('删除失败，请刷新后重试');
    }
  }

  Future<void> _organize() async {
    if (_busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从对话整理记忆'),
        content: const Text('将这个助手近期的对话发送给已配置的模型服务，生成候选记忆。确认选中的条目后才会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始整理'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    _cancel = CancelToken();
    try {
      final conversationId =
          widget.conversationId ??
          (await _core.repository.getOrCreatePrimaryConversation(
            widget.assistant.id,
          )).id;
      final proposal = await _core.memory.prepare(
        assistantId: widget.assistant.id,
        conversationId: conversationId,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      if (proposal.items.isEmpty) {
        _toast('没有需要新增的记忆');
        return;
      }
      final selected = await showDialog<Set<String>>(
        context: context,
        builder: (_) => _MemoryReview(proposal: proposal),
      );
      if (selected == null || selected.isEmpty || !mounted) return;
      final count = await _core.memory.confirm(proposal, selected);
      await _load();
      _toast('已保存$count条记忆');
    } catch (error) {
      if (mounted && !(_cancel?.isCancelled ?? false)) {
        _toast(
          error is StateError ? error.message.toString() : '整理未完成，请检查模型配置后重试',
        );
      }
    } finally {
      _cancel = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (!mounted || range == null) return;
    setState(() => _range = range);
    await _load();
  }

  void _toast(String text) {
    if (mounted) AsOneToast.show(context, text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AsOneTheme.mainPageBg,
    appBar: AsOneAppBar(
      title: '${widget.assistant.name}的记忆',
      actions: [
        AsOneIconButton(
          key: const Key('community-memory-add'),
          tooltip: '新建记忆',
          icon: AsOneIconName.add,
          onPressed: _busy ? null : () => _edit(),
        ),
      ],
    ),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text('聊天中使用记忆'),
          value: _enabled,
          onChanged: _busy
              ? null
              : (value) async {
                  try {
                    await _core.memories.setRetrievalEnabled(
                      widget.assistant.id,
                      value,
                    );
                    if (mounted) setState(() => _enabled = value);
                  } catch (_) {
                    _toast('设置保存失败，请重试');
                  }
                },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: '搜索记忆',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => _load(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseDates,
                icon: const Icon(Icons.date_range),
                label: const Text('日期筛选'),
              ),
              if (_range != null)
                IconButton(
                  tooltip: '清除日期筛选',
                  onPressed: () {
                    setState(() => _range = null);
                    _load();
                  },
                  icon: const Icon(Icons.clear),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _organize,
                child: Text(_busy ? '正在整理…' : '从对话整理'),
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.isEmpty ? 1 : _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      if (_items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 64),
                          child: Center(child: Text('没有找到记忆')),
                        );
                      }
                      final item = _items[index];
                      return Card(
                        child: ListTile(
                          title: Text(item.content),
                          subtitle: Text(
                            '${(item.sourceTime ?? item.createdAt).toLocal().toString().split('.').first}'
                            '${item.manualEdit ? ' · 已确认' : ''}',
                          ),
                          onTap: _busy ? null : () => _edit(item),
                          trailing: IconButton(
                            tooltip: '删除记忆',
                            onPressed: _busy ? null : () => _delete(item),
                            icon: const Icon(Icons.delete_outline),
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

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor({this.item});
  final MemoryItem? item;
  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  late final _text = TextEditingController(text: widget.item?.content ?? '');
  late DateTime? _time = widget.item?.sourceTime;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AsOneDialog(
    title: widget.item == null ? '新建记忆' : '编辑记忆',
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('community-memory-content'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 800,
            decoration: const InputDecoration(hintText: '记忆正文'),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _time == null
                      ? '未设置记忆时间'
                      : _time!.toLocal().toString().split(' ').first,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    initialDate: _time?.toLocal() ?? DateTime.now(),
                  );
                  if (value != null && mounted) setState(() => _time = value);
                },
                child: const Text('选择时间'),
              ),
              if (_time != null)
                IconButton(
                  onPressed: () => setState(() => _time = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_text.text.trim().isNotEmpty) {
            Navigator.pop(context, (content: _text.text.trim(), time: _time));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _MemoryReview extends StatefulWidget {
  const _MemoryReview({required this.proposal});
  final CommunityMemoryProposal proposal;
  @override
  State<_MemoryReview> createState() => _MemoryReviewState();
}

class _MemoryReviewState extends State<_MemoryReview> {
  late final _selected = widget.proposal.items.toSet();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认候选记忆'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in widget.proposal.items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item),
                value: _selected.contains(item),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(item);
                  } else {
                    _selected.remove(item);
                  }
                }),
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
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, _selected),
        child: const Text('保存选中记忆'),
      ),
    ],
  );
}
