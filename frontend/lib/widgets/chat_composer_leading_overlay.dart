import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pins only the leading controls; the existing row still lays out the input
/// and trailing controls. The single-line inset includes the wrapping hint.
class ChatComposerLeadingOverlay extends StatelessWidget {
  const ChatComposerLeadingOverlay({
    super.key,
    required this.controller,
    required this.leading,
    required this.child,
    required this.leadingWidth,
    required this.hintText,
    required this.voiceMode,
    required this.busy,
    required this.showSendWhenEmpty,
  });

  final TextEditingController controller;
  final Widget leading;
  final Widget child;
  final double leadingWidth;
  final String hintText;
  final bool voiceMode;
  final bool busy;
  final bool showSendWhenEmpty;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        child: child,
        builder: (context, value, body) => LayoutBuilder(
          builder: (context, constraints) {
            final showSend =
                busy || showSendWhenEmpty || value.text.trim().isNotEmpty;
            final trailingWidth = voiceMode || !showSend
                ? 48.0
                : busy
                ? 57.0
                : 59.0;
            var singleLineHeight = 51.0;
            if (!voiceMode) {
              final theme = Theme.of(context);
              final base = theme.useMaterial3
                  ? theme.textTheme.bodyLarge!
                  : theme.textTheme.titleMedium!;
              final painter =
                  TextPainter(
                    text: TextSpan(
                      text: hintText,
                      style: base.copyWith(fontSize: 16, letterSpacing: -.48),
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 5,
                  )..layout(
                    maxWidth: math.max(
                      1,
                      constraints.maxWidth - leadingWidth - trailingWidth,
                    ),
                  );
              singleLineHeight = math.max(
                singleLineHeight,
                painter.height + 24,
              );
              painter.dispose();
            }
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                body!,
                Positioned(
                  left: 0,
                  bottom: (singleLineHeight - 48) / 2,
                  child: leading,
                ),
              ],
            );
          },
        ),
      );
}
