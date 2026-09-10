import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/asone_theme.dart';
import '../widgets/asone_icons.dart';

Rect calculateImageCropViewport(Size canvasSize, double aspectRatio) {
  assert(aspectRatio > 0);
  final availableWidth = math.max(1.0, canvasSize.width - 48);
  final availableHeight = math.max(1.0, canvasSize.height - 120);
  var width = math.min(availableWidth, availableHeight * aspectRatio);
  var height = width / aspectRatio;
  if (height > availableHeight) {
    height = availableHeight;
    width = height * aspectRatio;
  }
  return Rect.fromCenter(
    center: Offset(canvasSize.width / 2, canvasSize.height / 2),
    width: width,
    height: height,
  );
}

Size imageCropOutputSize(int outputWidth, double aspectRatio) =>
    Size(outputWidth.toDouble(), (outputWidth / aspectRatio).roundToDouble());

class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({
    super.key,
    required this.sourcePath,
    this.cropAspectRatio = 1,
    this.outputWidth = 1024,
    this.title = '调整头像',
    this.subject = '头像',
  });

  final String sourcePath;
  final double cropAspectRatio;
  final int outputWidth;
  final String title;
  final String subject;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  ui.Image? _image;
  Rect _cropRect = Rect.zero;
  double _displayScale = 1;
  double _gestureScale = 1;
  double _gestureStartScale = 1;
  Offset _imageOffset = Offset.zero;
  Offset _gestureImagePoint = Offset.zero;
  bool _positioned = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取所选照片，请重新选择');
    }
  }

  void _positionImage(Size canvasSize, Rect cropRect) {
    final image = _image;
    if (image == null || _positioned) return;
    final displayScale = [
      cropRect.width / image.width,
      cropRect.height / image.height,
    ].reduce((a, b) => a > b ? a : b);
    final displayWidth = image.width * displayScale;
    final displayHeight = image.height * displayScale;
    final imageOffset = Offset(
      (canvasSize.width - displayWidth) / 2,
      (canvasSize.height - displayHeight) / 2,
    );
    setState(() {
      _cropRect = cropRect;
      _displayScale = displayScale;
      _imageOffset = imageOffset;
      _positioned = true;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _gestureScale;
    _gestureImagePoint =
        (details.localFocalPoint - _imageOffset) / _gestureScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final image = _image;
    if (image == null || !_positioned) return;
    final nextScale = (_gestureStartScale * details.scale).clamp(1.0, 6.0);
    final nextOffset =
        details.localFocalPoint - (_gestureImagePoint * nextScale);
    final width = image.width * _displayScale * nextScale;
    final height = image.height * _displayScale * nextScale;
    final clamped = Offset(
      nextOffset.dx.clamp(_cropRect.right - width, _cropRect.left),
      nextOffset.dy.clamp(_cropRect.bottom - height, _cropRect.top),
    );
    setState(() {
      _gestureScale = nextScale;
      _imageOffset = clamped;
    });
  }

  Future<void> _confirm() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final effectiveScale = _displayScale * _gestureScale;
      final left = ((_cropRect.left - _imageOffset.dx) / effectiveScale).clamp(
        0.0,
        image.width.toDouble(),
      );
      final top = ((_cropRect.top - _imageOffset.dy) / effectiveScale).clamp(
        0.0,
        image.height.toDouble(),
      );
      final right = ((_cropRect.right - _imageOffset.dx) / effectiveScale)
          .clamp(0.0, image.width.toDouble());
      final bottom = ((_cropRect.bottom - _imageOffset.dy) / effectiveScale)
          .clamp(0.0, image.height.toDouble());
      final source = Rect.fromLTRB(left, top, right, bottom);
      if (source.width < 1 || source.height < 1) {
        throw StateError('裁剪范围无效');
      }
      final outputSize = imageCropOutputSize(
        widget.outputWidth,
        widget.cropAspectRatio,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        Offset.zero & outputSize,
        Paint()..filterQuality = FilterQuality.high,
      );
      final output = await recorder.endRecording().toImage(
        outputSize.width.toInt(),
        outputSize.height.toInt(),
      );
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List() ?? Uint8List(0);
      if (bytes.isEmpty) throw StateError('${widget.subject}生成失败');
      final cache = await getTemporaryDirectory();
      final target = File(
        '${cache.path}${Platform.pathSeparator}${widget.subject == '头像' ? 'avatar' : 'chat_background'}_crop_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await target.writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.pop(context, target.path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '${widget.subject}裁剪失败，请重新调整后再试';
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171717),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171717),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: AsOneIconButton(
          icon: AsOneIconName.back,
          tooltip: '返回',
          color: Colors.white,
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || !_positioned ? null : _confirm,
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 48),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              textStyle: AsOneTheme.buttonStyle,
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          final cropRect = _cropRectFor(canvasSize);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _positionImage(canvasSize, cropRect);
          });
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_image == null)
                const Center(child: CircularProgressIndicator())
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: _imageOffset.dx,
                        top: _imageOffset.dy,
                        child: Transform.scale(
                          alignment: Alignment.topLeft,
                          scale: _gestureScale,
                          child: Image.file(
                            File(widget.sourcePath),
                            width: _image!.width * _displayScale,
                            height: _image!.height * _displayScale,
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _AvatarCropMaskPainter(cropRect: cropRect),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: cropRect.bottom + 24,
                child: const Text(
                  '拖动照片调整位置，双指缩放',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              if (_error != null) ...[
                Positioned(
                  left: 20,
                  right: 20,
                  top: cropRect.bottom + 58,
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AsOneTheme.danger),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Rect _cropRectFor(Size canvasSize) {
    return calculateImageCropViewport(canvasSize, widget.cropAspectRatio);
  }
}

class _AvatarCropMaskPainter extends CustomPainter {
  const _AvatarCropMaskPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final crop = RRect.fromRectAndRadius(
      cropRect,
      Radius.circular(cropRect.width == cropRect.height ? 36 : 18),
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(crop)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black54);
    canvas.drawRRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _AvatarCropMaskPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect;
}
