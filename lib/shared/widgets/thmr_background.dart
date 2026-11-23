import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import '../../core/theme/thmr_motion.dart';
import 'thmr_wallpaper.dart';

/// Navigator 和各透明页面共用的背景插画。
class ThmrBackground extends StatelessWidget {
  const ThmrBackground({
    super.key,
    required this.child,
    this.underlay,
    this.underlayAboveWash = false,
    this.illustration,
    this.illustrationTint,
    this.illustrationWidthFactor,
    this.illustrationHeightFactor,
    this.alignment = Alignment.bottomLeft,
    this.showIllustration = true,
    this.illustrationOpacity = .9,
    this.visible = true,
  });

  final Widget child;
  final Widget? underlay;

  /// 将动态效果绘制在纸面底色与角色插画之间。
  final bool underlayAboveWash;

  /// 默认使用当前角色主题的插画。
  final String? illustration;
  final Color? illustrationTint;
  final double? illustrationWidthFactor;
  final double? illustrationHeightFactor;
  final Alignment alignment;
  final bool showIllustration;
  final double illustrationOpacity;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final asset = illustration ?? tokens.illustration;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final artHeight = illustrationHeightFactor ?? (compact ? .8 : .9);
    final washBehindArt = underlay != null && underlayAboveWash;
    // MaterialApp 已经插值主题色，纸面颜色和渐变直接使用当前帧的主题值。
    final wash = DecoratedBox(
      key: const ValueKey('background-wash'),
      decoration: BoxDecoration(gradient: tokens.pageGradient),
    );
    return ThmrWallpaper(
      visible: visible,
      textureKey: underlay == null
          ? (
              tokens.pageBg,
              tokens.pageGradient,
              asset,
              showIllustration,
              illustrationTint,
              illustrationOpacity,
              illustrationWidthFactor,
              artHeight,
              alignment,
            )
          : null,
      background: ColoredBox(
        color: tokens.pageBg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (washBehindArt) wash,
            if (underlay != null) underlay!,
            Offstage(
              key: const ValueKey('background-illustration'),
              offstage: !showIllustration,
              child: Align(
                alignment: alignment,
                child: FractionallySizedBox(
                  widthFactor: illustrationWidthFactor,
                  heightFactor: artHeight,
                  alignment: alignment,
                  child: ThmrAnimatedContent(
                    alignment: alignment,
                    child: Image.asset(
                      asset,
                      key: ValueKey(asset),
                      color: illustrationTint,
                      colorBlendMode: BlendMode.srcATop,
                      opacity: AlwaysStoppedAnimation(illustrationOpacity),
                      fit: BoxFit.contain,
                      alignment: alignment,
                      filterQuality: FilterQuality.low,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
            // 使用半透明纸面底色，使各页仍能看见背景插画。
            if (!washBehindArt) wash,
          ],
        ),
      ),
      child: child,
    );
  }
}
