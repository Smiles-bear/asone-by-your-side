import 'package:asone_contracts/asone_contracts.dart';
import 'pages/assistant_system_prompt_page.dart';
import 'pages/assistant_user_profile_page.dart';
import 'widgets/asone_feedback.dart';
import 'package:flutter/material.dart';

/// Resolve the latest assistant within the installed community scope before
/// opening a reused editor; stale list/chat snapshots must not overwrite edits.
Future<void> openCommunityAssistantSettings(
  BuildContext context,
  String assistantId, {
  bool userProfile = false,
}) async {
  final repository = OpenCoreBinding.instance.assistants;
  try {
    final assistant = await repository.getAssistant(assistantId);
    if (!context.mounted) return;
    if (assistant == null) {
      AsOneToast.show(context, '助手不存在');
      return;
    }
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => userProfile
            ? AssistantUserProfilePage(
                assistant: assistant,
                assistants: repository,
              )
            : AssistantSystemPromptPage(
                assistant: assistant,
                assistants: repository,
              ),
      ),
    );
  } catch (_) {
    if (context.mounted) AsOneToast.show(context, '加载失败');
  }
}
