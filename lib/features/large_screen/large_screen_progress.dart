import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';

/// 本地暂停时电台仍在直播。以服务端报告的播放位置为基准推进进度，避免依赖服务端与本机时钟同步。
class LargeScreenProgress extends StatefulWidget {
  const LargeScreenProgress(
      {super.key, required this.current, required this.updatedAt});
  final CurrentTrack? current;
  final DateTime? updatedAt;

  @override
  State<LargeScreenProgress> createState() => _LargeScreenProgressState();
}

class _LargeScreenProgressState extends State<LargeScreenProgress>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _receivedAt = DateTime.now();
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant LargeScreenProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.updatedAt != widget.updatedAt) {
      _receivedAt = DateTime.now();
    }
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncTimer();

  void _syncTimer() {
    if (_visible &&
        ThmrMotion.viewVisible &&
        (widget.current?.durationSec ?? 0) > 0) {
      _timer ??=
          Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      return;
    }
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
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
      SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text('直播进度',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.mutedInk)),
            Text(
                duration > 0
                    ? '${clock(position)} / ${clock(duration)}'
                    : '— / —',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tokens.mutedInk,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    ]);
  }
}
