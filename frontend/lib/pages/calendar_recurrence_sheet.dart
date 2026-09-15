import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import '../widgets/asone_dialog.dart';

class CalendarRecurrenceDraft {
  const CalendarRecurrenceDraft(
    this.kind,
    this.interval,
    this.weekdays,
    this.until,
  );
  final String kind;
  final int interval;
  final Set<int> weekdays;
  final DateTime? until;

  bool isPreset(DateTime start) =>
      interval == 1 &&
      until == null &&
      (kind != 'weekly' ||
          weekdays.length == 1 && weekdays.contains(start.weekday));
}

Future<CalendarRecurrenceDraft?> chooseCalendarRecurrence(
  BuildContext context,
  CalendarRecurrenceDraft current, {
  required DateTime start,
}) async {
  final selected = current.isPreset(start) ? current.kind : 'custom';
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in const {
            'none': '永不',
            'daily': '每天',
            'weekly': '每周',
            'monthly': '每月',
            'yearly': '每年',
            'custom': '自定义',
          }.entries)
            ListTile(
              key: Key('recurrence-${entry.key}'),
              title: Text(entry.value),
              trailing: selected == entry.key
                  ? const Icon(Icons.check, color: AsOneTheme.accent)
                  : null,
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == 'custom') {
    return showModalBottomSheet<CalendarRecurrenceDraft>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) =>
          CalendarCustomRecurrenceSheet(current: current, start: start),
    );
  }
  if (!current.isPreset(start)) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AsOneDialog(
        title: '替换原重复规则？',
        content: const Text('原有的自定义间隔、星期及结束日期将替换为所选规则。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('替换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
  }
  return CalendarRecurrenceDraft(
    choice,
    1,
    choice == 'weekly' ? {start.weekday} : {},
    null,
  );
}

class CalendarCustomRecurrenceSheet extends StatefulWidget {
  const CalendarCustomRecurrenceSheet({
    super.key,
    required this.current,
    required this.start,
  });
  final CalendarRecurrenceDraft current;
  final DateTime start;

  @override
  State<CalendarCustomRecurrenceSheet> createState() =>
      _CalendarCustomRecurrenceSheetState();
}

class _CalendarCustomRecurrenceSheetState
    extends State<CalendarCustomRecurrenceSheet> {
  static const units = {
    'daily': '天',
    'weekly': '周',
    'monthly': '月',
    'yearly': '年',
  };
  late String _kind = widget.current.kind == 'none'
      ? 'daily'
      : widget.current.kind;
  late int _interval = widget.current.interval;
  late final List<int> _values = [
    for (var i = 1; i <= 999; i++) i,
    if (_interval > 999) _interval,
  ];
  late final _controller = FixedExtentScrollController(
    initialItem: _values.indexOf(_interval),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('recurrence-custom-done'),
              onPressed: () => Navigator.pop(
                context,
                CalendarRecurrenceDraft(
                  _kind,
                  _interval,
                  _kind == 'weekly'
                      ? (widget.current.kind == 'weekly' &&
                                widget.current.weekdays.isNotEmpty
                            ? {...widget.current.weekdays}
                            : {widget.start.weekday})
                      : {},
                  widget.current.until,
                ),
              ),
              child: const Text('完成'),
            ),
          ),
          Row(
            children: [
              const Text('频率'),
              const SizedBox(width: 24),
              Expanded(
                child: DropdownButton<String>(
                  key: const Key('recurrence-frequency'),
                  value: _kind,
                  isExpanded: true,
                  items: [
                    for (final entry in units.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _kind = value);
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('每'),
              Expanded(
                child: SizedBox(
                  height: 144,
                  child: CupertinoPicker.builder(
                    key: const Key('recurrence-interval'),
                    scrollController: _controller,
                    itemExtent: 40,
                    childCount: _values.length,
                    onSelectedItemChanged: (index) =>
                        _interval = _values[index],
                    itemBuilder: (_, index) =>
                        Center(child: Text('${_values[index]}')),
                  ),
                ),
              ),
              Text(units[_kind]!, key: const Key('recurrence-unit')),
            ],
          ),
        ],
      ),
    ),
  );
}
