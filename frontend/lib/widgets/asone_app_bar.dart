import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_icons.dart';

class AsOneAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AsOneAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: subtitle == null
          ? Text(title)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AsOneTheme.captionStyle.copyWith(
                    color: AsOneTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
      leading:
          leading ??
          (Navigator.of(context).canPop()
              ? AsOneIconButton(
                  icon: AsOneIconName.back,
                  tooltip: '返回',
                  onPressed: () => Navigator.maybePop(context),
                )
              : null),
      actions: actions,
    );
  }
}
