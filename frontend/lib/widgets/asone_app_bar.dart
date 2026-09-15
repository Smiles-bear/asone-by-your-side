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
    this.mainPage = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool mainPage;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (mainPage ? 1 : 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: mainPage ? AsOneTheme.mainHeaderBg : null,
      surfaceTintColor: mainPage ? Colors.transparent : null,
      scrolledUnderElevation: mainPage ? 0 : null,
      bottom: mainPage
          ? const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: AsOneTheme.mainHeaderDivider),
            )
          : null,
      title: subtitle == null
          ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
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
