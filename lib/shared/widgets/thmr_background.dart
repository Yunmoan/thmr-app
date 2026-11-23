import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import '../../core/theme/thmr_motion.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final asset = illustration ?? tokens.illustration;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final motionDuration =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : ThmrMotion.duration;
    final washBehindArt = underlay != null && underlayAboveWash;
    final wash = RepaintBoundary(
      key: const ValueKey('background-wash'),
      child: AnimatedContainer(
        duration: motionDuration,
        curve: ThmrMotion.enterCurve,
        decoration: BoxDecoration(gradient: tokens.pageGradient),
      ),
    );
    return AnimatedContainer(
      duration: motionDuration,
      curve: ThmrMotion.enterCurve,
      decoration: BoxDecoration(color: tokens.pageBg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (washBehindArt) wash,
          if (underlay != null) underlay!,
          // 页面及播放器控件播放动画时，背景插画保持静止。
          Offstage(
            key: const ValueKey('background-illustration'),
            offstage: !showIllustration,
            child: RepaintBoundary(
              child: Align(
                alignment: alignment,
                child: FractionallySizedBox(
                  widthFactor: illustrationWidthFactor,
                  heightFactor: illustrationHeightFactor ?? (compact ? .8 : .9),
                  alignment: alignment,
                  child: Opacity(
                    opacity: illustrationOpacity,
                    child: ThmrAnimatedContent(
                      alignment: alignment,
                      child: Image.asset(
                        asset,
                        key: ValueKey(asset),
                        color: illustrationTint,
                        colorBlendMode: BlendMode.srcATop,
                        fit: BoxFit.contain,
                        alignment: alignment,
                        filterQuality: FilterQuality.low,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 使用半透明纸面底色，使各页仍能看见背景插画。
          if (!washBehindArt) wash,
          child,
        ],
      ),
    );
  }
}
