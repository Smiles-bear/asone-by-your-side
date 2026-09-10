import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_icons.dart';

enum AsOneButtonTone { primary, secondary, ghost, danger }

class AsOneButton extends StatelessWidget {
  const AsOneButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = AsOneButtonTone.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AsOneButtonTone tone;
  final AsOneIconName? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final foreground = switch (tone) {
      AsOneButtonTone.primary => Colors.white,
      AsOneButtonTone.secondary => AsOneTheme.accent,
      AsOneButtonTone.ghost => AsOneTheme.accent,
      AsOneButtonTone.danger => Colors.white,
    };
    final background = switch (tone) {
      AsOneButtonTone.primary => AsOneTheme.iconAccent,
      AsOneButtonTone.secondary => const Color(0xFFFBEAE4),
      AsOneButtonTone.ghost => Colors.transparent,
      AsOneButtonTone.danger => AsOneTheme.danger,
    };

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  AsOneIcon(icon!, size: 19, color: foreground),
                  const SizedBox(width: 8),
                ],
                Text(label),
              ],
            ),
    );

    final button = TextButton(
      onPressed: loading ? null : onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(88, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        foregroundColor: foreground,
        backgroundColor: background,
        disabledForegroundColor: AsOneTheme.textDisabled,
        disabledBackgroundColor: tone == AsOneButtonTone.ghost
            ? Colors.transparent
            : const Color(0xFFF1E8E4),
        textStyle: AsOneTheme.buttonStyle,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
