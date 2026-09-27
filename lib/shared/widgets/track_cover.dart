import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';

/// 曲目封面:圆角、细描边;无封面(空串 / 404)时使用官方占位图
/// (提取自 Web 端 public/assets/cover-fallback.svg 的内嵌 PNG)。
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
        child: url.isEmpty
            ? Image.asset('assets/brand/cover-fallback.png',
                fit: BoxFit.cover, cacheWidth: cacheWidth)
            : Image.network(
                url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                cacheWidth: cacheWidth,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Image.asset(
                    'assets/brand/cover-fallback.png',
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth),
              ),
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
