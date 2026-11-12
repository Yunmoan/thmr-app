import 'package:flutter/material.dart';

import '../../../core/theme/thmr_theme.dart';
import '../../../shared/widgets/thmr_panel.dart';

/// Mirrors the real player, controls and history/queue layout without a ticker.
class ChannelLoadingSkeleton extends StatelessWidget {
  const ChannelLoadingSkeleton({super.key, required this.switching});

  final bool switching;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).thmr.mutedInk.withValues(alpha: 0.12);
    Widget block(double height, {double? width, double radius = 4}) =>
        Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    Widget bar(double height, [double fraction = 1]) => FractionallySizedBox(
          widthFactor: fraction,
          alignment: Alignment.centerLeft,
          child: block(height),
        );

    Widget player(bool wide) => ThmrPanel(
          key: const ValueKey('skeleton-player'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(96, width: 96, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(12, .3),
                        const SizedBox(height: 14),
                        bar(wide ? 26 : 22, .9),
                        const SizedBox(height: 10),
                        bar(14, .55),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            for (var i = 0; i < 3; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(child: block(28)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              block(48),
              const SizedBox(height: 20),
              Row(
                children: [
                  block(14, width: 16),
                  const SizedBox(width: 12),
                  Expanded(child: block(5)),
                  const SizedBox(width: 12),
                  block(12, width: 28),
                ],
              ),
            ],
          ),
        );

    Widget controls() => Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: ThmrPanel(
                  key: ValueKey('skeleton-control-$i'),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(12, .35),
                      const SizedBox(height: 12),
                      bar(24, .8),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );

    Widget queueRow() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              block(46, width: 46, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(14, .9),
                    const SizedBox(height: 10),
                    bar(11, .55),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              block(11, width: 32),
            ],
          ),
        );

    Widget history() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(18, .45),
            const SizedBox(height: 10),
            ThmrPanel(
              key: const ValueKey('skeleton-history'),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(11, .22),
                  const SizedBox(height: 10),
                  queueRow(),
                  const Divider(height: 20),
                  Row(
                    children: [
                      block(11, width: 48),
                      const Spacer(),
                      block(12, width: 42),
                    ],
                  ),
                  const SizedBox(height: 10),
                  bar(10, .4),
                ],
              ),
            ),
            const SizedBox(height: 20),
            bar(18, .5),
            const SizedBox(height: 10),
            Expanded(
              child: ThmrPanel(
                key: const ValueKey('skeleton-queue'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView.separated(
                  itemCount: 6,
                  itemBuilder: (_, __) => queueRow(),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                ),
              ),
            ),
            const SizedBox(height: 8),
            block(36),
          ],
        );

    return Semantics(
      label: switching ? '正在切换频道…' : '正在加载频道…',
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 900 && constraints.hasBoundedHeight;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          player(true),
                          const SizedBox(height: 12),
                          controls(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(width: 330, child: history()),
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                player(false),
                const SizedBox(height: 12),
                controls(),
                const SizedBox(height: 20),
                bar(18, .3),
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, __) => SizedBox(
                      width: 240,
                      child: ThmrPanel(
                        frost: false,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: queueRow(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
