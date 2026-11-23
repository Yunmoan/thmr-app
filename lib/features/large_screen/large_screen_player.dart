import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thmr_app/shared/widgets/volume_wheel_control.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/desktop_window.dart';
import '../../core/platform/mobile_presentation.dart';
import '../../core/player/playback_controller.dart';
import '../../core/player/spectrum.dart';
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
import 'large_screen_fluid_colors.dart';
import 'large_screen_music_visual.dart';
import 'large_screen_symbols.dart';
import '../listen/widgets/channel_switcher.dart';

final largeScreenThemeProvider =
    Provider.family<ThemeData, ThemeMode>((ref, mode) {
  final accent = ref.watch(settingsProvider.select((s) => s.accentTheme));
  return mode == ThemeMode.light
      ? ThmrTheme.light(accent)
      : ThmrTheme.dark(accent);
});

final largeScreenSpectrumProvider =
    Provider<SpectrumSource?>((ref) => getPlatformSpectrum());

/// 大屏模式沿用 THMR 的纸面、角色插画和排版，收起导航。播放器和频道状态在整个切换过程中保持挂载。
class LargeScreenPlayer extends ConsumerStatefulWidget {
  const LargeScreenPlayer(
      {super.key,
      this.safeInsets = EdgeInsets.zero,
      this.preview = false,
      this.phonePreview = false,
      this.demoRun = 0,
      this.liveSpectrumPreview = false});
  final EdgeInsets safeInsets;
  final bool preview;
  final bool phonePreview;
  final int demoRun;
  final bool liveSpectrumPreview;

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
        // 大屏可能在不透明路由下方入场，此时 Ticker 会静音。超时后直接应用最终状态，
        // 避免界面一直透明并占用忙碌状态。
        _presentation.stop();
        _presentation.value = visible ? 1 : 0;
      });
    } on TickerCanceled {
      // 移除大屏界面时，也需要解除原生模式切换的等待。
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
          // 原生全屏切换可能替换或取消动画 Ticker。切换完成后需要确保内容已经可见。
          _presentationVisible = true;
          _presentation.value = 1;
        }
      });
      // 过渡中重挂载可能错过控制器回调。此时以共享的可见状态为准，确保大屏启用后内容可以显示。
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
    final fullScreen = widget.preview
        ? false
        : ref.watch(largeScreenProvider.select((state) => state.fullScreen));
    final theme = settings.themeMode == ThemeMode.system
        ? Theme.of(context)
        : ref.watch(largeScreenThemeProvider(settings.themeMode));
    return Theme(
        data: theme,
        child: Builder(builder: (context) {
          final phone = widget.preview
              ? widget.phonePreview
              : usesPhoneLayout(context, ref);
          final landscape =
              MediaQuery.orientationOf(context) == Orientation.landscape;
          final artOnRight = settings.illustrationPosition ==
              LargeScreenIllustrationPosition.right;
          final artOnTop = phone && !landscape;
          final illustrationAlignment = artOnTop
              ? (artOnRight ? Alignment.topRight : Alignment.topLeft)
              : (artOnRight ? Alignment.bottomRight : Alignment.bottomLeft);
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
                  child: Opacity(
                    key: const ValueKey('large-screen-controls'),
                    opacity: _controlsVisible ? 1 : 0,
                    child: Focus(
                        focusNode: _controlsFocus,
                        child: _PlaybackControls(
                            preview: widget.preview, phone: phone)),
                  ),
                ),
              ));
          final coverUrl = station.status?.current?.coverUrl.trim() ?? '';
          final demoVisual = widget.preview && !widget.liveSpectrumPreview;
          final playing = !demoVisual &&
              phase == PlaybackPhase.online &&
              (widget.preview ||
                  ref.watch(largeScreenProvider
                      .select((state) => state.contentVisible)));
          final source =
              demoVisual ? null : ref.watch(largeScreenSpectrumProvider);
          final fluidStage =
              settings.musicEffect == LargeScreenMusicEffect.fluid;
          final artwork = fluidStage && coverUrl.isNotEmpty
              ? ResizeImage(NetworkImage(coverUrl),
                  width: 48, height: 48, policy: ResizeImagePolicy.fit)
              : null;
          Color? illustrationTint(FluidColors? colors) {
            if (colors == null) return null;
            final toned = toneFluidColors(
                colors, theme.thmr, theme.brightness == Brightness.dark);
            final pigment = Color.lerp(
                    Color.lerp(toned.topLeft, toned.topRight, .5),
                    Color.lerp(toned.bottomLeft, toned.bottomRight, .5),
                    .5)!
                .withValues(alpha: .38);
            return pigment;
          }

          final content = ThmrFadeSlide(
            key: ValueKey(widget.preview
                ? 'large-preview-transition'
                : 'large-mode-transition'),
            animation: _presentation,
            fade: false,
            child: SafeArea(
              minimum: widget.safeInsets,
              child: LargeScreenContent(
                settings: settings,
                station: station,
                phase: phase,
                playbackError: error,
                header: _Header(preview: widget.preview, phone: phone),
                controls: controls,
                phone: phone,
              ),
            ),
          );
          return LargeScreenFluidArtwork(
            artwork: artwork,
            builder: (context, artworkColors) {
              final musicVisual =
                  settings.musicEffect == LargeScreenMusicEffect.off
                      ? null
                      : LargeScreenMusicVisual(
                          key: ValueKey(widget.demoRun),
                          effect: settings.musicEffect,
                          intensity: settings.musicEffectIntensity,
                          lowPower: settings.musicEffectLowPower,
                          fluidMotion: settings.fluidMotion,
                          artworkColors: artworkColors,
                          themeTint: settings.themeTint,
                          demo: demoVisual,
                          playing: playing,
                          source: source,
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
                          underlay: musicVisual,
                          underlayAboveWash: fluidStage,
                          showIllustration: settings.showIllustration,
                          illustrationTint: illustrationTint(artworkColors),
                          illustrationWidthFactor: phone
                              ? (landscape
                                  ? phoneLandscapeIllustrationWidth
                                  : .54)
                              : null,
                          illustrationHeightFactor: artOnTop ? .44 : null,
                          illustrationOpacity: settings.illustrationOpacity *
                              (fluidStage ? .55 : 1) *
                              (artOnTop ? .32 : 1),
                          alignment: illustrationAlignment,
                          child: content,
                        ),
                        if (hasDesktopWindowControls &&
                            !fullScreen &&
                            !widget.preview)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height:
                                (settings.contentMargin + 8).clamp(24.0, 64.0),
                            child: const DragToMoveArea(
                              key: ValueKey('large-screen-window-drag-strip'),
                              child: SizedBox.expand(),
                            ),
                          ),
                        Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: SafeArea(
                              top: false,
                              child: StatusNotice(
                                  message: switching ? '正在切换频道…' : null,
                                  busy: switching,
                                  duration: null),
                            )),
                      ]),
                    ),
                  ),
                ),
              );
            },
          );
        }));
  }
}

