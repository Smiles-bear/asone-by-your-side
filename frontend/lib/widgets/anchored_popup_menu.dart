import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/asone_theme.dart';
import 'asone_icons.dart';

enum AnchoredPopupDirection { above, below }

class AnchoredPopupMenuEntry<T> {
  const AnchoredPopupMenuEntry({
    required this.value,
    required this.label,
    this.key,
    this.assetPath,
    this.icon,
    this.iconSize = 24,
  }) : assert(assetPath == null || icon == null);

  final T value;
  final String label;
  final Key? key;
  final String? assetPath;
  final AsOneIconName? icon;
  final double iconSize;
}

Future<T?> showAnchoredPopupMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<AnchoredPopupMenuEntry<T>> entries,
  AnchoredPopupDirection direction = AnchoredPopupDirection.below,
  double? width,
  double rowHeight = 48,
  bool showDividers = false,
  bool dismissOnAnchorTap = false,
}) {
  final anchorRenderObject = anchorKey.currentContext?.findRenderObject();
  final overlayRenderObject = Navigator.of(
    context,
  ).overlay?.context.findRenderObject();
  if (anchorRenderObject is! RenderBox || overlayRenderObject is! RenderBox) {
    return Future<T?>.value();
  }

  final anchorTopLeft = anchorRenderObject.localToGlobal(
    Offset.zero,
    ancestor: overlayRenderObject,
  );
  final anchorRect = anchorTopLeft & anchorRenderObject.size;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      const screenMargin = 12.0;
      const tailHeight = 8.0;
      const anchorGap = 2.0;
      const verticalPadding = 4.0;
      const horizontalPadding = 16.0;
      const iconGap = 12.0;
      const menuTextStyle = AsOneTheme.listTitleStyle;
      final screenSize = MediaQuery.sizeOf(dialogContext);

      var measuredWidth = 0.0;
      for (final entry in entries) {
        final textPainter = TextPainter(
          text: TextSpan(text: entry.label, style: menuTextStyle),
          maxLines: 1,
          textDirection: Directionality.of(dialogContext),
        )..layout();
        final iconWidth = entry.assetPath == null && entry.icon == null
            ? 0.0
            : entry.iconSize + iconGap;
        measuredWidth = math.max(
          measuredWidth,
          horizontalPadding * 2 + iconWidth + textPainter.width,
        );
      }
      final popupWidth = (width ?? measuredWidth)
          .clamp(120.0, math.min(220.0, screenSize.width - screenMargin * 2))
          .toDouble();
      final dividerHeight = showDividers
          ? math.max(0, entries.length - 1).toDouble()
          : 0.0;
      final bubbleHeight =
          entries.length * rowHeight + verticalPadding * 2 + dividerHeight;
      final popupHeight = bubbleHeight + tailHeight;
      final belowFits =
          anchorRect.bottom + anchorGap + popupHeight <=
          screenSize.height -
              screenMargin -
              MediaQuery.paddingOf(dialogContext).bottom;
      final aboveFits =
          anchorRect.top - anchorGap - popupHeight >=
          screenMargin + MediaQuery.paddingOf(dialogContext).top;
      final effectiveDirection = direction == AnchoredPopupDirection.below
          ? (belowFits || !aboveFits ? direction : AnchoredPopupDirection.above)
          : (aboveFits || !belowFits
                ? direction
                : AnchoredPopupDirection.below);
      final preferredLeft = effectiveDirection == AnchoredPopupDirection.below
          ? anchorRect.center.dx - popupWidth + 26
          : anchorRect.center.dx - 26;
      final left = preferredLeft
          .clamp(
            screenMargin,
            math.max(
              screenMargin,
              screenSize.width - popupWidth - screenMargin,
            ),
          )
          .toDouble();
      final tailCenter = (anchorRect.center.dx - left).clamp(
        20.0,
        popupWidth - 20.0,
      );
      final preferredTop = effectiveDirection == AnchoredPopupDirection.below
          ? anchorRect.bottom + anchorGap
          : anchorRect.top - popupHeight - anchorGap;
      final top = preferredTop
          .clamp(
            screenMargin,
            math.max(
              screenMargin,
              screenSize.height - popupHeight - screenMargin,
            ),
          )
          .toDouble();
      final pointsUp = effectiveDirection == AnchoredPopupDirection.below;

      final menuContent = Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: verticalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                if (index > 0 && showDividers)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Divider(
                      height: 1,
                      thickness: 0.7,
                      color: Color(0xFFE6E6E6),
                    ),
                  ),
                InkWell(
                  key: entries[index].key,
                  onTap: () =>
                      Navigator.of(dialogContext).pop(entries[index].value),
                  child: SizedBox(
                    height: rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Row(
                        children: [
                          if (entries[index].icon != null ||
                              entries[index].assetPath != null) ...[
                            if (entries[index].icon case final icon?)
                              AsOneIcon(icon, size: entries[index].iconSize)
                            else
                              Transform.scale(
                                scale: 2.55,
                                child:
                                    entries[index].assetPath!.endsWith('.svg')
                                    ? SvgPicture.asset(
                                        entries[index].assetPath!,
                                        width: entries[index].iconSize,
                                        height: entries[index].iconSize,
                                        fit: BoxFit.contain,
                                      )
                                    : Image.asset(
                                        entries[index].assetPath!,
                                        width: entries[index].iconSize,
                                        height: entries[index].iconSize,
                                        fit: BoxFit.contain,
                                      ),
                              ),
                            const SizedBox(width: iconGap),
                          ],
                          Text(
                            entries[index].label,
                            maxLines: 1,
                            style: menuTextStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      return Stack(
        children: [
          if (dismissOnAnchorTap)
            Positioned.fromRect(
              rect: anchorRect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          Positioned(
            left: left,
            top: top,
            width: popupWidth,
            height: popupHeight,
            child: PhysicalShape(
              clipper: _PopupShapeClipper(
                tailCenter: tailCenter,
                tailHeight: tailHeight,
                pointsUp: pointsUp,
              ),
              clipBehavior: Clip.antiAlias,
              color: const Color(0xFFFFFCFA),
              shadowColor: Colors.black.withValues(alpha: 0.12),
              elevation: 6,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: pointsUp ? tailHeight : 0,
                    height: bubbleHeight,
                    child: menuContent,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _PopupShapeClipper extends CustomClipper<Path> {
  const _PopupShapeClipper({
    required this.tailCenter,
    required this.tailHeight,
    required this.pointsUp,
  });

  final double tailCenter;
  final double tailHeight;
  final bool pointsUp;

  @override
  Path getClip(Size size) {
    const radius = Radius.circular(14);
    const tailHalfWidth = 8.0;
    final bodyRect = pointsUp
        ? Rect.fromLTWH(0, tailHeight, size.width, size.height - tailHeight)
        : Rect.fromLTWH(0, 0, size.width, size.height - tailHeight);
    final body = Path()..addRRect(RRect.fromRectAndRadius(bodyRect, radius));
    final tail = Path();
    if (pointsUp) {
      tail
        ..moveTo(tailCenter, 0)
        ..lineTo(tailCenter - tailHalfWidth, tailHeight)
        ..lineTo(tailCenter + tailHalfWidth, tailHeight);
    } else {
      tail
        ..moveTo(tailCenter - tailHalfWidth, size.height - tailHeight)
        ..lineTo(tailCenter + tailHalfWidth, size.height - tailHeight)
        ..lineTo(tailCenter, size.height);
    }
    tail.close();
    return Path.combine(PathOperation.union, body, tail);
  }

  @override
  bool shouldReclip(covariant _PopupShapeClipper oldClipper) {
    return tailCenter != oldClipper.tailCenter ||
        tailHeight != oldClipper.tailHeight ||
        pointsUp != oldClipper.pointsUp;
  }
}
