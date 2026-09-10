import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_button.dart';
import 'asone_icons.dart';

class AsOneBanner extends StatelessWidget {
  const AsOneBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final AsOneIconName icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3EE),
        border: Border.all(color: const Color(0xFFEFCABC)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE4DB),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: AsOneIcon(icon, color: AsOneTheme.iconAccent, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AsOneTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: AsOneTheme.captionStyle.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            AsOneButton(
              label: actionLabel!,
              onPressed: onAction,
              tone: AsOneButtonTone.ghost,
            ),
          ],
        ],
      ),
    );
  }
}

class AsOneToast {
  const AsOneToast._();

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    AsOneIconName icon = AsOneIconName.success,
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    return messenger.showSnackBar(
      snackBar(message, icon: icon, duration: duration),
    );
  }

  static SnackBar snackBar(
    String message, {
    AsOneIconName icon = AsOneIconName.success,
    Duration duration = const Duration(seconds: 2),
  }) => SnackBar(
    dismissDirection: DismissDirection.horizontal,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    duration: duration,
    padding: EdgeInsets.zero,
    backgroundColor: Colors.transparent,
    elevation: 0,
    content: Center(
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF3D3531),
          borderRadius: BorderRadius.circular(13),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AsOneIcon(icon, size: 19, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: AsOneTheme.secondaryStyle.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
