import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_icons.dart';

enum AsOneButtonTone { primary, secondary, ghost, danger, dangerOutline }

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
      AsOneButtonTone.danger => AsOneTheme.danger,
      AsOneButtonTone.dangerOutline => AsOneTheme.danger,
    };
    final background = switch (tone) {
      AsOneButtonTone.primary => AsOneTheme.iconAccent,
      AsOneButtonTone.secondary => const Color(0xFFFBEAE4),
      AsOneButtonTone.ghost => Colors.transparent,
      AsOneButtonTone.danger => AsOneTheme.dangerSoft,
      AsOneButtonTone.dangerOutline => Colors.transparent,
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
                  AsOneIcon(
                    icon!,
                    size: 19,
                    color: onPressed == null
                        ? AsOneTheme.textDisabled
                        : foreground,
                  ),
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
            : AsOneTheme.disabledActionBg,
        side:
            tone == AsOneButtonTone.dangerOutline ||
                tone == AsOneButtonTone.danger
            ? BorderSide(
                color: onPressed == null || loading
                    ? AsOneTheme.divider
                    : AsOneTheme.danger.withValues(alpha: 0.5),
              )
            : BorderSide.none,
        textStyle: AsOneTheme.buttonStyle,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
