import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/desktop_window.dart';
import '../../core/player/playback_controller.dart';
import '../../core/models/models.dart';
import '../../core/state/large_screen_settings.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../core/theme/thmr_motion.dart';
import '../../shared/widgets/status_notice.dart';
import '../../shared/widgets/thmr_background.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/volume_slider.dart';
import 'large_screen_content.dart';
import 'large_screen_controller.dart';
import 'large_screen_symbols.dart';
import '../listen/widgets/channel_switcher.dart';

final _stageThemeProvider = Provider.family<ThemeData, ThemeMode>((ref, mode) {
  final accent = ref.watch(settingsProvider.select((s) => s.accentTheme));
  return mode == ThemeMode.light
      ? ThmrTheme.light(accent)
      : ThmrTheme.dark(accent);
});

/// The existing THMR paper, character illustration and typography, presented
/// without navigation. The shared player and station remain mounted throughout.
class LargeScreenPlayer extends ConsumerStatefulWidget {
  const LargeScreenPlayer(
      {super.key, this.safeInsets = EdgeInsets.zero, this.preview = false});
  final EdgeInsets safeInsets;
  final bool preview;

  @override
  ConsumerState<LargeScreenPlayer> createState() => _LargeScreenPlayerState();
}

class _LargeScreenPlayerState extends ConsumerState<LargeScreenPlayer>
    with SingleTickerProviderStateMixin {
  Timer? _hideTimer;
  bool _controlsVisible = true;
  final _controlsFocus = FocusNode(debugLabel: '大屏播放控制');
  late final LargeScreenController _mode;
  late final AnimationController _presentation;
  bool _presentationVisible = true;
  StationUiState? _lastLoaded;

  @override
  void initState() {
    super.initState();
    _mode = ref.read(largeScreenProvider.notifier);
    _presentationVisible =
        widget.preview || ref.read(largeScreenProvider).contentVisible;
    _presentation = AnimationController(
        vsync: this,
        duration: ThmrMotion.duration,
        value: _presentationVisible ? 1 : 0);
    if (!widget.preview) {
      _mode.animatePresentation = _animatePresentation;
      largeScreenRevealRequests.addListener(_reveal);
    }
    _reveal();
  }

  Future<void> _animatePresentation(bool visible) async {
    _presentationVisible = visible;
    if (visible) _reveal();
    final duration = ThmrMotion.of(context, exiting: !visible);
    _presentation.duration = duration;
    if (duration == Duration.zero || !TickerMode.valuesOf(context).enabled) {
      _presentation.value = visible ? 1 : 0;
      return;
    }
    try {
      await (visible ? _presentation.forward() : _presentation.reverse())
          .orCancel
          .timeout(duration + const Duration(milliseconds: 200), onTimeout: () {
        // A muted ticker (the stage can be entered under an opaque route)
        // never ticks. Land on the target instead of keeping `busy` set with
        // the content stranded at opacity zero.
        _presentation.stop();
        _presentation.value = visible ? 1 : 0;
      });
    } on TickerCanceled {
      // Removing the surface also completes its native mode transition.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _presentation.value = _presentationVisible ? 1 : 0;
    }
  }

  void _reveal() {
    if (widget.preview) return;
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (!ref.read(largeScreenSettingsProvider).autoHideControls) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (_controlsFocus.hasFocus &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional) {
        _reveal();
      } else if (mounted) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (!widget.preview) largeScreenRevealRequests.removeListener(_reveal);
    if (!widget.preview && _mode.animatePresentation == _animatePresentation) {
      _mode.animatePresentation = null;
    }
    _presentation.dispose();
    _controlsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.preview) {
      ref.listen(largeScreenProvider, (_, state) {
        if (!state.busy && state.active && state.contentVisible) {
          // Native fullscreen changes can replace or cancel an animation's
          // ticker. A completed transition must always have painted content.
          _presentationVisible = true;
          _presentation.value = 1;
        }
      });
      // Fallback for a missed controller callback (for example when the stage
      // remounts during a transition): follow the shared visibility state so
      // the content can never stay transparent while the stage is visible.
      ref.listen(largeScreenProvider.select((state) => state.contentVisible),
          (previous, visible) {
        if (visible != _presentationVisible &&
            _mode.animatePresentation != _animatePresentation) {
          unawaited(_animatePresentation(visible));
        }
      });
    }
    final settings = ref.watch(largeScreenSettingsProvider);
    ref.listen(largeScreenSettingsProvider, (_, __) => _reveal());
    final theme = settings.themeMode == ThemeMode.system
        ? Theme.of(context)
        : ref.watch(_stageThemeProvider(settings.themeMode));
    return Theme(
        data: theme,
        child: Builder(builder: (context) {
          final currentStation = ref.watch(stationProvider);
          final switching = currentStation.status == null &&
              currentStation.initialLoading &&
              _lastLoaded != null;
          if (currentStation.status != null) _lastLoaded = currentStation;
          final station = widget.preview && currentStation.status == null
              ? _previewStation
              : switching
                  ? _lastLoaded!
                  : currentStation;
          final phase = widget.preview
              ? PlaybackPhase.online
              : ref.watch(playbackProvider.select((s) => s.phase));
          final error = widget.preview
              ? null
              : ref.watch(playbackProvider.select((s) => s.error));
          final controls = ExcludeFocus(
              excluding: !_controlsVisible,
              child: ExcludeSemantics(
                excluding: !_controlsVisible,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    key: const ValueKey('large-screen-controls'),
                    opacity: _controlsVisible ? 1 : 0,
                    duration:
                        ThmrMotion.of(context, exiting: !_controlsVisible),
                    curve: _controlsVisible
                        ? ThmrMotion.enterCurve
                        : ThmrMotion.exitCurve,
                    child: Focus(
                        focusNode: _controlsFocus,
                        child: _PlaybackControls(preview: widget.preview)),
                  ),
                ),
              ));
          final content = ThmrFadeSlide(
            key: ValueKey(widget.preview
                ? 'large-preview-transition'
                : 'large-mode-transition'),
            animation: _presentation,
            child: SafeArea(
              minimum: widget.safeInsets,
              child: LargeScreenContent(
                settings: settings,
                station: station,
                phase: phase,
                playbackError: error,
                header: _Header(preview: widget.preview),
                controls: controls,
              ),
            ),
          );
          return MouseRegion(
            cursor: _controlsVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onHover: (_) => _reveal(),
            child: Listener(
              onPointerDown: (_) => _reveal(),
              child: Focus(
                autofocus: !widget.preview,
                skipTraversal: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent) _reveal();
                  return KeyEventResult.ignored;
                },
                child: Scaffold(
                  backgroundColor: theme.thmr.pageBg,
                  body: Stack(fit: StackFit.expand, children: [
                    ThmrBackground(
                      showIllustration: settings.showIllustration,
                      illustrationOpacity: settings.illustrationOpacity,
                      alignment: settings.illustrationPosition ==
                              LargeScreenIllustrationPosition.right
                          ? Alignment.bottomRight
                          : Alignment.bottomLeft,
                      child: content,
                    ),
                    Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: StatusNotice(
                            message: switching ? '正在切换频道…' : null,
                            busy: switching,
                            duration: null)),
                  ]),
                ),
              ),
            ),
          );
        }));
  }
}

