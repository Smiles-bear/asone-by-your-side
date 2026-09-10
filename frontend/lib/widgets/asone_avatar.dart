import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';

class AsOneAvatar extends StatelessWidget {
  const AsOneAvatar({
    super.key,
    required this.imagePath,
    required this.size,
    required this.borderRadius,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.backgroundColor,
    this.fallbackText,
  });

  factory AsOneAvatar.assistant({
    Key? key,
    required String imagePath,
    required String name,
    required double size,
    required double borderRadius,
  }) {
    final normalizedName = name.trim();
    return AsOneAvatar(
      key: key,
      imagePath: imagePath,
      size: size,
      borderRadius: borderRadius,
      fallbackIcon: Icons.smart_toy_outlined,
      fallbackText: normalizedName.isEmpty
          ? '助'
          : normalizedName.characters.first,
      fallbackColor: AsOneTheme.accent,
      backgroundColor: AsOneTheme.cardBg,
    );
  }

  final String imagePath;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final Color backgroundColor;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final text = fallbackText?.trim() ?? '';
    final fallback = ColoredBox(
      color: backgroundColor,
      child: Center(
        child: text.isNotEmpty
            ? Text(
                text,
                maxLines: 1,
                style: TextStyle(
                  color: fallbackColor,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Icon(fallbackIcon, size: size * 0.5, color: fallbackColor),
      ),
    );
    final normalizedPath = imagePath.trim();
    Widget image = fallback;
    if (normalizedPath.startsWith('http://') ||
        normalizedPath.startsWith('https://')) {
      image = Image.network(
        normalizedPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else if (normalizedPath.startsWith('assets/')) {
      image = Image.asset(
        normalizedPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else if (normalizedPath.isNotEmpty && !kIsWeb) {
      image = Image.file(
        File(normalizedPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}
