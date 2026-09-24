import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/asone_theme.dart';
import 'asone_feedback.dart';
import 'asone_icons.dart';
import 'asone_line_asset_icon.dart';

class AsOneChatTextField extends StatelessWidget {
  const AsOneChatTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '发消息或按住说话...',
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;

  @override
  Widget build(BuildContext context) => TextField(
    focusNode: focusNode,
    controller: controller,
    minLines: 1,
    maxLines: 5,
    textInputAction: TextInputAction.newline,
    style: const TextStyle(
      color: Color(0xFF535353),
      fontSize: 16,
      letterSpacing: -0.48,
    ),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFFC2C2C2),
        fontSize: 16,
        letterSpacing: -0.48,
      ),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
  );
}

class AsOneChatSendButton extends StatelessWidget {
  const AsOneChatSendButton({
    super.key,
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onStop,
    this.hasPendingAttachments = false,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback? onSend;
  final VoidCallback? onStop;
  final bool hasPendingAttachments;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          final showAction = busy || hasText || hasPendingAttachments;
          if (!showAction) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 4),
              GestureDetector(
                key: Key(busy ? 'chat-stop-button' : 'chat-send-button'),
                behavior: HitTestBehavior.opaque,
                onTap: busy ? onStop : onSend,
                child: busy
                    ? const SizedBox(
                        width: 45,
                        height: 44,
                        child: Center(child: AsOneLineAssetIcon.stop()),
                      )
                    : Opacity(
                        opacity: onSend == null ? 0.45 : 1,
                        child: Container(
                          width: 47,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AsOneTheme.accent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '发送',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.45,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
            ],
          );
        },
      );
}

enum _AsOneVoiceReleaseTarget { send, cancel, toText }

class AsOneChatInputBar extends StatefulWidget {
  const AsOneChatInputBar({
    super.key,
    required this.controller,
    required this.busy,
    required this.voiceEnabled,
    required this.attachmentMenuOpen,
    this.hasPendingAttachments = false,
    required this.onSend,
    required this.onStop,
    required this.onAdd,
    required this.onVoiceStart,
    required this.onVoiceFinish,
    required this.onVoiceToText,
    required this.onVoiceCancel,
    required this.onVoiceAmplitude,
    required this.addButtonKey,
    this.header,
    this.onInputTap,
    this.reserveBottomInset = true,
  });

  final TextEditingController controller;
  final bool busy;
  final bool voiceEnabled;
  final bool attachmentMenuOpen;
  final bool hasPendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAdd;
  final Future<bool> Function() onVoiceStart;
  final Future<void> Function() onVoiceFinish;
  final Future<void> Function() onVoiceToText;
  final Future<void> Function() onVoiceCancel;
  final Stream<double> Function() onVoiceAmplitude;
  final GlobalKey addButtonKey;
  final Widget? header;
  final VoidCallback? onInputTap;
  final bool reserveBottomInset;

  @override
  State<AsOneChatInputBar> createState() => _AsOneChatInputBarState();
}

class _AsOneChatInputBarState extends State<AsOneChatInputBar> {
  final FocusNode _focusNode = FocusNode();
  bool _voiceMode = false;
  bool _recording = false;
  bool _pressHeld = false;
  bool _startingRecording = false;
  Timer? _warningTimer;
  Timer? _limitTimer;
  StreamSubscription<double>? _amplitudeSubscription;
  OverlayEntry? _recordingOverlay;
  _AsOneVoiceReleaseTarget _releaseTarget = _AsOneVoiceReleaseTarget.send;
  double _amplitude = 0.12;

  @override
  void dispose() {
    _focusNode.dispose();
    _warningTimer?.cancel();
    _limitTimer?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    _removeRecordingOverlay();
    super.dispose();
  }

