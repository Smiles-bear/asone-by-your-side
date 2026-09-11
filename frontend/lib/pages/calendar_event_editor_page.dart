import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../calendar/calendar_category.dart';
import '../models/assistant.dart';
import '../services/debug_logger.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/asone_bottom_sheet.dart';
import '../widgets/asone_dialog.dart';
import '../widgets/mind_source_identity.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';

enum CalendarSeriesScope { occurrence, forward, series }

class _RecurrenceDraft {
  const _RecurrenceDraft(this.kind, this.interval, this.weekdays, this.until);

  final String kind;
  final int interval;
  final Set<int> weekdays;
  final DateTime? until;
}

CalendarEventInput anchorSeriesEditInput(
  CalendarEventInput input,
  CalendarOccurrence occurrence,
) {
  final original = occurrence.event;
  final startOffset = input.startAt.toUtc().difference(
    occurrence.startAt.toUtc(),
  );
  final anchoredStart = original.startAt.toUtc().add(startOffset);
  final inputEnd = input.endAt?.toUtc();
  DateTime? anchoredEnd;
  if (inputEnd != null) {
    final occurrenceEnd = occurrence.endAt?.toUtc();
    final originalEnd = original.endAt?.toUtc();
    anchoredEnd = occurrenceEnd != null && originalEnd != null
        ? originalEnd.add(inputEnd.difference(occurrenceEnd))
        : anchoredStart.add(inputEnd.difference(input.startAt.toUtc()));
  }
  return CalendarEventInput(
    title: input.title,
    notes: input.notes,
    categoryId: input.categoryId,
    startAt: anchoredStart,
    endAt: anchoredEnd,
    isAllDay: input.isAllDay,
    recurrenceKind: input.recurrenceKind,
    recurrenceInterval: input.recurrenceInterval,
    recurrenceWeekdays: input.recurrenceWeekdays,
    recurrenceUntil: input.recurrenceUntil,
    customAdvanceMinutes: input.customAdvanceMinutes,
  );
}

class CalendarEventEditorPage extends StatefulWidget {
  const CalendarEventEditorPage({
    super.key,
    required this.repository,
    required this.initialDay,
    this.occurrence,
    this.assistants = const {},
  });

  final CalendarRepositoryApi repository;
  final DateTime initialDay;
  final CalendarOccurrence? occurrence;
  final Map<String, Assistant> assistants;

  @override
  State<CalendarEventEditorPage> createState() =>
      _CalendarEventEditorPageState();
}

