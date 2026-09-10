/// 标准文本输入对话框（新增场景，无编辑）
///
/// controller 由对话框自身 State 持有并随路由卸载释放，
/// 避免"弹窗退出动画期间 controller 已 dispose"的问题。
library;

import 'package:flutter/material.dart';

import '../theme/asone_theme.dart';
import 'asone_button.dart';
import 'asone_icons.dart';

class AsOneInputDialog extends StatefulWidget {
  const AsOneInputDialog({
    super.key,
    required this.title,
    this.hintText,
    this.initialValue,
    required this.confirmLabel,
    this.maxLength = 100,
    this.maxLines = 3,
  });

  /// 对话框标题
  final String title;

  /// 输入提示
  final String? hintText;

  /// 输入框初始内容（编辑、重命名场景）
  final String? initialValue;

  /// 确认按钮文案
  final String confirmLabel;

  /// 最大字数
  final int maxLength;

  /// 最大行数
  final int maxLines;

  /// 弹出对话框，返回输入文本（取消返回 null，空输入也返回 null）
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? hintText,
    String? initialValue,
    required String confirmLabel,
    int maxLength = 100,
    int maxLines = 3,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => AsOneInputDialog(
        title: title,
        hintText: hintText,
        initialValue: initialValue,
        confirmLabel: confirmLabel,
        maxLength: maxLength,
        maxLines: maxLines,
      ),
    );
  }

  @override
  State<AsOneInputDialog> createState() => _AsOneInputDialogState();
}

class _AsOneInputDialogState extends State<AsOneInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: const Color(0xFFFFFCFA),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AsOneTheme.dialogTitleStyle.copyWith(fontSize: 19),
                    ),
                  ),
                  AsOneIconButton(
                    icon: AsOneIconName.close,
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    iconSize: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: widget.maxLength,
                minLines: 2,
                maxLines: widget.maxLines,
                style: AsOneTheme.bodyStyle,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE9B7A6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE9B7A6)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AsOneTheme.iconAccent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AsOneButton(
                      label: '取消',
                      onPressed: () => Navigator.pop(context),
                      tone: AsOneButtonTone.secondary,
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AsOneButton(
                      label: widget.confirmLabel,
                      onPressed: () {
                        final text = _controller.text.trim();
                        Navigator.pop(context, text.isEmpty ? null : text);
                      },
                      expand: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
