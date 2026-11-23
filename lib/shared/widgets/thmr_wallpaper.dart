import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/thmr_motion.dart';

const thmrFrostSigma = 8.0;

/// 普通页面共用同一张模糊壁纸，卡片只绘制对应位置的裁剪区域。
class ThmrWallpaper extends StatefulWidget {
  const ThmrWallpaper({
    super.key,
    required this.background,
    required this.child,
    required this.textureKey,
    this.visible = true,
  });

  final Widget background;
  final Widget child;
  final bool visible;

  /// 动态背景传入 null，使用卡片内的实时滤镜。
  final Object? textureKey;

  static Widget? frostOf(BuildContext context) {
    final wallpaper =
        context.dependOnInheritedWidgetOfExactType<_FrostedWallpaper>();
    if (wallpaper == null) return null;
    final image = wallpaper.image;
    if (image == null) {
      wallpaper.requestTexture();
      return null;
    }
    final background = wallpaper.boundaryKey.currentContext?.findRenderObject();
    if (background is! RenderBox) return null;
    final size = wallpaper.size;
    return IgnorePointer(
      child: _WallpaperSample(
        background: background,
        textureSize: size,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: RawImage(image: image, fit: BoxFit.fill),
        ),
      ),
    );
  }

  @override
  State<ThmrWallpaper> createState() => _ThmrWallpaperState();
}

class _ThmrWallpaperState extends State<ThmrWallpaper>
    with WidgetsBindingObserver {
  final _boundaryKey = GlobalKey();
  final _textures = <(Object, Size), ui.Image>{};
  Timer? _settle;
  var _revision = 0;
  var _capturing = false;
  var _textureRequested = false;

  bool get _canCapture =>
      _textureRequested &&
      widget.visible &&
      widget.textureKey != null &&
      ThmrMotion.viewVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ThmrWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textureKey != oldWidget.textureKey ||
        widget.visible != oldWidget.visible) {
      _scheduleCapture();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _scheduleCapture();

  void _requestTexture() {
    if (_textureRequested) return;
    _textureRequested = true;
    _scheduleCapture();
  }

  void _scheduleCapture() {
    _revision++;
    _settle?.cancel();
    if (!_capturing && _canCapture) {
      // 窗口拖动、主题淡入或插画解码期间合并请求。
      _settle = Timer(const Duration(milliseconds: 120), _capture);
    }
  }

  Future<void> _capture() async {
    final key = widget.textureKey;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (!_canCapture ||
        key == null ||
        boundary is! RenderRepaintBoundary ||
        !boundary.hasSize ||
        boundary.size.isEmpty) {
      return;
    }
    final size = boundary.size;
    final revision = _revision;
    _capturing = true;
    ui.Image? source;
    ui.Picture? picture;
    try {
      final ratio = math.min(.5, 1024 / size.longestSide);
      source = await boundary.toImage(pixelRatio: ratio);
      if (!mounted || revision != _revision) return;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final sigma = thmrFrostSigma * ratio;
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
      );
      canvas.drawImage(source, Offset.zero, Paint());
      canvas.restore();
      picture = recorder.endRecording();
      final image = await picture.toImage(source.width, source.height);
      if (!mounted || revision != _revision) {
        image.dispose();
        return;
      }
      setState(() {
        final id = (key, size);
        _textures.remove(id)?.dispose();
        _textures[id] = image;
        // 保留最近两种尺寸，反复还原和最大化时可以直接使用已有底图。
        if (_textures.length > 2) {
          _textures.remove(_textures.keys.first)?.dispose();
        }
      });
    } catch (_) {
      // 光栅表面切换期间可能无法读取壁纸，此时卡片继续使用实时滤镜。
    } finally {
      picture?.dispose();
      source?.dispose();
      _capturing = false;
      if (mounted && revision != _revision) _scheduleCapture();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settle?.cancel();
    for (final image in _textures.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return _FrostedWallpaper(
        image: widget.visible ? _textures[(widget.textureKey, size)] : null,
        size: size,
        boundaryKey: _boundaryKey,
        requestTexture: _requestTexture,
        child: Stack(fit: StackFit.expand, children: [
          Offstage(
            offstage: !widget.visible,
            child: _WallpaperBoundary(
              key: _boundaryKey,
              onPaint: _scheduleCapture,
              child: widget.background,
            ),
          ),
          widget.child,
        ]),
      );
    });
  }
}

class _FrostedWallpaper extends InheritedWidget {
  const _FrostedWallpaper({
    required this.image,
    required this.size,
    required this.boundaryKey,
    required this.requestTexture,
    required super.child,
  });

  final ui.Image? image;
  final Size size;
  final GlobalKey boundaryKey;
  final VoidCallback requestTexture;

  @override
  bool updateShouldNotify(_FrostedWallpaper oldWidget) =>
      oldWidget.image != image;
}

class _WallpaperSample extends SingleChildRenderObjectWidget {
  const _WallpaperSample({
    required this.background,
    required this.textureSize,
    required super.child,
  });

  final RenderBox background;
  final Size textureSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWallpaperSample(background, textureSize);

  @override
  void updateRenderObject(
      BuildContext context, _RenderWallpaperSample renderObject) {
    if (renderObject.background == background &&
        renderObject.textureSize == textureSize) {
      return;
    }
    renderObject
      ..background = background
      ..textureSize = textureSize
      ..markNeedsPaint();
  }
}

class _RenderWallpaperSample extends RenderProxyBox {
  _RenderWallpaperSample(this.background, this.textureSize);

  RenderBox background;
  Size textureSize;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final samplingLayer =
        layer as _WallpaperSampleLayer? ?? _WallpaperSampleLayer();
    samplingLayer
      ..background = background
      ..sample = this
      ..offset = offset;
    layer = samplingLayer;
    context.pushLayer(samplingLayer, super.paint, Offset.zero,
        childPaintBounds: Offset.zero & textureSize);
  }
}

class _WallpaperSampleLayer extends ContainerLayer {
  late RenderBox background;
  late RenderBox sample;
  late Offset offset;

  // 路由可把前景单独光栅化为快照，用渲染对象的坐标计算取样，避免跨图层树链接。
  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (!background.attached ||
        !sample.attached ||
        background.owner != sample.owner) {
      return;
    }
    final transform = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(background.getTransformTo(sample));
    engineLayer = builder.pushTransform(transform.storage,
        oldLayer: engineLayer as ui.TransformEngineLayer?);
    addChildrenToScene(builder);
    builder.pop();
  }
}

class _WallpaperBoundary extends SingleChildRenderObjectWidget {
  const _WallpaperBoundary(
      {super.key, required this.onPaint, required super.child});

  final VoidCallback onPaint;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderWallpaperBoundary(onPaint);

  @override
  void updateRenderObject(
      BuildContext context, _RenderWallpaperBoundary renderObject) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderWallpaperBoundary extends RenderRepaintBoundary {
  _RenderWallpaperBoundary(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
