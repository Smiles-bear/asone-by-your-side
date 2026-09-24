import 'package:asone_contracts/asone_contracts.dart'
    show DailyTokenUsage, OpenCoreBinding, TokenUsageRecord, TokenUsageSummary;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../theme/asone_theme.dart';
import '../widgets/asone_app_bar.dart';
import '../widgets/asone_feedback.dart';
import '../widgets/asone_icons.dart';

class TokenUsagePage extends StatefulWidget {
  const TokenUsagePage({super.key});

  @override
  State<TokenUsagePage> createState() => _TokenUsagePageState();
}

class _TokenUsagePageState extends State<TokenUsagePage> {
  String _selectedTimeRange = 'month'; // 'today', 'week', 'month', 'all'
  String _selectedTaskType = 'chat'; // 'chat', 'memory_rebuild', 'function'
  bool _isLoading = true;
  bool _hasLoaded = false;
  int _loadRevision = 0;

  TokenUsageSummary _totalSummary = TokenUsageSummary(
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
  );
  TokenUsageSummary _typeSummary = TokenUsageSummary(
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
  );
  List<DailyTokenUsage> _dailyUsage = [];
  List<TokenUsageRecord> _detailedRecords = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final revision = ++_loadRevision;
    if (mounted) setState(() => _isLoading = true);