class _Header extends ConsumerWidget {
  const _Header({this.preview = false});
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = preview
        ? LargeScreenState(
            fullScreen: ref.watch(
                largeScreenSettingsProvider.select((s) => s.startFullScreen)))
        : ref.watch(largeScreenProvider);
    final brand = Row(children: [
      ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset('assets/brand/logo.png',
              width: 42, height: 42, excludeFromSemantics: true)),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('东方音乐电台',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 4),
        Text('Touhou Music Radio',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.thmr.mutedInk, letterSpacing: 1)),
      ])),
    ]);
    final channels = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: preview
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: theme.thmr.panelSoft,
                    border: Border.all(color: theme.thmr.panelBorder),
                    borderRadius: BorderRadius.circular(7)),
                child: Text(
                    '频道  ${ref.watch(stationProvider).status?.station.name ?? '东方综合频道'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium))
            : ChannelSwitcher(
                station: ref
                    .watch(stationProvider.select((s) => s.status?.station))));
    final actions = [
      if (hasDesktopWindowControls)
        IconButton(
            tooltip: state.fullScreen ? '退出全屏' : '进入全屏',
            onPressed: preview
                ? () {}
                : state.busy
                    ? null
                    : () => unawaited(ref
                        .read(largeScreenProvider.notifier)
                        .toggleFullScreen()),
            icon: LargeScreenGlyph(state.fullScreen
                ? LargeScreenSymbol.windowed
                : LargeScreenSymbol.fullscreen)),
      IconButton(
          tooltip: '收起大屏幕模式',
          onPressed: preview
              ? () {}
              : state.busy
                  ? null
                  : () => unawaited(
                      ref.read(largeScreenProvider.notifier).change(false)),
          icon: const LargeScreenGlyph(LargeScreenSymbol.collapse)),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: hasDesktopWindowControls
                      ? DragToMoveArea(
                          key: const ValueKey('large-screen-window-drag'),
                          child: brand)
                      : brand),
              if (!narrow) ...[
                const SizedBox(width: 20),
                channels,
                const SizedBox(width: 12)
              ],
              ...actions,
            ]),
            if (narrow) ...[const SizedBox(height: 10), channels],
          ]);
    });
  }
}

