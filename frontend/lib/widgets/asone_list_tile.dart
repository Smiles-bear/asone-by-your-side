import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_avatar.dart';

class AsOneListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? time;
  final IconData fallbackIcon;
  final String? fallbackText;
  final String avatarPath;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showIndicator;

  /// subtitle 超宽截断方式，默认保持原有 ellipsis；对话列表传 fade 实现右侧淡出。
  final TextOverflow subtitleOverflow;

  const AsOneListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.fallbackIcon,
    this.fallbackText,
    this.avatarPath = '',
    this.time,
    this.onTap,
    this.onLongPress,
    this.showIndicator = false,
    this.subtitleOverflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AsOneAvatar.assistant(
                    imagePath: avatarPath,
                    name: fallbackText ?? title,
                    size: 50,
                    borderRadius: 14,
                  ),
                  if (showIndicator)
                    const Positioned(
                      key: Key('asone-list-tile-indicator'),
                      right: -2,
                      top: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AsOneTheme.notificationBadge,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: 9),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AsOneTheme.listTitleStyle,
                          ),
                        ),
                        if (time != null)
                          Text(time!, style: AsOneTheme.captionStyle),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: subtitleOverflow,
                      style: AsOneTheme.secondaryStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