  void _showVoiceMode() {
    if (widget.busy) return;
    if (!widget.voiceEnabled) {
      AsOneToast.show(context, '该助手的语音功能已关闭');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _voiceMode = true;
      _recording = false;
    });
  }

  void _showKeyboardMode() {
    widget.onInputTap?.call();
    setState(() {
      _voiceMode = false;
      _recording = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _startVoicePress(LongPressStartDetails _) async {
    if (!_voiceMode || widget.busy) return;
    _pressHeld = true;
    _startingRecording = true;
    final started = await widget.onVoiceStart();
    _startingRecording = false;
    if (!mounted || !started) return;
    if (!_pressHeld) {
      await widget.onVoiceCancel();
      return;
    }
    setState(() {
      _recording = true;
      _releaseTarget = _AsOneVoiceReleaseTarget.send;
      _amplitude = 0.12;
    });
    _showRecordingOverlay();
    _amplitudeSubscription = widget.onVoiceAmplitude().listen((value) {
      if (!mounted || !_recording) return;
      _amplitude = value;
      _recordingOverlay?.markNeedsBuild();
    });
    _warningTimer = Timer(const Duration(seconds: 110), () {
      if (!mounted || !_recording) return;
      AsOneToast.show(context, '录音将在 10 秒后自动结束');
    });
    _limitTimer = Timer(const Duration(seconds: 120), () {
      if (_recording) {
        _releaseTarget = _AsOneVoiceReleaseTarget.send;
        unawaited(_finishVoicePress());
      }
    });
    unawaited(HapticFeedback.selectionClick());
  }

  void _moveVoicePress(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    final size = MediaQuery.sizeOf(context);
    final position = details.globalPosition;
    final next = position.dy > size.height * 0.68
        ? position.dx < size.width * 0.42
              ? _AsOneVoiceReleaseTarget.cancel
              : position.dx > size.width * 0.58
              ? _AsOneVoiceReleaseTarget.toText
              : _AsOneVoiceReleaseTarget.send
        : _AsOneVoiceReleaseTarget.send;
    if (next == _releaseTarget) return;
    _releaseTarget = next;
    _recordingOverlay?.markNeedsBuild();
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _finishVoicePress([LongPressEndDetails? _]) async {
    _pressHeld = false;
    if (!_recording) return;
    _warningTimer?.cancel();
    _limitTimer?.cancel();
    final amplitudeSubscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (amplitudeSubscription != null) {
      unawaited(amplitudeSubscription.cancel());
    }
    final target = _releaseTarget;
    _removeRecordingOverlay();
    setState(() => _recording = false);
    switch (target) {
      case _AsOneVoiceReleaseTarget.send:
        await widget.onVoiceFinish();
        break;
      case _AsOneVoiceReleaseTarget.cancel:
        await widget.onVoiceCancel();
        break;
      case _AsOneVoiceReleaseTarget.toText:
        await widget.onVoiceToText();
        if (mounted) _showKeyboardMode();
        break;
    }
  }

  Future<void> _cancelVoicePress() async {
    _pressHeld = false;
    _warningTimer?.cancel();
    _limitTimer?.cancel();
    if (_startingRecording || !_recording) return;
    final amplitudeSubscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    if (amplitudeSubscription != null) {
      unawaited(amplitudeSubscription.cancel());
    }
    _removeRecordingOverlay();
    setState(() => _recording = false);
    await widget.onVoiceCancel();
  }

  void _showRecordingOverlay() {
    _removeRecordingOverlay();
    _recordingOverlay = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _AsOneVoiceRecordingOverlay(
          target: _releaseTarget,
          amplitude: _amplitude,
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_recordingOverlay!);
  }

  void _removeRecordingOverlay() {
    _recordingOverlay?.remove();
    _recordingOverlay = null;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: widget.reserveBottomInset,
    child: ColoredBox(
      color: const Color(0xFFFFF5F2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.header != null) widget.header!,
            Container(
              constraints: const BoxConstraints(minHeight: 51),
              padding: const EdgeInsets.symmetric(horizontal: 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 4.6,
                    offset: const Offset(1, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  KeyedSubtree(
                    key: widget.addButtonKey,
                    child: GestureDetector(
                      key: const Key('chat-add-button'),
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.busy ? null : widget.onAdd,
                      child: SizedBox(
                        width: 40,
                        height: 48,
                        child: Center(
                          child: Transform.translate(
                            offset: const Offset(4, 0),
                            child: widget.attachmentMenuOpen
                                ? const AsOneIcon(
                                    AsOneIconName.close,
                                    color: AsOneTheme.iconAccent,
                                  )
                                : const AsOneIcon(AsOneIconName.add),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _voiceMode
                        ? GestureDetector(
                            key: const Key('chat-hold-to-talk'),
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart: _startVoicePress,
                            onLongPressMoveUpdate: _moveVoicePress,
                            onLongPressEnd: _finishVoicePress,
                            onLongPressCancel: _cancelVoicePress,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _recording
                                    ? const Color(0x1FE78C71)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _recording ? '松开结束' : '长按说话',
                                style: TextStyle(
                                  color: _recording
                                      ? const Color(0xFFE78C71)
                                      : const Color(0xFF535353),
                                  fontSize: 16,
                                  letterSpacing: -0.48,
                                ),
                              ),
                            ),
                          )
                        : AsOneChatTextField(
                            focusNode: _focusNode,
                            controller: widget.controller,
                          ),
                  ),
                  if (_voiceMode)
                    GestureDetector(
                      key: const Key('chat-keyboard-button'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _showKeyboardMode,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(child: AsOneIcon(AsOneIconName.keyboard)),
                      ),
                    )
                  else
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) {
                        final showSend =
                            widget.busy ||
                            widget.hasPendingAttachments ||
                            value.text.trim().isNotEmpty;
                        if (showSend) {
                          return AsOneChatSendButton(
                            controller: widget.controller,
                            hasPendingAttachments: widget.hasPendingAttachments,
                            busy: widget.busy,
                            onSend: widget.onSend,
                            onStop: widget.onStop,
                          );
                        }
                        return GestureDetector(
                          key: const Key('chat-voice-button'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _showVoiceMode,
                          child: Opacity(
                            opacity: widget.voiceEnabled ? 1 : 0.45,
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: AsOneIcon(AsOneIconName.microphone),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AsOneVoiceRecordingOverlay extends StatelessWidget {
  const _AsOneVoiceRecordingOverlay({
    required this.target,
    required this.amplitude,
  });

  final _AsOneVoiceReleaseTarget target;
  final double amplitude;

  @override
  Widget build(BuildContext context) {
    final accent = switch (target) {
      _AsOneVoiceReleaseTarget.cancel => AsOneTheme.danger,
      _AsOneVoiceReleaseTarget.send ||
      _AsOneVoiceReleaseTarget.toText => AsOneTheme.iconAccent,
    };
    final instruction = switch (target) {
      _AsOneVoiceReleaseTarget.send => '松手发送',
      _AsOneVoiceReleaseTarget.cancel => '松手取消',
      _AsOneVoiceReleaseTarget.toText => '松手转文字',
    };
    return Material(
      color: Colors.transparent,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.46),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Align(
                  alignment: const Alignment(0, -0.16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (constraints.maxWidth - 48).clamp(260.0, 320.0),
                    ),
                    child: AnimatedContainer(
                      key: const Key('voice-recording-card'),
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDFC),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFF0E5E0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.13),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: AsOneIcon(
                              AsOneIconName.microphone,
                              color: accent,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: 68,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            alignment: Alignment.center,
                            child: _AsOneVoiceAmplitudeWave(
                              amplitude: amplitude,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            instruction,
                            style: AsOneTheme.displayTitleStyle.copyWith(
                              color: accent,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            '左右滑动可取消或转成文字',
                            style: AsOneTheme.secondaryStyle,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    child: Row(
                      children: [
                        Expanded(
                          child: _AsOneVoiceReleaseChoice(
                            key: const Key('voice-cancel-target'),
                            icon: AsOneIconName.close,
                            label: '取消',
                            accent: AsOneTheme.danger,
                            selected: target == _AsOneVoiceReleaseTarget.cancel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AsOneVoiceReleaseChoice(
                            key: const Key('voice-text-target'),
                            icon: AsOneIconName.document,
                            label: '转文字',
                            accent: AsOneTheme.iconAccent,
                            selected: target == _AsOneVoiceReleaseTarget.toText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AsOneVoiceAmplitudeWave extends StatelessWidget {
  const _AsOneVoiceAmplitudeWave({
    required this.amplitude,
    required this.color,
  });

  final double amplitude;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List<Widget>.generate(23, (index) {
      final distance = (index - 11).abs() / 11;
      final shape = 0.35 + (1 - distance) * 0.65;
      final pulse = (8 + amplitude * 35 * shape).clamp(8.0, 43.0);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: 3,
        height: pulse,
        margin: const EdgeInsets.symmetric(horizontal: 1.2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }),
  );
}

class _AsOneVoiceReleaseChoice extends StatelessWidget {
  const _AsOneVoiceReleaseChoice({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
  });

  final AsOneIconName icon;
  final String label;
  final Color accent;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    height: 72,
    decoration: BoxDecoration(
      color: selected
          ? accent.withValues(alpha: 0.18)
          : const Color(0xFFFFFDFC).withValues(alpha: 0.94),
      border: Border.all(
        color: selected ? accent.withValues(alpha: 0.65) : Colors.transparent,
        width: 1.2,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AsOneIcon(icon, color: selected ? accent : AsOneTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: AsOneTheme.listTitleStyle.copyWith(
            color: selected ? accent : AsOneTheme.textPrimary,
          ),
        ),
      ],
    ),
  );
}
