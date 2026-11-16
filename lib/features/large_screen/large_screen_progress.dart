import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/thmr_theme.dart';

/// Broadcast time continues when local playback is paused. Anchor the clock to
/// the reported position instead of assuming the server and PC clocks agree.
class LargeScreenProgress extends StatefulWidget {
  const LargeScreenProgress(
      {super.key, required this.current, required this.updatedAt});
  final CurrentTrack? current;
  final DateTime? updatedAt;

  @override
  State<LargeScreenProgress> createState() => _LargeScreenProgressState();
}

class _LargeScreenProgressState extends State<LargeScreenProgress> {
  late final Timer _timer;
  DateTime _receivedAt = DateTime.now();
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_visible && widget.current != null) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
  }

  @override
  void didUpdateWidget(covariant LargeScreenProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.updatedAt != widget.updatedAt) {
      _receivedAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final duration = math.max(0, widget.current?.durationSec ?? 0);
    final elapsed =
        DateTime.now().difference(widget.updatedAt ?? _receivedAt).inSeconds;
    final position = ((widget.current?.positionSec ?? 0) + math.max(0, elapsed))
        .clamp(0, duration)
        .toInt();
    String clock(int value) =>
        '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      LinearProgressIndicator(
        value: duration > 0 ? position / duration : 0,
        minHeight: 3,
        backgroundColor: tokens.panelBorder,
        semanticsLabel: duration > 0
            ? '直播进度，${clock(position)} / ${clock(duration)}'
            : '直播进度，等待放送',
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text('直播进度',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.mutedInk)),
        const Spacer(),
        Text(duration > 0 ? '${clock(position)} / ${clock(duration)}' : '— / —',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.mutedInk,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    ]);
  }
}