final _previewStation = StationUiState(
    initialLoading: false,
    status: StationStatus.fromJson({
      'station': {'id': 'preview', 'name': '东方综合频道'},
      'current': {
        'trackId': 'preview-current',
        'title': '春色小径 ～ Colorful Path',
        'artist': '上海アリス幻樂団',
        'durationSec': 214,
        'positionSec': 82,
      },
      'queue': [
        for (final title in [
          '少女綺想曲 ～ Dream Battle',
          '恋色マスタースパーク',
          '千年幻想郷 ～ History of the Moon'
        ])
          {
            'trackId': title,
            'title': title,
            'artist': '上海アリス幻樂団',
            'durationSec': 240
          },
      ],
    }));

class _PlaybackControls extends ConsumerWidget {
  const _PlaybackControls({this.preview = false});
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (phase, volume) = preview
        ? (PlaybackPhase.online, 60.0)
        : ref.watch(playbackProvider.select((s) => (s.phase, s.volume)));
    final connecting = phase == PlaybackPhase.connecting ||
        phase == PlaybackPhase.reconnecting;
    final playing =
        phase == PlaybackPhase.online || phase == PlaybackPhase.buffering;
    return ThmrPanel(
      enabled:
          ref.watch(largeScreenSettingsProvider.select((s) => s.cardLayout)),
      frost: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(children: [
        IconButton(
            tooltip: connecting
                ? '取消连接'
                : playing
                    ? '暂停播放'
                    : '播放',
            onPressed: preview
                ? () {}
                : () => unawaited(ref
                    .read(playbackProvider.notifier)
                    .toggle(ref.read(streamUrlProvider))),
            icon: Icon(connecting
                ? Icons.stop_rounded
                : playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded)),
        IconButton(
            tooltip: volume > 0 ? '静音' : '恢复音量',
            onPressed: preview
                ? () {}
                : () => ref.read(playbackProvider.notifier).setVolume(
                    ref.read(playbackProvider).volumeAfterMuteToggle),
            icon: Icon(volume > 0
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded)),
        Expanded(
            child: VolumeSlider(
                value: volume,
                onChanged: preview
                    ? (_) {}
                    : ref.read(playbackProvider.notifier).setVolume)),
        SizedBox(
            width: 42,
            child: Text('${volume.round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall)),
      ]),
    );
  }
}
