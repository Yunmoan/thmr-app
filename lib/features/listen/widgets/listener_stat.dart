import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/listener_provider.dart';
import '../../../core/theme/thmr_theme.dart';

class ListenerStat extends ConsumerStatefulWidget {
  const ListenerStat({
    super.key,
    required this.listeners,
    this.compact = false,
  });

  final int? listeners;
  final bool compact;

  @override
  ConsumerState<ListenerStat> createState() => _ListenerStatState();
}

class _ListenerStatState extends ConsumerState<ListenerStat> {
  late final Timer _timer;
  bool _showSite = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 4200), (_) {
      if (!_visible ||
          widget.listeners == null ||
          ref.read(siteListenersProvider) == null) {
        return;
      }
      setState(() => _showSite = !_showSite);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
  }

  @override
  void didUpdateWidget(covariant ListenerStat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listeners == null) _showSite = false;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteListenersProvider);
    ref.listen(siteListenersProvider, (_, total) {
      if (total == null && _showSite) setState(() => _showSite = false);
    });

    final showSite = _showSite && site != null && widget.listeners != null;
    final theme = Theme.of(context);
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: theme.thmr.mutedInk);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 520);
    final channelCount = '${widget.listeners ?? '—'}';
    final siteCount = '${site ?? '—'}';

    Widget line(String channel, String wholeSite, TextStyle? style) {
      return _ListenerLine(
        channel: channel,
        site: wholeSite,
        style: style,
        showSite: showSite,
        duration: duration,
      );
    }

    return Semantics(
      excludeSemantics: true,
      label: showSite
          ? '全站实时在线听众，$siteCount 个客户端'
          : '本频道实时在线听众，$channelCount 个客户端',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.compact ? 140 : 200),
        child: widget.compact
            ? line('本频道 $channelCount 人在听', '全站 $siteCount 人在听', labelStyle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  line('本频道实时在线听众', '全站实时在线听众', labelStyle),
                  const SizedBox(height: 4),
                  line(
                    channelCount,
                    siteCount,
                    theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  line('客户端', '客户端', labelStyle),
                ],
              ),
      ),
    );
  }
}

/// Both values share the same width and a single clipped text line.
class _ListenerLine extends StatelessWidget {
  const _ListenerLine({
    required this.channel,
    required this.site,
    required this.style,
    required this.showSite,
    required this.duration,
  });

  final String channel;
  final String site;
  final TextStyle? style;
  final bool showSite;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    const curve = Cubic(0.22, 0.8, 0.22, 1);
    return ClipRect(
      child: Stack(
        alignment: AlignmentDirectional.centerEnd,
        children: [
          AnimatedSlide(
            offset: showSite ? const Offset(0, -1) : Offset.zero,
            duration: duration,
            curve: curve,
            child: Text(
              channel,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AnimatedSlide(
            offset: showSite ? Offset.zero : const Offset(0, 1),
            duration: duration,
            curve: curve,
            child: Text(
              site,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
