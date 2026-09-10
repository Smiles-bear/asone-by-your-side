import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';

class AsOneSurface extends StatelessWidget {
  const AsOneSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.constraints,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BoxConstraints? constraints;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      constraints: constraints,
      width: width,
      child: Material(
        color: const Color(0xFFFFFDFC),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFF0E5E0)),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AsOneSectionTitle extends StatelessWidget {
  const AsOneSectionTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AsOneTheme.sectionTitleStyle),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: AsOneTheme.captionStyle.copyWith(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
