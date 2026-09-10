import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';

class AsOneEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;

  const AsOneEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AsOneTheme.cardBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AsOneTheme.accent),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AsOneTheme.sectionTitleStyle,
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AsOneTheme.secondaryStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
