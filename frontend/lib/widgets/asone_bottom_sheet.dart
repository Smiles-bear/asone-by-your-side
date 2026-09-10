import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_icons.dart';

class AsOneSheetAction<T> {
  const AsOneSheetAction({
    this.key,
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final Key? key;
  final T value;
  final String label;
  final AsOneIconName icon;
  final bool destructive;
}

class AsOneBottomSheet {
  const AsOneBottomSheet._();

  static Future<T?> showContent<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    double heightFactor = 0.82,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: heightFactor,
        child: Material(
          color: const Color(0xFFFFFCFA),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Center(
                child: Container(
                  key: const Key('asone-sheet-handle'),
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9CECA),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Expanded(child: builder(sheetContext)),
            ],
          ),
        ),
      ),
    );
  }

  static Future<T?> showActions<T>(
    BuildContext context, {
    String? title,
    required List<AsOneSheetAction<T>> actions,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFCFA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9CECA),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                child: Text(title, style: AsOneTheme.sectionTitleStyle),
              ),
            ],
            ...actions.map(
              (action) => _SheetActionTile<T>(key: action.key, action: action),
            ),
            const SizedBox(height: 4),
            _SheetCancelTile(onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

class _SheetActionTile<T> extends StatelessWidget {
  const _SheetActionTile({super.key, required this.action});

  final AsOneSheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive
        ? AsOneTheme.danger
        : AsOneTheme.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => Navigator.pop(context, action.value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              AsOneIcon(action.icon, size: 21, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  action.label,
                  style: AsOneTheme.bodyStyle.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetCancelTile extends StatelessWidget {
  const _SheetCancelTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              AsOneIcon(AsOneIconName.close, size: 21),
              SizedBox(width: 11),
              Expanded(child: Text('取消', style: AsOneTheme.bodyStyle)),
            ],
          ),
        ),
      ),
    );
  }
}
