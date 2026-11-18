import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import '../../core/theme/thmr_motion.dart';

/// One shared illustration behind the navigator and every transparent page.
class ThmrBackground extends StatelessWidget {
  const ThmrBackground({
    super.key,
    required this.child,
    this.underlay,
    this.underlayAboveWash = false,
    this.illustration,
    this.alignment = Alignment.bottomLeft,
    this.showIllustration = true,
    this.illustrationOpacity = .9,
  });

  final Widget child;
  final Widget? underlay;

  /// Place the motion between the paper wash and the character illustration.
  final bool underlayAboveWash;

  /// Defaults to the current character theme's illustration.
  final String? illustration;
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
    // Full-bleed color can sit above the wash. Keep the illustration soft on
    // that surface with the same amount of translucency as the usual paper.
    final artOpacity = washBehindArt
        ? illustrationOpacity *
            (theme.brightness == Brightness.dark ? .34 : .42)
        : illustrationOpacity;
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
          // The illustration stays still while pages and player controls animate.
          Offstage(
            key: const ValueKey('background-illustration'),
            offstage: !showIllustration,
            child: RepaintBoundary(
              child: Align(
                alignment: alignment,
                child: FractionallySizedBox(
                  heightFactor: compact ? 0.8 : 0.9,
                  alignment: alignment,
                  child: Opacity(
                    opacity: artOpacity,
                    child: ThmrAnimatedContent(
                      alignment: alignment,
                      child: Image.asset(
                        asset,
                        key: ValueKey(asset),
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
          // Semi-transparent wash keeps the artwork visible across pages.
          if (!washBehindArt) wash,
          child,
        ],
      ),
    );
  }
}
