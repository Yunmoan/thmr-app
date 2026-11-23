import 'package:flutter/material.dart';

import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';

/// 曲目封面，加载中、无封面或加载失败时显示 THMR 标志。
class TrackCover extends StatelessWidget {
  const TrackCover({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 8,
  });

  final String url;
  final double size;
  final double radius;

  /// 可见封面与后台预加载共用同样的缩略图解码配置。
  static ImageProvider<Object> providerFor(String url,
      {required int cacheWidth}) {
    return ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      url.isEmpty
          ? const AssetImage('assets/brand/logo.png')
          : NetworkImage(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    // 限制解码尺寸:小缩略图不必解码原图(队列列表大量使用)
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final clip = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: TrackCoverImage(url: url, cacheWidth: cacheWidth),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tokens.panelBorder),
        boxShadow: [
          BoxShadow(
              color: tokens.shadow, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: clip,
    );
  }
}

/// 不同尺寸与装饰的封面共用的加载逻辑。
class TrackCoverImage extends StatelessWidget {
  const TrackCoverImage({
    super.key,
    required this.url,
    required this.cacheWidth,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.low,
  });

  final String url;
  final int cacheWidth;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Image(
          image: TrackCover.providerFor('', cacheWidth: cacheWidth),
          fit: fit,
          filterQuality: filterQuality,
        );

    if (url.isEmpty) return placeholder();

    return Image(
      // 图片来源变化时，从占位图重新开始，避免沿用旧封面或旧封面已完成的淡入动画。
      key: ValueKey((url, cacheWidth)),
      image: TrackCover.providerFor(url, cacheWidth: cacheWidth),
      fit: fit,
      filterQuality: filterQuality,
      frameBuilder: (context, child, frame, synchronous) {
        final ready = synchronous || frame != null;
        return AnimatedSwitcher(
          duration: ThmrMotion.of(context),
          switchInCurve: ThmrMotion.enterCurve,
          switchOutCurve: ThmrMotion.exitCurve,
          child: SizedBox.expand(
            key: ValueKey(ready),
            child: ready ? child : placeholder(),
          ),
        );
      },
      errorBuilder: (_, __, ___) => placeholder(),
    );
  }
}
