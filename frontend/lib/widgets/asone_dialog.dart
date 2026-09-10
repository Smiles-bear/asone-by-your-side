import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';

class AsOneDialog extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget content;
  final List<Widget> actions;
  final Color? iconColor;

  const AsOneDialog({
    super.key,
    this.icon,
    required this.title,
    required this.content,
    required this.actions,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AsOneTheme.accent;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: const Color(0xFFFFFCFA),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: AsOneTheme.dialogTitleStyle.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 10),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: AsOneTheme.secondaryStyle,
                    textAlign: TextAlign.center,
                    child: content,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Theme(
                  data: Theme.of(context).copyWith(
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(88, 48),
                        foregroundColor: AsOneTheme.accent,
                        backgroundColor: const Color(0xFFFBEAE4),
                        textStyle: AsOneTheme.buttonStyle,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(88, 48),
                        backgroundColor: AsOneTheme.iconAccent,
                        foregroundColor: Colors.white,
                        textStyle: AsOneTheme.buttonStyle,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
