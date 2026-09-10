import 'package:flutter/material.dart';

import '../models/assistant.dart';
import '../services/user_identity_service.dart';
import '../theme/asone_theme.dart';
import 'asone_avatar.dart';

class MindSourceIdentity extends StatelessWidget {
  const MindSourceIdentity({
    super.key,
    required this.authorType,
    this.authorAssistantId,
    required this.assistants,
    this.compact = false,
  });

  final String authorType;
  final String? authorAssistantId;
  final Map<String, Assistant> assistants;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final assistant = assistants[authorAssistantId];
    final identity = UserIdentityService.instance.value;
    final isUser = authorType == 'user';
    final isAssistant = authorType == 'assistant';
    final name = isUser
        ? '我'
        : isAssistant
        ? assistant?.name ?? '已删除的助手'
        : '系统';
    final imagePath = isUser ? identity.avatarPath : assistant?.avatar ?? '';
    final size = compact ? 22.0 : 28.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AsOneAvatar(
          imagePath: imagePath,
          size: size,
          borderRadius: size / 2,
          fallbackIcon: isUser
              ? Icons.person_outline
              : Icons.smart_toy_outlined,
          fallbackColor: AsOneTheme.textSecondary,
          backgroundColor: Colors.white.withValues(alpha: 0.72),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact
                ? AsOneTheme.microStyle.copyWith(
                    color: AsOneTheme.textSecondary,
                  )
                : AsOneTheme.captionStyle,
          ),
        ),
      ],
    );
  }
}
