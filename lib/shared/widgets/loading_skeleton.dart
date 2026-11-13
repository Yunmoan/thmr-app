import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import 'thmr_panel.dart';

/// Static placeholders: no perpetual animation, including reduced motion.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.width, required this.height});
  final double? width;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).thmr.mutedInk.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

class SkeletonText extends StatelessWidget {
  const SkeletonText(
      {super.key, required this.style, this.lines = 1, this.fraction = .8});
  final TextStyle? style;
  final int lines;
  final double fraction;
  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final painter = TextPainter(
        text: TextSpan(text: '曲目', style: effective),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final height = painter.height;
    painter.dispose();
    return SizedBox(
        height: height * lines,
        child: Column(children: [
          for (var i = 0; i < lines; i++)
            SizedBox(
                height: height,
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                        widthFactor: i == 0 ? fraction : fraction * .7,
                        child: SkeletonBlock(height: height * .6)))),
        ]));
  }
}

/// Match the cover, typography, padding and separation of list rows.
class TrackListSkeleton extends StatelessWidget {
  const TrackListSkeleton(
      {super.key,
      this.padding = EdgeInsets.zero,
      this.rowPadding =
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      this.gap = 8,
      this.extraHeight = 0,
      this.titleStyle});
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry rowPadding;
  final double gap;
  final double extraHeight;
  final TextStyle? titleStyle;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '正在加载列表',
        liveRegion: true,
        child: ExcludeSemantics(
            child: ListView.separated(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 8,
          separatorBuilder: (_, __) => SizedBox(height: gap),
          itemBuilder: (context, i) => ThmrPanel(
              frost: false,
              padding: rowPadding,
              child: Row(children: [
                const SkeletonBlock(width: 46, height: 46),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      SkeletonText(
                          style: titleStyle ??
                              Theme.of(context).textTheme.titleSmall),
                      SkeletonText(
                          style: Theme.of(context).textTheme.bodySmall,
                          fraction: .55),
                      if (extraHeight > 0) SizedBox(height: extraHeight),
                    ])),
                const SizedBox(width: 12),
                const SkeletonBlock(width: 32, height: 10),
              ])),
        )),
      );
}