    try {
      final timeRange = _getTimeRange();
      final tokenService = OpenCoreBinding.instance.tokenUsage;

      // 获取总汇总
      final totalSummary = await tokenService.getTotalSummary(
        startTime: timeRange.start,
        endTime: timeRange.end,
      );

      // 获取分类汇总
      final typeSummary = await tokenService.getSummaryByType(
        taskType: _selectedTaskType,
        startTime: timeRange.start,
        endTime: timeRange.end,
      );

      // 获取每日数据
      final dailyUsage = await tokenService.getDailyUsageByType(
        taskType: _selectedTaskType,
        startTime: timeRange.start,
        endTime: timeRange.end,
      );

      // 获取详细记录
      final detailedRecords = await tokenService.getDetailedRecords(
        taskType: _selectedTaskType,
        startTime: timeRange.start,
        endTime: timeRange.end,
        limit: 50,
      );

      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _totalSummary = totalSummary;
        _typeSummary = typeSummary;
        _dailyUsage = dailyUsage;
        _detailedRecords = detailedRecords;
        _isLoading = false;
        _hasLoaded = true;
      });
    } catch (_) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
      });
      if (mounted) {
        AsOneToast.show(context, '用量加载失败，请稍后重试', icon: AsOneIconName.warning);
      }
    }
  }

  ({DateTime? start, DateTime? end}) _getTimeRange() {
    final now = DateTime.now();
    switch (_selectedTimeRange) {
      case 'today':
        final today = DateTime(now.year, now.month, now.day);
        return (start: today, end: null);
      case 'week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final monday = DateTime(weekStart.year, weekStart.month, weekStart.day);
        return (start: monday, end: null);
      case 'month':
        final monthStart = DateTime(now.year, now.month, 1);
        return (start: monthStart, end: null);
      case 'all':
        return (start: null, end: null);
      default:
        return (start: null, end: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsOneTheme.pageBg,
      appBar: const AsOneAppBar(title: '用量统计'),
      body: !_hasLoaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      // 总用量卡片
                      _buildSummaryCard(),
                      const SizedBox(height: 16),

                      // 时间范围选择
                      _buildTimeRangeSelector(),
                      const SizedBox(height: 16),

                      // 任务类型选择
                      _buildTaskTypeSelector(),
                      const SizedBox(height: 16),

                      // 分类统计
                      _buildTypeSummaryCard(),
                      const SizedBox(height: 16),

                      // 图表
                      if (_dailyUsage.isNotEmpty) ...[
                        _buildChart(),
                        const SizedBox(height: 16),
                      ],

                      // 详细记录
                      _buildDetailedRecords(),
                    ],
                  ),
                ),
                if (_isLoading)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_getTimeRangeTitle(), style: AsOneTheme.sectionTitleStyle),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    '输入',
                    _formatTokens(_totalSummary.inputTokens),
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    '输出',
                    _formatTokens(_totalSummary.outputTokens),
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    '总计',
                    _formatTokens(_totalSummary.totalTokens),
                    AsOneTheme.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: AsOneTheme.captionStyle),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRangeSelector() {
    return Row(
      children: [
        _buildTimeRangeChip('今日', 'today'),
        const SizedBox(width: 8),
        _buildTimeRangeChip('本周', 'week'),
        const SizedBox(width: 8),
        _buildTimeRangeChip('本月', 'month'),
        const SizedBox(width: 8),
        _buildTimeRangeChip('全部', 'all'),
      ],
    );
  }

  Widget _buildTimeRangeChip(String label, String value) {
    final isSelected = _selectedTimeRange == value;
    return Expanded(
      child: Material(
        color: isSelected ? AsOneTheme.selectedBg : const Color(0xFFFFFDFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isSelected
                ? AsOneTheme.accent.withValues(alpha: 0.40)
                : const Color(0xFFF0E5E0),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isSelected
              ? null
              : () {
                  setState(() => _selectedTimeRange = value);
                  _loadData();
                },
          child: SizedBox(
            height: 42,
            child: Center(
              child: Text(
                label,
                style: AsOneTheme.secondaryStyle.copyWith(
                  color: isSelected
                      ? AsOneTheme.accent
                      : AsOneTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '任务类型',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AsOneTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildTaskTypeChip('对话', 'chat'),
            const SizedBox(width: 8),
            _buildTaskTypeChip('记忆整理', 'memory_rebuild'),
            const SizedBox(width: 8),
            _buildTaskTypeChip('功能', 'function'),
          ],
        ),
      ],
    );
  }

  Widget _buildTaskTypeChip(String label, String value) {
    final isSelected = _selectedTaskType == value;
    return Expanded(
      child: Material(
        color: isSelected ? AsOneTheme.selectedBg : const Color(0xFFFFFDFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isSelected
                ? AsOneTheme.accent.withValues(alpha: 0.40)
                : const Color(0xFFF0E5E0),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isSelected
              ? null
              : () {
                  setState(() => _selectedTaskType = value);
                  _loadData();
                },
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: AsOneTheme.secondaryStyle.copyWith(
                  color: isSelected
                      ? AsOneTheme.accent
                      : AsOneTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_getTaskTypeLabel(_selectedTaskType)}用量',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const AsOneIcon(
                  AsOneIconName.arrowUp,
                  size: 16,
                  color: Colors.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  '输入: ${_formatTokens(_typeSummary.inputTokens)}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 16),
                const AsOneIcon(
                  AsOneIconName.arrowDown,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  '输出: ${_formatTokens(_typeSummary.outputTokens)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_dailyUsage.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每日趋势',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxYValue(),
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < _dailyUsage.length) {
                            final date = _dailyUsage[value.toInt()].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('M/d').format(date),
                                style: AsOneTheme.captionStyle,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            _formatTokensShort(value.toInt()),
                            style: AsOneTheme.captionStyle,
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _dailyUsage.asMap().entries.map((entry) {
                    final index = entry.key;
                    final usage = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: usage.inputTokens.toDouble(),
                          color: Colors.blue,
                          width: 8,
                        ),
                        BarChartRodData(
                          toY: usage.outputTokens.toDouble(),
                          color: Colors.orange,
                          width: 8,
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('输入', Colors.blue),
                const SizedBox(width: 16),
                _buildLegendItem('输出', Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: AsOneTheme.captionStyle),
      ],
    );
  }

  Widget _buildDetailedRecords() {
    if (_detailedRecords.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('暂无记录', style: AsOneTheme.secondaryStyle)),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '详细记录',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          ..._detailedRecords.map((record) => _buildRecordItem(record)),
        ],
      ),
    );
  }

  Widget _buildRecordItem(TokenUsageRecord record) {
    return InkWell(
      onTap: () {
        // 可以导航到对话详情等
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatRecordTime(record.createdAt),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTaskTypeLabel(record.taskType),
                    style: AsOneTheme.captionStyle,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '↑ ${_formatTokens(record.inputTokens)}',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
                Text(
                  '↓ ${_formatTokens(record.outputTokens)}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeRangeTitle() {
    switch (_selectedTimeRange) {
      case 'today':
        return '今日总用量';
      case 'week':
        return '本周总用量';
      case 'month':
        return '本月总用量';
      case 'all':
        return '全部总用量';
      default:
        return '总用量';
    }
  }

  String _getTaskTypeLabel(String taskType) {
    switch (taskType) {
      case 'chat':
        return '对话';
      case 'memory_rebuild':
        return '记忆整理';
      case 'function':
        return '功能';
      default:
        return taskType;
    }
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    } else {
      return tokens.toString();
    }
  }

  String _formatTokensShort(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(0)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(0)}K';
    } else {
      return tokens.toString();
    }
  }

  String _formatRecordTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDay = DateTime(time.year, time.month, time.day);

    if (recordDay == today) {
      return DateFormat('HH:mm').format(time);
    } else if (recordDay == today.subtract(const Duration(days: 1))) {
      return '昨天 ${DateFormat('HH:mm').format(time)}';
    } else if (time.year == now.year) {
      return DateFormat('M月d日 HH:mm').format(time);
    } else {
      return DateFormat('yyyy年M月d日').format(time);
    }
  }

  double _getMaxYValue() {
    if (_dailyUsage.isEmpty) return 100;
    final maxInput = _dailyUsage
        .map((e) => e.inputTokens)
        .reduce((a, b) => a > b ? a : b);
    final maxOutput = _dailyUsage
        .map((e) => e.outputTokens)
        .reduce((a, b) => a > b ? a : b);
    final max = maxInput > maxOutput ? maxInput : maxOutput;
    return (max * 1.2).toDouble(); // 留20%余量
  }
}
