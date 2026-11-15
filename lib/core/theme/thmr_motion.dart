import 'package:flutter/material.dart';

class ThmrMotion {
  const ThmrMotion._();
  static const duration = Duration(milliseconds: 240);
  static const exitDuration = Duration(milliseconds: 180);
  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;
  static const distance = 8.0;

  static Duration of(BuildContext context, {bool exiting = false}) =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : exiting
              ? exitDuration
              : duration;
}

/// Shared small fade/rise, measured in pixels rather than a page-height ratio.
class ThmrFadeSlide extends StatelessWidget {
  const ThmrFadeSlide(
      {super.key, required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final curve = animation.status == AnimationStatus.reverse
              ? ThmrMotion.exitCurve
              : ThmrMotion.enterCurve;
          final progress = curve.transform(animation.value);
          return FadeTransition(
              opacity: AlwaysStoppedAnimation(progress),
              child: Transform.translate(
                  offset: Offset(0, ThmrMotion.distance * (1 - progress)),
                  child: child));
        });
  }
}

/// Outgoing content never competes for focus, pointer input or announcements.
class ThmrAnimatedContent extends StatelessWidget {
  const ThmrAnimatedContent({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: ThmrMotion.of(context),
        reverseDuration: ThmrMotion.of(context, exiting: true),
        switchInCurve: ThmrMotion.enterCurve,
        switchOutCurve: ThmrMotion.exitCurve,
        layoutBuilder: (current, previous) =>
            Stack(alignment: Alignment.topLeft, children: [
          for (final old in previous)
            Positioned.fill(
                child: ExcludeFocus(
                    child: ExcludeSemantics(
                        child: IgnorePointer(
                            child: TickerMode(enabled: false, child: old))))),
          if (current != null) current,
        ]),
        child: child,
      );
}

class ThmrPageTransitionsBuilder extends PageTransitionsBuilder {
  const ThmrPageTransitionsBuilder();
  @override
  Duration get transitionDuration => ThmrMotion.duration;
  @override
  Duration get reverseTransitionDuration => ThmrMotion.exitDuration;
  @override
  Widget buildTransitions<T>(
          PageRoute<T> route,
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child) =>
      ThmrFadeSlide(animation: animation, child: child);
}
