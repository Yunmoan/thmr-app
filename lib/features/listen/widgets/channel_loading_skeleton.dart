import 'package:flutter/material.dart';

import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/player_panel_layout.dart';
import '../../../shared/widgets/thmr_panel.dart';

/// Uses the same player geometry and breakpoint as the loaded channel.
class ChannelLoadingSkeleton extends StatelessWidget {
  const ChannelLoadingSkeleton(
      {super.key, required this.switching, this.wide, this.showVote = false});
  final bool switching;
  final bool? wide;
  final bool showVote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget masked(Widget child) => ColorFiltered(
        colorFilter:
            ColorFilter.mode(Theme.of(context).disabledColor, BlendMode.srcIn),
        child: child);
    Widget quality() => masked(Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text('音质', style: text.labelMedium)),
              for (final rate in ['320k', '128k', '96k'])
                ChoiceChip(label: Text(rate), selected: rate == '320k'),
              const IconButton(
                  onPressed: null,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.link_rounded, size: 18)),
            ]));
    Widget action(String label) => masked(Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white)),
        child: Text(label,
            style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.w600, color: Colors.transparent))));
    Widget player(bool wide) => PlayerPanelLayout(
          key: const ValueKey('skeleton-player'),
          header: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SkeletonBlock(width: 96, height: 96),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  SkeletonText(style: text.labelSmall, fraction: .35),
                  const SizedBox(height: 4),
                  SkeletonText(
                      style: text.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                      lines: 2),
                  const SizedBox(height: 6),
                  SkeletonText(style: text.bodySmall, fraction: .55),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [action('收藏'), action('反馈'), action('复制信息')]),
                ])),
          ]),
          playback: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration:
                  BoxDecoration(border: Border.all(color: Colors.transparent)),
              child: Row(children: [
                SizedBox(
                    width: 52,
                    child: masked(Text('00:00',
                        style: text.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700)))),
                const SizedBox(width: 12),
                const Expanded(child: SkeletonBlock(height: 36)),
                const SizedBox(width: 12),
                masked(Text('播放', style: text.labelLarge)),
              ])),
          volume: wide
              ? masked(Row(children: [
                  const IconButton(
                      onPressed: null,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.volume_up_rounded, size: 18)),
                  const Expanded(
                      child: SizedBox(
                          height: 34,
                          child: Center(child: SkeletonBlock(height: 5)))),
                  Text('70%', style: text.labelSmall),
                ]))
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(children: [
                    const SkeletonBlock(width: 18, height: 18),
                    const SizedBox(width: 6),
                    masked(Text('音量 70%', style: text.labelSmall))
                  ])),
          quality: wide ? null : quality(),
        );
    Widget vote() => ThmrPanel(
        key: const ValueKey('skeleton-vote'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SizedBox(
            height: 48,
            child: Row(children: [
              const SkeletonBlock(width: 21, height: 21),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    SkeletonText(style: text.labelLarge),
                    SkeletonText(style: text.labelSmall),
                  ])),
            ])));
    Widget queueRow({bool compact = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 0 : 10),
        child: Row(children: [
          const SkeletonBlock(width: 40, height: 40),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                SkeletonText(style: text.titleSmall),
                SkeletonText(style: text.labelSmall, fraction: .55),
              ])),
        ]));
    Widget history() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: '过去与未来'),
          ThmrPanel(
              key: const ValueKey('skeleton-history'),
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(style: text.labelSmall, fraction: .25),
                    const SizedBox(height: 8),
                    SizedBox(height: 40, child: queueRow(compact: true)),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 10),
                    SkeletonText(style: text.titleSmall),
                    const SizedBox(height: 6),
                    SkeletonText(style: text.labelSmall, fraction: .4),
                  ])),
          const SizedBox(height: 16),
          const SectionHeader(title: '接下来'),
          Expanded(
              child: ThmrPanel(
                  key: const ValueKey('skeleton-queue'),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListView.builder(
                      itemCount: 6, itemBuilder: (_, __) => queueRow()))),
          const SizedBox(height: 8),
          const SkeletonBlock(height: 36),
        ]);
    return Semantics(
        label: switching ? '正在切换频道…' : '正在加载频道…',
        liveRegion: true,
        child: ExcludeSemantics(
            child: ExcludeFocus(child: IgnorePointer(child: LayoutBuilder(
          builder: (context, constraints) {
            final useWide = wide ??
                (constraints.maxWidth >= 900 && constraints.hasBoundedHeight);
            if (useWide) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: SingleChildScrollView(
                            child: Column(children: [
                      player(true),
                      const SizedBox(height: 12),
                      IntrinsicHeight(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Expanded(
                                child: ThmrPanel(
                                    key: const ValueKey('skeleton-control-0'),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    child: quality())),
                            if (showVote) ...[
                              const SizedBox(width: 8),
                              Expanded(child: vote())
                            ],
                          ])),
                    ]))),
                    const SizedBox(width: 16),
                    SizedBox(width: 330, child: history()),
                  ]);
            }
            final body =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              player(false),
              if (showVote) ...[const SizedBox(height: 12), vote()],
              const SizedBox(height: 18),
              const SectionHeader(title: '接下来'),
              SizedBox(
                  height: 92,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 3,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, __) => SizedBox(
                          width: 264,
                          child: ThmrPanel(
                              frost: false,
                              padding: const EdgeInsets.all(10),
                              child: Row(children: [
                                const SkeletonBlock(width: 72, height: 72),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: SkeletonText(
                                        style: text.titleSmall, lines: 2)),
                              ]))))),
              const SizedBox(height: 2),
              masked(TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.unfold_more_rounded, size: 16),
                  label: const Text('查看全部'))),
              const SizedBox(height: 24),
            ]);
            return constraints.hasBoundedHeight
                ? SingleChildScrollView(child: body)
                : body;
          },
        )))));
  }
}
