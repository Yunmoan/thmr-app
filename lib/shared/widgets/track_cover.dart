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
class TrackCoverImage extends StatefulWidget {
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
  State<TrackCoverImage> createState() => _TrackCoverImageState();
}

class _TrackCoverImageState extends State<TrackCoverImage> {
  bool _hasCoverFrame = false;

  @override
  void didUpdateWidget(covariant TrackCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _hasCoverFrame = false;
  }

  @override
  Widget build(BuildContext context) {
    final TrackCoverImage(:url, :cacheWidth, :fit, :filterQuality) = widget;
    Widget placeholder() => Image(
          image: TrackCover.providerFor('', cacheWidth: cacheWidth),
          fit: fit,
          filterQuality: filterQuality,
        );

    if (url.isEmpty) return placeholder();

    return Image(
      // 仅切换封面来源时重建图片。同一封面重新解码期间继续显示已有帧。
      key: ValueKey(url),
      image: TrackCover.providerFor(url, cacheWidth: cacheWidth),
      fit: fit,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        // 解码尺寸改变时帧号会重置，已有封面无需重新从占位图淡入。
        _hasCoverFrame |= synchronous || frame != null;
        return AnimatedSwitcher(
          duration: ThmrMotion.of(context),
          switchInCurve: ThmrMotion.enterCurve,
          switchOutCurve: ThmrMotion.exitCurve,
          child: SizedBox.expand(
            key: ValueKey(_hasCoverFrame),
            child: _hasCoverFrame ? child : placeholder(),
          ),
        );
      },
      errorBuilder: (_, __, ___) => placeholder(),
    );
  }
}
