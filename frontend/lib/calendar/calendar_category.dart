import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CalendarCategory {
  const CalendarCategory({
    required this.id,
    required this.label,
    required this.strongColor,
    required this.paleColor,
    required this.assetName,
    required this.sheetColumn,
    required this.sheetRow,
  });

  final String id;
  final String label;
  final Color strongColor;
  final Color paleColor;
  final String assetName;
  final int sheetColumn;
  final int sheetRow;

  static const daily = CalendarCategory(
    id: 'daily',
    label: '日常',
    strongColor: Color(0xFFF1AC88),
    paleColor: Color(0xFFFDF0EB),
    assetName: 'daily',
    sheetColumn: 0,
    sheetRow: 0,
  );
  static const work = CalendarCategory(
    id: 'work',
    label: '工作',
    strongColor: Color(0xFFEAAD5A),
    paleColor: Color(0xFFFDF4E5),
    assetName: 'work',
    sheetColumn: 1,
    sheetRow: 0,
  );
  static const study = CalendarCategory(
    id: 'study',
    label: '学习',
    strongColor: Color(0xFF9CB389),
    paleColor: Color(0xFFF2F2E8),
    assetName: 'study',
    sheetColumn: 2,
    sheetRow: 0,
  );
  static const other = CalendarCategory(
    id: 'other',
    label: '其他',
    strongColor: Color(0xFFA39B99),
    paleColor: Color(0xFFF7F2F2),
    assetName: 'other',
    sheetColumn: 3,
    sheetRow: 0,
  );
  static const travel = CalendarCategory(
    id: 'travel',
    label: '旅行',
    strongColor: Color(0xFF9FBAD2),
    paleColor: Color(0xFFF0F3F7),
    assetName: 'travel',
    sheetColumn: 4,
    sheetRow: 0,
  );
  static const health = CalendarCategory(
    id: 'health',
    label: '健康',
    strongColor: Color(0xFFE3938B),
    paleColor: Color(0xFFFCECEA),
    assetName: 'health',
    sheetColumn: 0,
    sheetRow: 1,
  );
  static const anniversary = CalendarCategory(
    id: 'anniversary',
    label: '纪念日',
    strongColor: Color(0xFFCDAC7E),
    paleColor: Color(0xFFFCF4E7),
    assetName: 'anniversary',
    sheetColumn: 1,
    sheetRow: 1,
  );
  static const social = CalendarCategory(
    id: 'social',
    label: '社交',
    strongColor: Color(0xFFAF9DBA),
    paleColor: Color(0xFFF6F1F5),
    assetName: 'social',
    sheetColumn: 1,
    sheetRow: 2,
  );
  static const activity = CalendarCategory(
    id: 'activity',
    label: '活动',
    strongColor: Color(0xFF8BA4C1),
    paleColor: Color(0xFFEFF2F6),
    assetName: 'activity',
    sheetColumn: 2,
    sheetRow: 2,
  );
  static const notification = CalendarCategory(
    id: 'reminder',
    label: '通知',
    strongColor: Color(0xFFE89E9D),
    paleColor: Color(0xFFFDEFED),
    assetName: 'notification',
    sheetColumn: 4,
    sheetRow: 2,
  );

  static const values = <CalendarCategory>[
    daily,
    work,
    study,
    travel,
    health,
    anniversary,
    social,
    activity,
    notification,
    other,
  ];

  static CalendarCategory fromId(String? id) {
    // `fitness` was used before the approved ten-category icon set replaced it
    // with “其他”. Keep old rows renderable without rewriting persisted data.
    if (id == 'fitness') return other;
    return values.firstWhere((value) => value.id == id, orElse: () => daily);
  }
}

/// Renders the approved vector artwork supplied for each calendar category.
class CalendarCategoryIcon extends StatelessWidget {
  const CalendarCategoryIcon({
    super.key,
    required this.category,
    this.size = 42,
  });

  final CalendarCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: Transform.scale(
          scale: 1.65,
          child: SvgPicture.asset(
            'assets/calendar/${category.assetName}.svg',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
