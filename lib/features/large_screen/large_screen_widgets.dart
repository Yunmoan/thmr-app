import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/state/large_screen_settings.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_theme.dart';

/// 各小组件条带独立预留空间，避免挡住曲目信息和播放控件。
class LargeScreenWidgetStrip extends StatefulWidget {
  const LargeScreenWidgetStrip(
      {super.key,
      required this.components,
      required this.station,
      required this.atTop,
      this.singleColumn = false});
  final List<LargeScreenWidgetSettings> components;
  final StationUiState station;
  final bool atTop;
  final bool singleColumn;
  @override
  State<LargeScreenWidgetStrip> createState() => _LargeScreenWidgetStripState();
}

class _LargeScreenWidgetStripState extends State<LargeScreenWidgetStrip> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  bool _active = true;
  Iterable<LargeScreenWidgetSettings> get _items =>
      widget.components.where((w) => w.enabled && w.atTop == widget.atTop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant LargeScreenWidgetStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    if (!_active || !_items.any((w) => w.needsClock)) {
      _timer?.cancel();
      _timer = null;
    } else {
      _now = DateTime.now();
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
              width: constraints.maxWidth,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                for (var column = 0;
                    column < (widget.singleColumn ? 1 : 3);
                    column++)
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: widget.singleColumn
                            ? CrossAxisAlignment.center
                            : [
                                CrossAxisAlignment.start,
                                CrossAxisAlignment.center,
                                CrossAxisAlignment.end
                              ][column],
                        children: [
                          for (final item in _items.where(
                              (w) => widget.singleColumn || w.column == column))
                            Padding(
                                key: ValueKey(item.id),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: LargeScreenWidgetView(
                                    component: item,
                                    value: largeScreenWidgetText(item, _now,
                                        title: widget.station.status?.current
                                                ?.title ??
                                            '',
                                        artist: widget.station.status?.current
                                                ?.artist ??
                                            '',
                                        channel: widget
                                                .station.status?.station.name ??
                                            ''))),
                        ]),
                  )),
              ])),
        );
      });
}

class LargeScreenWidgetView extends StatelessWidget {
  const LargeScreenWidgetView(
      {super.key, required this.component, required this.value});
  final LargeScreenWidgetSettings component;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final color = switch (component.tone) {
      LargeScreenWidgetTone.ink => tokens.ink,
      LargeScreenWidgetTone.muted => tokens.mutedInk,
      LargeScreenWidgetTone.accent => theme.colorScheme.primary,
      LargeScreenWidgetTone.custom => Color(component.color),
    };
    final family = switch (component.font) {
      LargeScreenWidgetFont.inherit => null,
      LargeScreenWidgetFont.sans => 'Microsoft YaHei',
      LargeScreenWidgetFont.mono => 'Consolas',
    };
    Widget child = Text(value,
        textAlign: component.textAlign,
        maxLines: component.maxLines,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: family,
          fontFamilyFallback: family == null
              ? null
              : const ['Noto Sans CJK SC', 'Microsoft YaHei', 'sans-serif'],
          fontSize: component.fontSize,
          height: 1.25,
          fontWeight: component.weight == 800
              ? FontWeight.w800
              : component.weight == 600
                  ? FontWeight.w600
                  : FontWeight.w400,
          fontStyle: component.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: component.letterSpacing,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ));
    if (component.decoration != LargeScreenWidgetDecoration.none) {
      child = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: component.decoration == LargeScreenWidgetDecoration.label
              ? tokens.fieldBg
              : null,
          border: component.decoration == LargeScreenWidgetDecoration.rule
              ? Border(left: BorderSide(color: color, width: 2))
              : Border.all(color: tokens.panelBorder),
          borderRadius:
              component.decoration == LargeScreenWidgetDecoration.label
                  ? BorderRadius.circular(6)
                  : null,
        ),
        child: child,
      );
    }
    return Opacity(
        opacity: component.opacity,
        child: Semantics(
            label: '${component.label}：$value',
            excludeSemantics: true,
            child: child));
  }
}
