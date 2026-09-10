import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_icons.dart';

class AsOneSettingsSection extends StatelessWidget {
  const AsOneSettingsSection({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              label!,
              style: AsOneTheme.captionStyle.copyWith(fontSize: 13),
            ),
          ),
        ],
        Material(
          color: const Color(0xFFFFFDFC),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFF0E5E0)),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1)
                  const Divider(height: 1, indent: 58, endIndent: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class AsOneSettingsTile extends StatelessWidget {
  const AsOneSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.iconBackgroundColor,
    this.enabled = true,
  });

  final AsOneIconName icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = enabled
        ? iconColor ?? AsOneTheme.iconAccent
        : AsOneTheme.iconDisabled;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackgroundColor ?? const Color(0xFFFFF0EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: AsOneIcon(icon, size: 20, color: effectiveIconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AsOneTheme.listTitleStyle.copyWith(
                        fontSize: 15,
                        color: enabled
                            ? AsOneTheme.textPrimary
                            : AsOneTheme.textDisabled,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AsOneTheme.captionStyle),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  const AsOneIcon(
                    AsOneIconName.forward,
                    size: 19,
                    color: AsOneTheme.textTertiary,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
