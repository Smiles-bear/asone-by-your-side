import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';

Future<DateTime?> showAsOneDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _AsOneDateDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    title: title,
  ),
);

Future<DateTimeRange?> showAsOneDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期范围',
}) => showDialog<DateTimeRange>(
  context: context,
  builder: (_) => _AsOneDateRangeDialog(
    initialDateRange: initialDateRange,
    firstDate: firstDate,
    lastDate: lastDate,
    title: title,
  ),
);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _clamp(DateTime value, DateTime first, DateTime last) {
  final date = _dateOnly(value);
  if (date.isBefore(first)) return first;
  if (date.isAfter(last)) return last;
  return date;
}

class _AsOneDateDialog extends StatefulWidget {
  const _AsOneDateDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_AsOneDateDialog> createState() => _AsOneDateDialogState();
}

class _AsOneDateDialogState extends State<_AsOneDateDialog> {
  late DateTime selected;

  @override
  void initState() {
    super.initState();
    selected = _clamp(
      widget.initialDate,
      _dateOnly(widget.firstDate),
      _dateOnly(widget.lastDate),
    );
  }

  @override
  Widget build(BuildContext context) => _PickerShell(
    key: const Key('asone-date-picker-dialog'),
    title: widget.title,
    onConfirm: () => Navigator.pop(context, selected),
    child: CalendarDatePicker(
      initialDate: selected,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      onDateChanged: (value) => setState(() => selected = value),
    ),
  );
}

class _AsOneDateRangeDialog extends StatefulWidget {
  const _AsOneDateRangeDialog({
    required this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTimeRange? initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_AsOneDateRangeDialog> createState() => _AsOneDateRangeDialogState();
}

class _AsOneDateRangeDialogState extends State<_AsOneDateRangeDialog> {
  late DateTime start;
  DateTime? end;
  bool choosingStart = true;
  String? error;

  @override
  void initState() {
    super.initState();
    final first = _dateOnly(widget.firstDate);
    final last = _dateOnly(widget.lastDate);
    start = _clamp(widget.initialDateRange?.start ?? last, first, last);
    end = widget.initialDateRange == null
        ? null
        : _clamp(widget.initialDateRange!.end, first, last);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final activeDate = choosingStart ? start : (end ?? start);
    return _PickerShell(
      key: const Key('asone-date-range-picker-dialog'),
      title: widget.title,
      header: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _RangeField(
                  label: '开始日期',
                  value: localizations.formatShortDate(start),
                  selected: choosingStart,
                  onTap: () => setState(() {
                    choosingStart = true;
                    error = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RangeField(
                  label: '结束日期',
                  value: end == null
                      ? '请选择'
                      : localizations.formatShortDate(end!),
                  selected: !choosingStart,
                  onTap: () => setState(() {
                    choosingStart = false;
                    error = null;
                  }),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error!,
                style: AsOneTheme.captionStyle.copyWith(
                  color: AsOneTheme.danger,
                ),
              ),
            ),
          ],
        ],
      ),
      onConfirm: end == null
          ? null
          : () =>
                Navigator.pop(context, DateTimeRange(start: start, end: end!)),
      child: CalendarDatePicker(
        key: ValueKey('range-$choosingStart-${activeDate.toIso8601String()}'),
        initialDate: activeDate,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        onDateChanged: _selectDate,
      ),
    );
  }

  void _selectDate(DateTime value) {
    final date = _dateOnly(value);
    setState(() {
      error = null;
      if (choosingStart) {
        start = date;
        if (end != null && end!.isBefore(start)) {
          end = null;
        }
        choosingStart = false;
      } else if (date.isBefore(start)) {
        error = '结束日期不能早于开始日期';
      } else {
        end = date;
      }
    });
  }
}

class _PickerShell extends StatelessWidget {
  const _PickerShell({
    super.key,
    required this.title,
    this.header,
    required this.child,
    required this.onConfirm,
  });

  final String title;
  final Widget? header;
  final Widget child;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickerTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: AsOneTheme.iconAccent,
        onPrimary: Colors.white,
        surface: const Color(0xFFFFFCFA),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFFFFFCFA),
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: Colors.transparent,
        headerForegroundColor: AsOneTheme.textPrimary,
        todayBorder: const BorderSide(color: AsOneTheme.iconAccent),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AsOneTheme.iconAccent
              : Colors.transparent,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AsOneTheme.textDisabled;
          }
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AsOneTheme.textPrimary;
        }),
      ),
    );
    final maxHeight = MediaQuery.sizeOf(context).height - 32;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 356, maxHeight: maxHeight),
        child: Material(
          color: const Color(0xFFFFFCFA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFF0E5E0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(title, style: AsOneTheme.dialogTitleStyle),
                  ),
                  if (header != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: header!,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Theme(
                    data: pickerTheme,
                    child: SizedBox(height: 330, child: child),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      TextButton(onPressed: onConfirm, child: const Text('确定')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF0EA) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AsOneTheme.iconAccent : AsOneTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AsOneTheme.captionStyle),
          const SizedBox(height: 2),
          Text(value, style: AsOneTheme.bodyStyle, maxLines: 1),
        ],
      ),
    ),
  );
}
