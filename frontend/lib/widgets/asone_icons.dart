import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../theme/asone_theme.dart';

/// Semantic icon names used by shared AsOne UI.
///
/// Keeping business code on this enum lets the visual icon family evolve
/// without replacing icon constants throughout the app again.
enum AsOneIconName {
  phone,
  phoneOff,
  back,
  forward,
  close,
  more,
  add,
  search,
  settings,
  sliders,
  camera,
  image,
  folder,
  microphone,
  microphoneOff,
  speaker,
  keyboard,
  send,
  link,
  attachment,
  copy,
  edit,
  delete,
  pin,
  star,
  heart,
  bookmark,
  share,
  calendar,
  clock,
  notification,
  message,
  user,
  users,
  play,
  pause,
  stop,
  refresh,
  success,
  warning,
  data,
  developer,
  voice,
  cloud,
  upload,
  download,
  restore,
  bug,
  info,
  eye,
  eyeOff,
  check,
  test,
  terminal,
  document,
  key,
  robot,
  swap,
  arrowUp,
  arrowDown,
}

IconData asOneIconData(AsOneIconName name) => switch (name) {
  AsOneIconName.phone => PhosphorIconsRegular.phone,
  AsOneIconName.phoneOff => PhosphorIconsRegular.phoneDisconnect,
  AsOneIconName.back => PhosphorIconsRegular.caretLeft,
  AsOneIconName.forward => PhosphorIconsRegular.caretRight,
  AsOneIconName.close => PhosphorIconsRegular.x,
  AsOneIconName.more => PhosphorIconsRegular.dotsThree,
  AsOneIconName.add => PhosphorIconsRegular.plusCircle,
  AsOneIconName.search => PhosphorIconsRegular.magnifyingGlass,
  AsOneIconName.settings => PhosphorIconsRegular.gear,
  AsOneIconName.sliders => PhosphorIconsRegular.slidersHorizontal,
  AsOneIconName.camera => PhosphorIconsRegular.camera,
  AsOneIconName.image => PhosphorIconsRegular.image,
  AsOneIconName.folder => PhosphorIconsRegular.folder,
  AsOneIconName.microphone => PhosphorIconsRegular.microphone,
  AsOneIconName.microphoneOff => PhosphorIconsRegular.microphoneSlash,
  AsOneIconName.speaker => PhosphorIconsRegular.speakerHigh,
  AsOneIconName.keyboard => PhosphorIconsRegular.keyboard,
  AsOneIconName.send => PhosphorIconsRegular.paperPlaneTilt,
  AsOneIconName.link => PhosphorIconsRegular.link,
  AsOneIconName.attachment => PhosphorIconsRegular.paperclip,
  AsOneIconName.copy => PhosphorIconsRegular.copy,
  AsOneIconName.edit => PhosphorIconsRegular.pencilSimple,
  AsOneIconName.delete => PhosphorIconsRegular.trash,
  AsOneIconName.pin => PhosphorIconsRegular.pushPin,
  AsOneIconName.star => PhosphorIconsRegular.star,
  AsOneIconName.heart => PhosphorIconsRegular.heart,
  AsOneIconName.bookmark => PhosphorIconsRegular.bookmarkSimple,
  AsOneIconName.share => PhosphorIconsRegular.shareNetwork,
  AsOneIconName.calendar => PhosphorIconsRegular.calendar,
  AsOneIconName.clock => PhosphorIconsRegular.clock,
  AsOneIconName.notification => PhosphorIconsRegular.bell,
  AsOneIconName.message => PhosphorIconsRegular.chatCircle,
  AsOneIconName.user => PhosphorIconsRegular.user,
  AsOneIconName.users => PhosphorIconsRegular.users,
  AsOneIconName.play => PhosphorIconsRegular.play,
  AsOneIconName.pause => PhosphorIconsRegular.pause,
  AsOneIconName.stop => PhosphorIconsRegular.stop,
  AsOneIconName.refresh => PhosphorIconsRegular.arrowClockwise,
  AsOneIconName.success => PhosphorIconsRegular.checkCircle,
  AsOneIconName.warning => PhosphorIconsRegular.warningCircle,
  AsOneIconName.data => PhosphorIconsRegular.database,
  AsOneIconName.developer => PhosphorIconsRegular.code,
  AsOneIconName.voice => PhosphorIconsRegular.waveform,
  AsOneIconName.cloud => PhosphorIconsRegular.cloud,
  AsOneIconName.upload => PhosphorIconsRegular.uploadSimple,
  AsOneIconName.download => PhosphorIconsRegular.downloadSimple,
  AsOneIconName.restore => PhosphorIconsRegular.arrowCounterClockwise,
  AsOneIconName.bug => PhosphorIconsRegular.bug,
  AsOneIconName.info => PhosphorIconsRegular.info,
  AsOneIconName.eye => PhosphorIconsRegular.eye,
  AsOneIconName.eyeOff => PhosphorIconsRegular.eyeSlash,
  AsOneIconName.check => PhosphorIconsRegular.check,
  AsOneIconName.test => PhosphorIconsRegular.flask,
  AsOneIconName.terminal => PhosphorIconsRegular.terminalWindow,
  AsOneIconName.document => PhosphorIconsRegular.fileText,
  AsOneIconName.key => PhosphorIconsRegular.key,
  AsOneIconName.robot => PhosphorIconsRegular.robot,
  AsOneIconName.swap => PhosphorIconsRegular.arrowsLeftRight,
  AsOneIconName.arrowUp => PhosphorIconsRegular.arrowUp,
  AsOneIconName.arrowDown => PhosphorIconsRegular.arrowDown,
};

class AsOneIcon extends StatelessWidget {
  const AsOneIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.color,
    this.semanticLabel,
  });

  final AsOneIconName name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Icon(
      asOneIconData(name),
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
  }
}

class AsOneIconButton extends StatelessWidget {
  const AsOneIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.iconSize = 22,
  });

  final AsOneIconName icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      splashRadius: 22,
      icon: AsOneIcon(
        icon,
        size: iconSize,
        color: color ?? AsOneTheme.iconDefault,
      ),
    );
  }
}
