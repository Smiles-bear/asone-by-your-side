import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders the original Figma SVG at its optical glyph size while keeping the
/// surrounding control free to provide a full-size touch target.
class AsOneLineAssetIcon extends StatelessWidget {
  const AsOneLineAssetIcon({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    this.color,
  });

  const AsOneLineAssetIcon.add({super.key})
    : assetPath = 'assets/icons/添加.svg',
      width = 24,
      height = 24,
      sourceWidth = 65.8,
      sourceHeight = 65.8,
      color = null;

  const AsOneLineAssetIcon.search({super.key})
    : assetPath = 'assets/icons/查找.svg',
      width = 23,
      height = 23,
      sourceWidth = 63.8,
      sourceHeight = 63.8,
      color = null;

  const AsOneLineAssetIcon.back({super.key})
    : assetPath = 'assets/icons/返回.svg',
      width = 11,
      height = 18,
      sourceWidth = 67.7,
      sourceHeight = 65.2,
      color = null;

  const AsOneLineAssetIcon.phone({super.key})
    : assetPath = 'assets/icons/电话.svg',
      width = 20,
      height = 21,
      sourceWidth = 58.3,
      sourceHeight = 57.5,
      color = null;

  const AsOneLineAssetIcon.more({super.key})
    : assetPath = 'assets/icons/三个点.svg',
      width = 20,
      height = 4,
      sourceWidth = 77.8,
      sourceHeight = 77.8,
      color = null;

  const AsOneLineAssetIcon.bubbleMore({super.key})
    : assetPath = 'assets/icons/三个点.svg',
      width = 16,
      height = 3,
      sourceWidth = 62.2,
      sourceHeight = 62.2,
      color = null;

  const AsOneLineAssetIcon.edit({super.key, this.color})
    : assetPath = 'assets/icons/编辑.svg',
      width = 19,
      height = 19,
      sourceWidth = 53.2,
      sourceHeight = 53.2;

  const AsOneLineAssetIcon.voice({super.key})
    : assetPath = 'assets/icons/语音转文字.svg',
      width = 24,
      height = 24,
      sourceWidth = 65.8,
      sourceHeight = 65.8,
      color = null;

  const AsOneLineAssetIcon.close({
    super.key,
    this.color,
    this.width = 19,
    this.height = 19,
  }) : assetPath = 'assets/icons/取消.svg',
       sourceWidth = 53,
       sourceHeight = 53;

  const AsOneLineAssetIcon.accentClose({super.key})
    : assetPath = 'assets/icons/粉色叉.svg',
      width = 24,
      height = 24,
      sourceWidth = 65.8,
      sourceHeight = 65.8,
      color = null;

  const AsOneLineAssetIcon.delete({super.key, this.color})
    : assetPath = 'assets/icons/垃圾桶.svg',
      width = 16,
      height = 19,
      sourceWidth = 16,
      sourceHeight = 19;

  const AsOneLineAssetIcon.comment({super.key, this.color})
    : assetPath = 'assets/icons/评论.svg',
      width = 22,
      height = 22,
      sourceWidth = 60,
      sourceHeight = 60;

  const AsOneLineAssetIcon.keyboard({super.key})
    : assetPath = 'assets/icons/键盘.svg',
      width = 36,
      height = 26,
      sourceWidth = 99,
      sourceHeight = 99,
      color = null;

  const AsOneLineAssetIcon.stop({super.key})
    : assetPath = 'assets/icons/暂停.svg',
      width = 28,
      height = 28,
      sourceWidth = 77.3,
      sourceHeight = 77.3,
      color = null;

  const AsOneLineAssetIcon.clock({super.key, this.color})
    : assetPath = 'assets/icons/时钟.svg',
      width = 22,
      height = 22,
      sourceWidth = 60.5,
      sourceHeight = 60.5;

  const AsOneLineAssetIcon.check({super.key, this.color})
    : assetPath = 'assets/icons/确认.svg',
      width = 20,
      height = 20,
      sourceWidth = 55,
      sourceHeight = 55;

  const AsOneLineAssetIcon.heart({
    super.key,
    required bool selected,
    this.color,
  }) : assetPath = selected
           ? 'assets/icons/喜欢点击态.svg'
           : 'assets/icons/喜欢未点检态.svg',
       width = 22,
       height = 22,
       sourceWidth = 60.5,
       sourceHeight = 60.5;

  final String assetPath;
  final double width;
  final double height;
  final double sourceWidth;
  final double sourceHeight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        minWidth: sourceWidth,
        maxWidth: sourceWidth,
        minHeight: sourceHeight,
        maxHeight: sourceHeight,
        alignment: Alignment.center,
        child: SvgPicture.asset(
          assetPath,
          width: sourceWidth,
          height: sourceHeight,
          fit: BoxFit.fill,
          colorFilter: color == null
              ? null
              : ColorFilter.mode(color!, BlendMode.srcIn),
        ),
      ),
    );
  }
}
