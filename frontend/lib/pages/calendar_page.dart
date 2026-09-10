import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calendar/calendar_category.dart';
import '../models/assistant.dart';
import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_icons.dart';
import '../widgets/asone_line_asset_icon.dart';
import '../widgets/asone_feedback.dart';
import 'calendar_event_editor_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, this.calendar, this.coreRepository});

  final CalendarRepositoryApi? calendar;
  final AssistantRepositoryApi? coreRepository;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late final CalendarRepositoryApi _repository =
      widget.calendar ?? OpenCoreBinding.instance.calendar;
  late final AssistantRepositoryApi _core =
      widget.coreRepository ?? OpenCoreBinding.instance.assistants;
  late DateTime _month;
  late DateTime _selected;
  List<CalendarOccurrence> _occurrences = const [];
  Map<String, Assistant> _assistants = const {};
  Map<String, int> _creatorColors = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    final readThrough = DateTime.now().toUtc();
    try {
      final occurrences = await _repository.listMonthForUser(
        _month.year,
        _month.month,
      );
      final results = await Future.wait<Object>([
        _core.getAssistants(),
        _repository.resolveCreatorColors(occurrences),
      ]);
      if (!mounted) return;
      final assistants = results[0] as List<Assistant>;
      setState(() {
        _occurrences = occurrences;
        _assistants = {for (final value in assistants) value.id: value};
        _creatorColors = results[1] as Map<String, int>;
        _loading = false;
      });
      if (widget.calendar == null) {
        await OpenCoreBinding.instance.featureUnread.markRead(
          FeatureUnreadKind.calendar,
          through: readThrough,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('加载失败，请稍后重试');
    }
  }

  List<CalendarOccurrence> _forDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _occurrences.where((occurrence) {
      final occurrenceStart = occurrence.startAt.toLocal();
      final occurrenceEnd = occurrence.endAt?.toLocal();
      if (occurrenceEnd == null) {
        return occurrenceStart.isBefore(end) &&
            !occurrenceStart.isBefore(start);
      }
      return occurrenceStart.isBefore(end) && occurrenceEnd.isAfter(start);
    }).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selected = DateTime(_month.year, _month.month, 1);
      _loading = true;
    });
    await _load();
  }

  Future<void> _openEditor([CalendarOccurrence? occurrence]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarEventEditorPage(
          repository: _repository,
          initialDay: _selected,
          occurrence: occurrence,
          assistants: _assistants,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  String _creatorKey(CalendarOccurrence occurrence) {
    final event = occurrence.event;
    return event.authorType == 'assistant'
        ? 'assistant:${event.authorAssistantId ?? ''}'
        : event.authorType;
  }

  Color _sourceColor(CalendarOccurrence occurrence) =>
      Color(_creatorColors[_creatorKey(occurrence)] ?? 0xFF9C8D86);

  void _message(String text) {
    AsOneToast.show(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _forDay(_selected);
    return Scaffold(
      backgroundColor: AsOneTheme.pageBg,
      appBar: AsOneAppBar(
        title: '日历',
        leading: AsOneIconButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: AsOneIconName.back,
        ),
        actions: [
          AsOneIconButton(
            tooltip: '新建事项',
            onPressed: _openEditor,
            icon: AsOneIconName.add,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 30),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: AspectRatio(
                        aspectRatio: 333 / 387,
                        child: Container(
                          key: const ValueKey('calendar-month-card'),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEFBFA),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x29000000),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 39,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        tooltip: '上个月',
                                        onPressed: () => _changeMonth(-1),
                                        icon: const AsOneLineAssetIcon.back(),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_month.year}年${_month.month}月',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F1A18),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '下个月',
                                        onPressed: () => _changeMonth(1),
                                        icon: Transform.rotate(
                                          angle: math.pi,
                                          child:
                                              const AsOneLineAssetIcon.back(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const _WeekHeader(),
                                Expanded(
                                  child: _MonthGrid(
                                    month: _month,
                                    selected: _selected,
                                    occurrences: _occurrences,
                                    eventsForDay: _forDay,
                                    sourceColor: _sourceColor,
                                    onSelect: (day) =>
                                        setState(() => _selected = day),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 9),
                    child: Text(
                      '${_selected.month}月${_selected.day}日 · ${_weekday(_selected)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27211F),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (selectedEvents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 44),
                      child: Center(
                        child: Text(
                          '这一天还没有安排',
                          style: TextStyle(color: AsOneTheme.textTertiary),
                        ),
                      ),
                    )
                  else
                    ...selectedEvents.map(
                      (occurrence) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OccurrenceTile(
                          occurrence: occurrence,
                          assistants: _assistants,
                          onTap: () => _openEditor(occurrence),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _weekday(DateTime value) => const [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ][value.weekday - 1];
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 29,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0E8E4), width: .7)),
      ),
      child: Row(
        children: [
          for (final day in const ['日', '一', '二', '三', '四', '五', '六'])
            Expanded(
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF77706D),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.occurrences,
    required this.eventsForDay,
    required this.sourceColor,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final List<CalendarOccurrence> occurrences;
  final List<CalendarOccurrence> Function(DateTime) eventsForDay;
  final Color Function(CalendarOccurrence) sourceColor;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final offset = DateTime(month.year, month.month).weekday % 7;
    final count = DateTime(month.year, month.month + 1, 0).day;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final rowHeight = constraints.maxHeight / 6;
        final bars = _barSegments(offset, count);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var row = 0; row < 6; row++)
              Positioned(
                top: (row + 1) * rowHeight - .6,
                left: 0,
                right: 0,
                child: const Divider(
                  height: .6,
                  thickness: .6,
                  color: Color(0xFFF1EAE7),
                ),
              ),
            for (var dayNumber = 1; dayNumber <= count; dayNumber++)
              _dayCell(
                dayNumber,
                offset,
                cellWidth,
                rowHeight,
                bars.any((bar) {
                  final index = offset + dayNumber - 1;
                  final column = index % 7;
                  return bar.row == index ~/ 7 &&
                      column >= bar.startColumn &&
                      column <= bar.endColumn;
                }),
              ),
            for (final bar in bars)
              Positioned(
                left: bar.startColumn * cellWidth + 2,
                top: bar.row * rowHeight + 29 + bar.lane * 15,
                width: (bar.endColumn - bar.startColumn + 1) * cellWidth - 4,
                height: 14,
                child: Container(
                  key: ValueKey(
                    'calendar-bar-${bar.occurrence.event.eventId}-${bar.row}-${bar.startColumn}',
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: bar.category.paleColor,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    bar.showTitle ? bar.occurrence.title : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF443C38),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dayCell(
    int dayNumber,
    int offset,
    double cellWidth,
    double rowHeight,
    bool hasBar,
  ) {
    final index = offset + dayNumber - 1;
    final row = index ~/ 7;
    final column = index % 7;
    final day = DateTime(month.year, month.month, dayNumber);
    final selectedDay = _sameDay(day, selected);
    final events = eventsForDay(day);
    final dots = hasBar
        ? const <CalendarOccurrence>[]
        : events.where((event) => !_isMultiDay(event)).take(3).toList();
    return Positioned(
      left: column * cellWidth,
      top: row * rowHeight,
      width: cellWidth,
      height: rowHeight,
      child: Semantics(
        button: true,
        selected: selectedDay,
        label:
            '${day.month}月${day.day}日${events.isEmpty ? '' : '，有${events.length}项安排'}',
        child: InkWell(
          onTap: () => onSelect(day),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  key: selectedDay
                      ? ValueKey(
                          'calendar-selected-${day.year}-${day.month}-${day.day}',
                        )
                      : null,
                  width: 36,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedDay
                        ? const Color(0xFFFFF0E9)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$dayNumber',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1,
                      color: selectedDay
                          ? const Color(0xFFF08B74)
                          : const Color(0xFF292321),
                      fontWeight: selectedDay
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (dots.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final occurrence in dots)
                        Container(
                          width: 4.5,
                          height: 4.5,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: sourceColor(occurrence),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_BarSegment> _barSegments(int offset, int count) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month, count, 23, 59, 59, 999);
    final raw = <_BarSegment>[];
    for (final occurrence in occurrences.where(_isMultiDay)) {
      var start = _dateOnly(occurrence.startAt.toLocal());
      var end = _inclusiveEnd(occurrence);
      if (start.isBefore(monthStart)) start = monthStart;
      if (end.isAfter(monthEnd)) end = _dateOnly(monthEnd);
      if (end.isBefore(start)) continue;
      var cursor = start;
      var first = true;
      while (!cursor.isAfter(end)) {
        final startIndex = offset + cursor.day - 1;
        final row = startIndex ~/ 7;
        final rowLastDay = math.min(count, (row + 1) * 7 - offset);
        final segmentEndDay = math.min(end.day, rowLastDay);
        raw.add(
          _BarSegment(
            occurrence: occurrence,
            category: CalendarCategory.fromId(occurrence.categoryId),
            row: row,
            startColumn: startIndex % 7,
            endColumn: (offset + segmentEndDay - 1) % 7,
            showTitle: first,
          ),
        );
        first = false;
        cursor = DateTime(month.year, month.month, segmentEndDay + 1);
      }
    }
    raw.sort((a, b) {
      final row = a.row.compareTo(b.row);
      return row != 0 ? row : a.startColumn.compareTo(b.startColumn);
    });
    final occupied = <int, List<List<int>>>{};
    for (final segment in raw) {
      final lanes = occupied.putIfAbsent(segment.row, () => <List<int>>[]);
      var lane = 0;
      while (lane < lanes.length &&
          lanes[lane].any(
            (column) =>
                column >= segment.startColumn && column <= segment.endColumn,
          )) {
        lane++;
      }
      if (lane == lanes.length) lanes.add(<int>[]);
      lanes[lane].addAll([
        for (
          var column = segment.startColumn;
          column <= segment.endColumn;
          column++
        )
          column,
      ]);
      segment.lane = math.min(lane, 1);
    }
    return raw;
  }

  bool _isMultiDay(CalendarOccurrence occurrence) {
    final end = occurrence.endAt?.toLocal();
    if (end == null) return false;
    return _inclusiveEnd(
      occurrence,
    ).isAfter(_dateOnly(occurrence.startAt.toLocal()));
  }

  DateTime _inclusiveEnd(CalendarOccurrence occurrence) {
    var end = occurrence.endAt!.toLocal();
    if (end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0 &&
        end.millisecond == 0 &&
        end.microsecond == 0) {
      end = end.subtract(const Duration(microseconds: 1));
    }
    return _dateOnly(end);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _BarSegment {
  _BarSegment({
    required this.occurrence,
    required this.category,
    required this.row,
    required this.startColumn,
    required this.endColumn,
    required this.showTitle,
  });

  final CalendarOccurrence occurrence;
  final CalendarCategory category;
  final int row;
  final int startColumn;
  final int endColumn;
  final bool showTitle;
  int lane = 0;
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({
    required this.occurrence,
    required this.assistants,
    required this.onTap,
  });

  final CalendarOccurrence occurrence;
  final Map<String, Assistant> assistants;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = CalendarCategory.fromId(occurrence.categoryId);
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1E8E4), width: 0.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Row(
            children: [
              const SizedBox(width: 9),
              Container(
                width: 2.8,
                height: 52,
                decoration: BoxDecoration(
                  color: category.strongColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              CalendarCategoryIcon(category: category, size: 42),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      occurrence.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF332C29),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _timeLabel(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF746B67),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '♙ ${_sourceLabel()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF8C837F),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: category.paleColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: category.strongColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Transform.rotate(
                angle: math.pi,
                child: const AsOneLineAssetIcon.back(),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel() {
    final event = occurrence.event;
    if (event.authorType == 'user') return '我';
    if (event.authorType == 'assistant') {
      return assistants[event.authorAssistantId]?.name ?? '助手';
    }
    return '系统';
  }

  String _timeLabel() {
    if (occurrence.isAllDay) return '全天';
    final start = occurrence.startAt.toLocal();
    final end = occurrence.endAt?.toLocal();
    final startText =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    if (end == null) return startText;
    final endText =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$startText - $endText';
  }
}
