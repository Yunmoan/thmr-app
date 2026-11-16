import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import '../../core/theme/thmr_motion.dart';

/// One shared illustration behind the navigator and every transparent page.
class ThmrBackground extends StatelessWidget {
  const ThmrBackground({
    super.key,
    required this.child,
    this.illustration,
    this.alignment = Alignment.bottomLeft,
    this.showIllustration = true,
  });

  final Widget child;

  /// Defaults to the current character theme's illustration.
  final String? illustration;
  final Alignment alignment;
  final bool showIllustration;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final asset = illustration ?? tokens.illustration;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final motionDuration =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : ThmrMotion.duration;
    return AnimatedContainer(
      duration: motionDuration,
      curve: ThmrMotion.enterCurve,
      decoration: BoxDecoration(color: tokens.pageBg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The illustration stays still while pages and player controls animate.
          Offstage(
            offstage: !showIllustration,
            child: RepaintBoundary(
              child: Align(
                alignment: alignment,
                child: FractionallySizedBox(
                  heightFactor: compact ? 0.8 : 0.9,
                  alignment: alignment,
                  child: Opacity(
                    opacity: 0.9,
                    child: AnimatedSwitcher(
                      duration: motionDuration,
                      switchInCurve: ThmrMotion.enterCurve,
                      switchOutCurve: ThmrMotion.exitCurve,
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
          RepaintBoundary(
            child: AnimatedContainer(
              duration: motionDuration,
              curve: ThmrMotion.enterCurve,
              decoration: BoxDecoration(gradient: tokens.pageGradient),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
