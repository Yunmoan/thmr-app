import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';

/// One shared illustration behind the navigator and every transparent page.
class ThmrBackground extends StatelessWidget {
  const ThmrBackground({
    super.key,
    required this.child,
    this.illustration,
  });

  final Widget child;

  /// Defaults to the current character theme's illustration.
  final String? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final asset = illustration ?? tokens.illustration;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final motionDuration =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : const Duration(milliseconds: 280);
    return AnimatedContainer(
      duration: motionDuration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(color: tokens.pageBg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The illustration stays still while pages and player controls animate.
          RepaintBoundary(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FractionallySizedBox(
                heightFactor: compact ? 0.8 : 0.9,
                alignment: Alignment.bottomLeft,
                child: Opacity(
                  opacity: 0.9,
                  child: AnimatedSwitcher(
                    duration: motionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Image.asset(
                      asset,
                      key: ValueKey(asset),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomLeft,
                      filterQuality: FilterQuality.low,
                      excludeFromSemantics: true,
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
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(gradient: tokens.pageGradient),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