class _CalendarEventEditorPageState extends State<CalendarEventEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _interval;
  late DateTime _start;
  DateTime? _end;
  late bool _allDay;
  late String _recurrence;
  late Set<int> _weekdays;
  DateTime? _recurrenceUntil;
  int? _advanceMinutes;
  late String _categoryId;
  bool _saving = false;

  bool get _editing => widget.occurrence != null;

  @override
  void initState() {
    super.initState();
    final occurrence = widget.occurrence;
    final event = occurrence?.event;
    _title = TextEditingController(text: occurrence?.title ?? '');
    _notes = TextEditingController(text: occurrence?.notes ?? '');
    _start =
        occurrence?.startAt.toLocal() ??
        DateTime(
          widget.initialDay.year,
          widget.initialDay.month,
          widget.initialDay.day,
          9,
        );
    _end = occurrence?.endAt?.toLocal();
    _allDay = occurrence?.isAllDay ?? false;
    _recurrence = event?.recurrenceKind ?? 'none';
    _interval = TextEditingController(
      text: '${event?.recurrenceInterval ?? 1}',
    );
    _weekdays = {...?event?.recurrenceWeekdays};
    _recurrenceUntil = event?.recurrenceUntil?.toLocal();
    _advanceMinutes = event?.customAdvanceMinutes;
    _categoryId = occurrence?.categoryId ?? event?.categoryId ?? 'daily';
    _title.addListener(_changed);
    _notes.addListener(_changed);
    _interval.addListener(_changed);
  }

  void _changed() {
    setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _interval.dispose();
    super.dispose();
  }

  CalendarEventInput? _input() {
    final interval = int.tryParse(_interval.text.trim());
    if (_title.text.trim().isEmpty) {
      _message('请填写事项标题');
      return null;
    }
    if (interval == null || interval <= 0) {
      _message('重复间隔必须大于 0');
      return null;
    }
    if (_end != null && _end!.isBefore(_start)) {
      _message('结束时间不能早于开始时间');
      return null;
    }
    if (_recurrence == 'weekly' && _weekdays.isEmpty) {
      _message('请至少选择一个星期');
      return null;
    }
    return CalendarEventInput(
      title: _title.text,
      notes: _notes.text,
      categoryId: _categoryId,
      startAt: _start,
      endAt: _end,
      isAllDay: _allDay,
      recurrenceKind: _recurrence,
      recurrenceInterval: interval,
      recurrenceWeekdays: _weekdays.toList()..sort(),
      recurrenceUntil: _recurrenceUntil,
      customAdvanceMinutes: _advanceMinutes,
    );
  }

  Future<CalendarSeriesScope?> _chooseScope(String verb) {
    return AsOneBottomSheet.showActions<CalendarSeriesScope>(
      context,
      title: '$verb重复事项',
      actions: const [
        AsOneSheetAction(
          value: CalendarSeriesScope.occurrence,
          label: '仅本次',
          icon: AsOneIconName.calendar,
        ),
        AsOneSheetAction(
          value: CalendarSeriesScope.forward,
          label: '本次及以后',
          icon: AsOneIconName.forward,
        ),
        AsOneSheetAction(
          value: CalendarSeriesScope.series,
          label: '整个系列',
          icon: AsOneIconName.refresh,
        ),
      ],
    );
  }

  Future<void> _save() async {
    var input = _input();
    if (input == null) return;
    CalendarSeriesScope? scope;
    final occurrence = widget.occurrence;
    if (occurrence?.event.isRecurring == true) {
      scope = await _chooseScope('修改');
      if (scope == null) return;
      if (scope == CalendarSeriesScope.series) {
        input = anchorSeriesEditInput(input, occurrence!);
      }
    }
    setState(() => _saving = true);
    try {
      if (occurrence == null) {
        await widget.repository.createEvent(input: input, authorType: 'user');
      } else {
        switch (scope ?? CalendarSeriesScope.series) {
          case CalendarSeriesScope.occurrence:
            await widget.repository.updateOccurrence(
              eventId: occurrence.event.eventId,
              occurrenceKey: occurrence.occurrenceKey,
              input: input,
            );
          case CalendarSeriesScope.forward:
            await widget.repository.updateFromOccurrence(
              eventId: occurrence.event.eventId,
              occurrenceKey: occurrence.occurrenceKey,
              input: input,
            );
          case CalendarSeriesScope.series:
            await widget.repository.updateSeries(
              eventId: occurrence.event.eventId,
              input: input,
            );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      DebugLogger.instance.error(
        '保存日历事项失败',
        tag: 'CalendarEditor',
        details: error.toString(),
      );
      _message(error is StateError ? '事项已不存在' : '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final occurrence = widget.occurrence!;
    CalendarSeriesScope? scope = CalendarSeriesScope.series;
    if (occurrence.event.isRecurring) {
      scope = await _chooseScope('删除');
      if (scope == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AsOneDialog(
          icon: asOneIconData(AsOneIconName.delete),
          iconColor: AsOneTheme.danger,
          title: '删除事项',
          content: const Text('确定删除这个事项吗？'),
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
      switch (scope) {
        case CalendarSeriesScope.occurrence:
          await widget.repository.deleteOccurrence(
            eventId: occurrence.event.eventId,
            occurrenceKey: occurrence.occurrenceKey,
          );
        case CalendarSeriesScope.forward:
          await widget.repository.deleteFromOccurrence(
            eventId: occurrence.event.eventId,
            occurrenceKey: occurrence.occurrenceKey,
          );
        case CalendarSeriesScope.series:
          await widget.repository.deleteSeries(occurrence.event.eventId);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      DebugLogger.instance.error(
        '删除日历事项失败',
        tag: 'CalendarEditor',
        details: error.toString(),
      );
      _message('删除失败，请稍后重试');
    }
  }

  Future<void> _pickDate(bool start) async {
    final value = start ? _start : (_end ?? _start);
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      final updated = DateTime(
        date.year,
        date.month,
        date.day,
        value.hour,
        value.minute,
      );
      if (start) {
        _start = updated;
      } else {
        _end = updated;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final value = start ? _start : (_end ?? _start);
    var selectedHour = value.hour;
    var selectedMinute = value.minute;
    final hourController = FixedExtentScrollController(
      initialItem: selectedHour,
    );
    final minuteController = FixedExtentScrollController(
      initialItem: selectedMinute,
    );
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFFFFF9F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: 330,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Expanded(
                    child: Text(
                      '选择时间',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      DateTime(
                        value.year,
                        value.month,
                        value.day,
                        selectedHour,
                        selectedMinute,
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 105,
                    child: CupertinoPicker.builder(
                      scrollController: hourController,
                      itemExtent: 46,
                      magnification: 1.12,
                      useMagnifier: true,
                      onSelectedItemChanged: (index) => selectedHour = index,
                      childCount: 24,
                      itemBuilder: (_, index) =>
                          Center(child: Text(index.toString().padLeft(2, '0'))),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('时', style: TextStyle(fontSize: 15)),
                  ),
                  SizedBox(
                    width: 105,
                    child: CupertinoPicker.builder(
                      scrollController: minuteController,
                      itemExtent: 46,
                      magnification: 1.12,
                      useMagnifier: true,
                      onSelectedItemChanged: (index) => selectedMinute = index,
                      childCount: 60,
                      itemBuilder: (_, index) =>
                          Center(child: Text(index.toString().padLeft(2, '0'))),
                    ),
                  ),
                  const Text('分', style: TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    hourController.dispose();
    minuteController.dispose();
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  String get _recurrenceSummary {
    switch (_recurrence) {
      case 'daily':
        return _interval.text == '1' ? '每天' : '每 ${_interval.text} 天';
      case 'weekly':
        final days = (_weekdays.isEmpty ? {_start.weekday} : _weekdays).toList()
          ..sort();
        final names = days.map((day) => '周${'一二三四五六日'[day - 1]}').join('、');
        return _interval.text == '1'
            ? '每周 $names'
            : '每 ${_interval.text} 周 · $names';
      case 'monthly':
        return _interval.text == '1'
            ? '每月 ${_start.day} 日'
            : '每 ${_interval.text} 个月';
      case 'yearly':
        return _interval.text == '1'
            ? '每年 ${_start.month} 月 ${_start.day} 日'
            : '每 ${_interval.text} 年';
      default:
        return '不重复';
    }
  }

  Future<void> _chooseRecurrence() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('重复'),
            subtitle: Text('选择常用规则，复杂规则可进入自定义'),
          ),
          for (final entry in <String, String>{
            'none': '不重复',
            'daily': '每天',
            'weekly': '每周 · 周${'一二三四五六日'[_start.weekday - 1]}',
            'monthly': '每月 · ${_start.day} 日',
            'yearly': '每年 · ${_start.month} 月 ${_start.day} 日',
            'custom': '自定义…',
          }.entries)
            ListTile(
              title: Text(entry.value),
              trailing: entry.key == _recurrence && _interval.text == '1'
                  ? const Icon(Icons.check, color: AsOneTheme.accent)
                  : null,
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'custom') {
      await _editCustomRecurrence();
      return;
    }
    setState(() {
      _recurrence = choice;
      _interval.text = '1';
      _weekdays = choice == 'weekly' ? {_start.weekday} : <int>{};
      _recurrenceUntil = null;
    });
  }

  Future<void> _editCustomRecurrence() async {
    var kind = _recurrence == 'none' ? 'weekly' : _recurrence;
    var interval = int.tryParse(_interval.text) ?? 1;
    final weekdays = {
      ...(_weekdays.isEmpty ? {_start.weekday} : _weekdays),
    };
    var until = _recurrenceUntil;
    final result = await showModalBottomSheet<_RecurrenceDraft>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '自定义重复',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _RecurrenceDraft(kind, interval, weekdays, until),
                      ),
                      child: const Text('完成'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('每'),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 72,
                      child: TextFormField(
                        initialValue: '$interval',
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: (value) =>
                            interval = int.tryParse(value) ?? 1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: kind,
                        items:
                            const {
                                  'daily': '天',
                                  'weekly': '周',
                                  'monthly': '个月',
                                  'yearly': '年',
                                }.entries
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => setSheetState(() {
                          kind = value ?? 'weekly';
                        }),
                      ),
                    ),
                  ],
                ),
                if (kind == 'weekly') ...[
                  const SizedBox(height: 18),
                  const Text('重复于'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (index) {
                      final day = index + 1;
                      return FilterChip(
                        label: Text('一二三四五六日'[index]),
                        selected: weekdays.contains(day),
                        onSelected: (selected) => setSheetState(() {
                          selected ? weekdays.add(day) : weekdays.remove(day);
                        }),
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('结束'),
                  subtitle: Text(until == null ? '永不' : _date(until!)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: until ?? _start,
                      firstDate: _start,
                      lastDate: DateTime(2100),
                    );
                    if (date != null) setSheetState(() => until = date);
                  },
                ),
                if (until != null)
                  TextButton(
                    onPressed: () => setSheetState(() => until = null),
                    child: const Text('改为永不结束'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    if (result.interval < 1 ||
        (result.kind == 'weekly' && result.weekdays.isEmpty)) {
      _message('请填写有效的重复规则');
      return;
    }
    setState(() {
      _recurrence = result.kind;
      _interval.text = '${result.interval}';
      _weekdays = result.weekdays;
      _recurrenceUntil = result.until;
    });
  }

  Future<void> _setCustomAdvance() async {
    final controller = TextEditingController(
      text: _advanceMinutes == null ? '' : '$_advanceMinutes',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AsOneDialog(
        icon: asOneIconData(AsOneIconName.clock),
        title: '自定义提前时间',
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '分钟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value < 0) {
      _message('提前时间不能为负数');
      return;
    }
    setState(() {
      _advanceMinutes = value;
    });
  }

  void _message(String message) {
    AsOneToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.occurrence?.event;
    return UnsavedChangesGuard(
      snapshot: () => [
        _title.text,
        _notes.text,
        _interval.text,
        _start.toIso8601String(),
        _end?.toIso8601String(),
        _allDay,
        _recurrence,
        (_weekdays.toList()..sort()),
        _recurrenceUntil?.toIso8601String(),
        _advanceMinutes,
        _categoryId,
      ],
      onSave: _save,
      saving: _saving,
      child: Scaffold(
        appBar: AsOneAppBar(
          title: _editing ? '编辑事项' : '新建事项',
          actions: [
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            children: [
              TextField(
                controller: _title,
                maxLength: 100,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 4),
              Text('类别', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                runSpacing: 10,
                children: [
                  for (final category in CalendarCategory.values)
                    _CategoryChoice(
                      category: category,
                      selected: category.id == _categoryId,
                      onTap: () => setState(() {
                        _categoryId = category.id;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('全天'),
                value: _allDay,
                onChanged: (value) => setState(() {
                  _allDay = value;
                }),
              ),
              _DateTimeRow(
                label: '开始',
                value: _start,
                allDay: _allDay,
                onDate: () => _pickDate(true),
                onTime: () => _pickTime(true),
              ),
              _DateTimeRow(
                label: '结束',
                value: _end,
                allDay: _allDay,
                optional: true,
                onDate: () => _pickDate(false),
                onTime: () => _pickTime(false),
                onClear: _end == null
                    ? null
                    : () => setState(() {
                        _end = null;
                      }),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('重复'),
                subtitle: Text(_recurrenceSummary),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseRecurrence,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('提前时间'),
                subtitle: Text(
                  _advanceMinutes == null ? '使用默认' : '提前 $_advanceMinutes 分钟',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: '设置提前时间',
                  onSelected: (value) {
                    if (value == 'custom') {
                      _setCustomAdvance();
                      return;
                    }
                    setState(() {
                      _advanceMinutes = value == 'default'
                          ? null
                          : int.parse(value);
                    });
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'default', child: Text('使用默认')),
                    PopupMenuItem(value: '60', child: Text('1 小时')),
                    PopupMenuItem(value: '1440', child: Text('1 天')),
                    PopupMenuItem(value: '4320', child: Text('3 天')),
                    PopupMenuItem(value: 'custom', child: Text('自定义')),
                  ],
                ),
              ),
              const Text(
                '用于助手理解临近安排，不会发送系统提醒。',
                style: AsOneTheme.captionStyle,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              if (event != null) ...[
                const Divider(height: 32),
                Text('来源', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                MindSourceIdentity(
                  authorType: event.authorType,
                  authorAssistantId: event.authorAssistantId,
                  assistants: widget.assistants,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AsOneTheme.danger,
                    side: const BorderSide(color: AsOneTheme.danger),
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除事项'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime value) => '${value.year}年${value.month}月${value.day}日';
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.allDay,
    required this.onDate,
    required this.onTime,
    this.optional = false,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final bool allDay;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final bool optional;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(label, style: AsOneTheme.secondaryStyle),
        ),
        Expanded(
          child: TextButton(
            onPressed: onDate,
            child: Text(
              current == null
                  ? (optional ? '未设置' : '选择日期')
                  : '${current.year}/${current.month}/${current.day}',
            ),
          ),
        ),
        if (!allDay)
          TextButton(
            onPressed: onTime,
            child: Text(
              current == null
                  ? '时间'
                  : '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
            ),
          ),
        if (onClear != null)
          IconButton(
            tooltip: '清除结束时间',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CalendarCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? category.paleColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? category.strongColor : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CalendarCategoryIcon(category: category, size: 38),
              const SizedBox(height: 4),
              Text(category.label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