class _Header extends ConsumerWidget {
  const _Header({this.preview = false, this.phone = false});
  final bool preview;
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = preview
        ? LargeScreenState(
            fullScreen: ref.watch(
                largeScreenSettingsProvider.select((s) => s.startFullScreen)))
        : ref.watch(largeScreenProvider);
    final logo = ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset('assets/brand/logo.png',
            width: phone ? 30 : 42,
            height: phone ? 30 : 42,
            excludeFromSemantics: true));
    final brand = Row(children: [
      logo,
      const SizedBox(width: 12),
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    '${phone ? '' : '频道  '}${ref.watch(stationProvider).status?.station.name ?? '东方综合频道'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium))
            : ChannelSwitcher(
                compact: phone,
                station: ref
                    .watch(stationProvider.select((s) => s.status?.station))));
    final collapse = IconButton(
      tooltip: '收起大屏幕模式',
      style: phone
          ? IconButton.styleFrom(
              backgroundColor: theme.thmr.solidPanel,
              minimumSize: const Size.square(44),
            )
          : null,
      onPressed: preview
          ? () {}
          : state.busy
              ? null
              : () => unawaited(
                  ref.read(largeScreenProvider.notifier).change(false)),
      icon: const LargeScreenGlyph(LargeScreenSymbol.collapse),
    );
    if (phone) {
      return Row(
        spacing: 8,
        children: [
          logo,
          Expanded(
              child: Align(alignment: Alignment.centerLeft, child: channels)),
          collapse,
        ],
      );
    }
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
      collapse,
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
  const _PlaybackControls({this.preview = false, this.phone = false});
  final bool preview;
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (phase, volume) = preview
        ? (PlaybackPhase.online, 60.0)
        : ref.watch(playbackProvider.select((s) => (s.phase, s.volume)));
    final connecting = phase == PlaybackPhase.connecting ||
        phase == PlaybackPhase.reconnecting;
    final playing =
        phase == PlaybackPhase.online || phase == PlaybackPhase.buffering;
    final theme = Theme.of(context);
    return ThmrPanel(
      enabled:
          ref.watch(largeScreenSettingsProvider.select((s) => s.cardLayout)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(children: [
        IconButton(
            style: phone
                ? IconButton.styleFrom(
                    minimumSize: const Size.square(44),
                    backgroundColor: theme.thmr.accentSoft,
                    foregroundColor: theme.thmr.ink,
                  )
                : null,
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
        // @Aoralsfout：鼠标悬停时，滚轮用于调整音量。
        VolumeWheelControl(
          value: volume,
          onChanged:
              preview ? (_) {} : ref.read(playbackProvider.notifier).setVolume,
          child: IconButton(
              style: phone
                  ? IconButton.styleFrom(minimumSize: const Size.square(44))
                  : null,
              tooltip: volume > 0 ? '静音' : '恢复音量',
              onPressed: preview
                  ? () {}
                  : () => ref.read(playbackProvider.notifier).setVolume(
                      ref.read(playbackProvider).volumeAfterMuteToggle),
              icon: Icon(volume > 0
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded)),
        ),
        Expanded(
            child: VolumeSlider(
                value: volume,
                height: phone ? 44 : 34,
                onChanged: preview
                    ? (_) {}
                    : ref.read(playbackProvider.notifier).setVolume)),
        if (!phone || MediaQuery.textScalerOf(context).scale(11) <= 20)
          SizedBox(
              width: 42,
              child: Text('${volume.round()}%',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall)),
      ]),
    );
  }
}
