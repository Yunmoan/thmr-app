// Desktop mini player (Windows): compact always-on-top window.
//
// The main shell stays mounted while mini mode is active (see ThmrApp
// builder) — only the visible layer swaps, so tab/scroll state survives.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/player/playback_controller.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/track_cover.dart';
import '../../shared/widgets/volume_slider.dart';
import '../../shared/widgets/volume_wheel_control.dart';

/// Three selectable mini window sizes in logical pixels.
const Size kMiniSmallWindowSize = Size(320, 96);
const Size kMiniWindowSize = Size(344, 112);
const Size kMiniLargeWindowSize = Size(384, 132);

Size miniWindowSize(TextScaler textScaler,
    {MiniPlayerSizePreset preset = MiniPlayerSizePreset.medium}) {
  final base = switch (preset) {
    MiniPlayerSizePreset.small => kMiniSmallWindowSize,
    MiniPlayerSizePreset.medium => kMiniWindowSize,
    MiniPlayerSizePreset.large => kMiniLargeWindowSize,
  };
  final contentHeight = switch (preset) {
    MiniPlayerSizePreset.small => 84.0,
    MiniPlayerSizePreset.medium => 96.0,
    MiniPlayerSizePreset.large => 116.0,
  };
  final extraHeight = (textScaler.scale(contentHeight) - contentHeight)
      .clamp(0.0, double.infinity);
  return Size(base.width, base.height + extraHeight);
}

MiniPlayerSizePreset _miniPresetForWidth(double width) => width < 332
    ? MiniPlayerSizePreset.small
    : width < 364
        ? MiniPlayerSizePreset.medium
        : MiniPlayerSizePreset.large;

double miniSummaryHeight(TextScaler textScaler) =>
    (textScaler.scale(34) + 12).clamp(46.0, double.infinity);

/// 主窗口最小尺寸(与 main.dart 的 WindowOptions 保持一致)。
const Size kMainMinWindowSize = Size(430, 660);

/// 是否处于迷你模式。
final miniPlayerProvider = StateProvider<bool>((ref) => false);

/// Controls the short fade when the window enters or leaves mini mode.
final miniContentVisibleProvider = StateProvider<bool>((ref) => true);

/// 进入迷你模式前记录的主窗口边界(逻辑像素)。
final miniSavedBoundsProvider = StateProvider<Rect?>((ref) => null);

final _miniWasMaximizedProvider = StateProvider<bool>((ref) => false);

/// 进入迷你模式:先切 UI 再缩窗,避免主界面被挤压的一帧产生溢出。
Future<void> enterMiniMode(WidgetRef ref, TextScaler textScaler) async {
  if (kIsWeb || !Platform.isWindows) return;
  final wasMax = await windowManager.isMaximized();
  if (wasMax) {
    await windowManager.unmaximize();
    // 给 WM 一拍把还原后的边界稳定下来,再读取正常尺寸
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  final bounds = await windowManager.getBounds();
  ref.read(miniSavedBoundsProvider.notifier).state = bounds;
  ref.read(_miniWasMaximizedProvider.notifier).state = wasMax;
  ref.read(miniContentVisibleProvider.notifier).state = false;
  ref.read(miniPlayerProvider.notifier).state = true;
  await windowManager.setAsFrameless();
  await windowManager.setHasShadow(false);
  final size = miniWindowSize(
    textScaler,
    preset: ref.read(miniPlayerSizeProvider),
  );
  await windowManager.setMinimumSize(size);
  await windowManager.setResizable(false);
  await windowManager.setSize(size);
  await windowManager.setAlwaysOnTop(true);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  ref.read(miniContentVisibleProvider.notifier).state = true;
}

/// 退出迷你模式:先恢复窗口尺寸再切回主界面(迷你 UI 可自由拉伸)。
Future<void> exitMiniMode(WidgetRef ref) async {
  if (kIsWeb || !Platform.isWindows) return;
  ref.read(miniContentVisibleProvider.notifier).state = false;
  await Future<void>.delayed(const Duration(milliseconds: 180));
  await windowManager.setAlwaysOnTop(false);
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  await windowManager.setResizable(true);
  await windowManager.setMinimumSize(kMainMinWindowSize);
  final saved = ref.read(miniSavedBoundsProvider);
  if (saved != null) await windowManager.setBounds(saved);
  ref.read(miniPlayerProvider.notifier).state = false;
  ref.read(miniContentVisibleProvider.notifier).state = true;
  if (ref.read(_miniWasMaximizedProvider.notifier).state) {
    await windowManager.maximize();
  }
  await windowManager.show();
  await windowManager.focus();
}

/// 迷你播放窗:全区域可拖动,双击还原,置顶显示。
enum MiniEdge { top, left, right }

class MiniEdgePlacement {
  const MiniEdgePlacement(this.edge, this.expanded, this.tucked);

  final MiniEdge edge;
  final Offset expanded;
  final Offset tucked;

  Offset tuckedAt(double visibleExtent) => switch (edge) {
        MiniEdge.top => tucked.translate(0, visibleExtent - 16),
        MiniEdge.left => tucked.translate(visibleExtent - 16, 0),
        MiniEdge.right => tucked.translate(16 - visibleExtent, 0),
      };
}

MiniEdgePlacement? miniEdgePlacement(Rect window, Rect workArea) {
  const threshold = 18.0;
  const revealedWidth = 16.0;
  if (window.bottom <= workArea.top ||
      window.top >= workArea.bottom ||
      window.right <= workArea.left ||
      window.left >= workArea.right) {
    return null;
  }
  final topGap = (window.top - workArea.top).abs();
  final leftGap = (window.left - workArea.left).abs();
  final rightGap = (window.right - workArea.right).abs();
  if (topGap > threshold && leftGap > threshold && rightGap > threshold) {
    return null;
  }
  final x = window.left.clamp(
    workArea.left,
    (workArea.right - window.width).clamp(workArea.left, workArea.right),
  );
  final y = window.top.clamp(
    workArea.top,
    (workArea.bottom - window.height).clamp(workArea.top, workArea.bottom),
  );
  if (topGap <= threshold) {
    return MiniEdgePlacement(
      MiniEdge.top,
      Offset(x, workArea.top),
      Offset(x, workArea.top - window.height + revealedWidth),
    );
  }
  if (leftGap <= rightGap) {
    return MiniEdgePlacement(
      MiniEdge.left,
      Offset(workArea.left, y),
      Offset(workArea.left - window.width + revealedWidth, y),
    );
  }
  return MiniEdgePlacement(
    MiniEdge.right,
    Offset(workArea.right - window.width, y),
    Offset(workArea.right - revealedWidth, y),
  );
}

/// Select the display containing the largest part of the mini window.
Rect? miniWorkAreaForWindow(Rect window, Iterable<Rect> workAreas) {
  Rect? best;
  var bestOverlap = 0.0;
  var nearestDistance = double.infinity;
  for (final area in workAreas) {
    final intersection = window.intersect(area);
    final overlap = intersection.width.clamp(0.0, double.infinity) *
        intersection.height.clamp(0.0, double.infinity);
    final dx = window.center.dx.clamp(area.left, area.right) - window.center.dx;
    final dy = window.center.dy.clamp(area.top, area.bottom) - window.center.dy;
    final distance = dx * dx + dy * dy;
    if (overlap > bestOverlap ||
        (overlap == bestOverlap && distance < nearestDistance)) {
      best = area;
      bestOverlap = overlap;
      nearestDistance = distance;
    }
  }
  return best;
}

class MiniPlayerWindow extends ConsumerStatefulWidget {
  const MiniPlayerWindow({super.key, this.stationState, this.playbackState});

  /// Optional snapshots allow the fixed-size layout to be rendered in tests.
  final StationUiState? stationState;
  final PlaybackState? playbackState;

  @override
  ConsumerState<MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends ConsumerState<MiniPlayerWindow>
    with WindowListener {
  MiniEdgePlacement? _placement;
  Timer? _hideTimer;
  bool _tucked = false;
  bool _hovered = false;
  bool _dragging = false;
  bool _settingPosition = false;
  Offset? _tuckedTarget;
  int _moveSerial = 0;
  int _positionSerial = 0;
  Timer? _moveTimer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isWindows) windowManager.addListener(this);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _moveTimer?.cancel();
    _moveSerial++;
    _positionSerial++;
    if (!kIsWeb && Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() {
    if (_settingPosition || _dragging) return;
    _moveTimer?.cancel();
    final serial = ++_moveSerial;
    _moveTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(_snapAfterMove(serial).catchError((Object error) {
        debugPrint('Mini player edge snap failed: $error');
      }));
    });
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'show' && _tucked) unawaited(_reveal());
  }

  Future<void> _snapAfterMove(int serial) async {
    if (_settingPosition || _dragging || !mounted) return;
    final bounds = await windowManager.getBounds();
    final displays = await screenRetriever.getAllDisplays();
    if (!mounted || _dragging || serial != _moveSerial || displays.isEmpty) {
      return;
    }
    final currentTarget = _tucked ? _tuckedTarget : _placement?.expanded;
    if (currentTarget != null &&
        (bounds.topLeft - currentTarget).distance < 2) {
      return;
    }
    final workAreas = <Rect>[];
    for (final display in displays) {
      final position = display.visiblePosition;
      final size = display.visibleSize;
      if (position == null || size == null) continue;
      workAreas.add(position & size);
    }
    final nearest = miniWorkAreaForWindow(bounds, workAreas);
    if (nearest == null) return;
    final placement = miniEdgePlacement(bounds, nearest);
    if (placement == null) {
      setState(() {
        _placement = null;
        _tucked = false;
        _tuckedTarget = null;
      });
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _placement = placement;
      _tucked = false;
    });
    await _tuck(placement);
  }

  Future<void> _setPosition(Offset position) async {
    final serial = ++_positionSerial;
    _settingPosition = true;
    try {
      final start = (await windowManager.getBounds()).topLeft;
      for (var step = 1; step <= 9; step++) {
        if (!mounted || serial != _positionSerial) return;
        final progress = Curves.easeOutCubic.transform(step / 9);
        await windowManager
            .setPosition(Offset.lerp(start, position, progress)!);
        if (step < 9) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }
    } catch (error) {
      debugPrint('Mini player position update failed: $error');
    } finally {
      if (serial == _positionSerial) _settingPosition = false;
    }
  }

  Future<void> _tuck(MiniEdgePlacement placement) async {
    final mode = ref.read(settingsProvider).miniEdgeHideMode;
    final extent = switch (mode) {
      MiniEdgeHideMode.compact when placement.edge == MiniEdge.top =>
        miniSummaryHeight(MediaQuery.textScalerOf(context)),
      MiniEdgeHideMode.hidden => 3.0,
      _ => 16.0,
    };
    final target = placement.tuckedAt(extent);
    _tuckedTarget = target;
    final movement = _setPosition(target);
    final serial = _positionSerial;
    await movement;
    if (!mounted ||
        _dragging ||
        _placement != placement ||
        serial != _positionSerial) {
      return;
    }
    setState(() => _tucked = true);
  }

  void _onEnter(PointerEnterEvent event) {
    _hovered = true;
    _hideTimer?.cancel();
    unawaited(_reveal());
  }

  Future<void> _reveal() async {
    final placement = _placement;
    if (!_tucked || placement == null) return;
    setState(() => _tucked = false);
    await _setPosition(placement.expanded);
  }

  Future<void> _dragWindow() async {
    _dragging = true;
    _hideTimer?.cancel();
    _moveTimer?.cancel();
    _moveSerial++;
    _positionSerial++;
    _settingPosition = false;
    setState(() {
      _placement = null;
      _tucked = false;
      _tuckedTarget = null;
    });
    try {
      await windowManager.startDragging();
    } catch (error) {
      debugPrint('Mini player dragging failed: $error');
    } finally {
      if (mounted) {
        _dragging = false;
        onWindowMoved();
      }
    }
  }

  void _onExit(PointerExitEvent event) {
    _hovered = false;
    if (_placement == null || _tucked) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 450), () {
      final placement = _placement;
      if (!mounted || _hovered || placement == null || _tucked) return;
      unawaited(_tuck(placement));
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.miniEdgeHideMode));
    ref.listen(settingsProvider.select((s) => s.miniEdgeHideMode),
        (previous, next) {
      if (_tucked && _placement != null) unawaited(_tuck(_placement!));
    });
    final edge = _placement?.edge;
    final tabAlignment = switch (edge) {
      MiniEdge.top => Alignment.bottomCenter,
      MiniEdge.left => Alignment.centerRight,
      MiniEdge.right => Alignment.centerLeft,
      null => Alignment.center,
    };
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_tucked)
            _MiniPlayerBody(
              attachedEdge: edge,
              onDragStart: _dragWindow,
              stationState: widget.stationState,
              playbackState: widget.playbackState,
            ),
          if (_tucked &&
              edge == MiniEdge.top &&
              mode == MiniEdgeHideMode.compact)
            Align(
              alignment: Alignment.bottomCenter,
              child: _MiniCompactSummary(
                stationState: widget.stationState,
                onTap: () => unawaited(_reveal()),
              ),
            ),
          if (_tucked && edge != null && mode == MiniEdgeHideMode.hidden)
            Align(
              alignment: tabAlignment,
              child: Semantics(
                button: true,
                label: '悬停或点击展开迷你播放器',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_reveal()),
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.01),
                    child: SizedBox(
                      width: edge == MiniEdge.top ? double.infinity : 3,
                      height: edge == MiniEdge.top ? 3 : double.infinity,
                    ),
                  ),
                ),
              ),
            ),
          if (_tucked &&
              edge != null &&
              (mode == MiniEdgeHideMode.tab ||
                  (mode == MiniEdgeHideMode.compact && edge != MiniEdge.top)))
            Align(
              alignment: tabAlignment,
              child: SizedBox(
                width: edge == MiniEdge.top ? 44 : 16,
                height: edge == MiniEdge.top ? 16 : 44,
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: switch (edge) {
                    MiniEdge.top =>
                      const BorderRadius.vertical(bottom: Radius.circular(8)),
                    MiniEdge.left =>
                      const BorderRadius.horizontal(right: Radius.circular(8)),
                    MiniEdge.right =>
                      const BorderRadius.horizontal(left: Radius.circular(8)),
                  },
                  child: Semantics(
                    label: '展开迷你播放器',
                    button: true,
                    child: InkWell(
                      onTap: () => unawaited(_reveal()),
                      child: Icon(
                        switch (edge) {
                          MiniEdge.top => Icons.keyboard_arrow_down_rounded,
                          MiniEdge.left => Icons.chevron_right_rounded,
                          MiniEdge.right => Icons.chevron_left_rounded,
                        },
                        size: 14,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniCompactSummary extends ConsumerWidget {
  const _MiniCompactSummary({this.stationState, required this.onTap});

  final StationUiState? stationState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final showIllustration =
        ref.watch(settingsProvider.select((s) => s.miniShowIllustration));
    final StationUiState station =
        stationState ?? ref.watch<StationUiState>(stationProvider);
    final track = station.status?.current;
    return SizedBox(
      width: double.infinity,
      height: miniSummaryHeight(MediaQuery.textScalerOf(context)),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(10)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: tokens.solidPanel),
              if (showIllustration)
                const _MiniIllustration(height: 104, width: 80, bottom: -32),
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    children: [
                      TrackCover(
                          url: track?.coverUrl ?? '', size: 34, radius: 5),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track?.title ?? '暂无播放',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        color: tokens.ink,
                                        fontWeight: FontWeight.w700)),
                            Text(track?.artist ?? '等待下一首',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: tokens.mutedInk)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 18, color: tokens.mutedInk),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniIllustration extends StatelessWidget {
  const _MiniIllustration({
    required this.width,
    required this.height,
    required this.bottom,
  });

  final double width;
  final double height;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -6,
      bottom: bottom,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Opacity(
            opacity: 0.2,
            child: Image.asset(
              Theme.of(context).thmr.illustration,
              width: width,
              height: height,
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
              filterQuality: FilterQuality.low,
              cacheHeight: 400,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerBody extends ConsumerWidget {
  const _MiniPlayerBody({
    this.attachedEdge,
    required this.onDragStart,
    this.stationState,
    this.playbackState,
  });

  final MiniEdge? attachedEdge;
  final Future<void> Function() onDragStart;
  final StationUiState? stationState;
  final PlaybackState? playbackState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final layout =
        switch (_miniPresetForWidth(MediaQuery.sizeOf(context).width)) {
      MiniPlayerSizePreset.small => (
          cover: 60.0,
          left: 7.0,
          right: 6.0,
          vertical: 6.0,
          coverGap: 8.0,
          caption: 22.0,
          subtitle: 16.0,
          titleGap: 3.0,
          controlsGap: 3.0,
        ),
      MiniPlayerSizePreset.medium => (
          cover: 68.0,
          left: 8.0,
          right: 7.0,
          vertical: 7.0,
          coverGap: 9.0,
          caption: 24.0,
          subtitle: 18.0,
          titleGap: 4.0,
          controlsGap: 4.0,
        ),
      MiniPlayerSizePreset.large => (
          cover: 80.0,
          left: 10.0,
          right: 8.0,
          vertical: 9.0,
          coverGap: 11.0,
          caption: 28.0,
          subtitle: 21.0,
          titleGap: 6.0,
          controlsGap: 7.0,
        ),
    };
    final showIllustration =
        ref.watch(settingsProvider.select((s) => s.miniShowIllustration));
    final StationUiState station =
        stationState ?? ref.watch<StationUiState>(stationProvider);
    final status = station.status;
    final cur = status?.current;
    const rounded = Radius.circular(10);
    final radius = switch (attachedEdge) {
      MiniEdge.top =>
        const BorderRadius.only(bottomLeft: rounded, bottomRight: rounded),
      MiniEdge.left =>
        const BorderRadius.only(topRight: rounded, bottomRight: rounded),
      MiniEdge.right =>
        const BorderRadius.only(topLeft: rounded, bottomLeft: rounded),
      null => const BorderRadius.all(rounded),
    };

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tokens.solidPanel),
            if (showIllustration)
              const _MiniIllustration(height: 150, width: 116, bottom: -40),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => unawaited(onDragStart()),
              onDoubleTap: () => exitMiniMode(ref),
              child: Padding(
                padding: EdgeInsets.fromLTRB(layout.left, layout.vertical,
                    layout.right, layout.vertical),
                child: Row(
                  children: [
                    TrackCover(
                        url: cur?.coverUrl ?? '',
                        size: layout.cover,
                        radius: 6),
                    SizedBox(width: layout.coverGap),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cur?.title ?? '暂无播放',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          height: 1.2),
                                ),
                              ),
                              _MiniCaptionButton(
                                icon: Icons.open_in_full_rounded,
                                label: '恢复主窗口',
                                size: layout.caption,
                                onTap: () => exitMiniMode(ref),
                              ),
                              _MiniCaptionButton(
                                icon: Icons.close_rounded,
                                label: '隐藏迷你播放器',
                                size: layout.caption,
                                onTap: () => windowManager.hide(),
                              ),
                            ],
                          ),
                          SizedBox(height: layout.titleGap),
                          _MiniRotatingSubtitle(
                            artist: cur?.artist ?? '等待下一首',
                            listeners: status?.listeners,
                            height: layout.subtitle,
                          ),
                          SizedBox(height: layout.controlsGap),
                          _MiniControls(playbackState: playbackState),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows artist and listener count in one line, moving vertically every 4 s.
class _MiniRotatingSubtitle extends StatefulWidget {
  const _MiniRotatingSubtitle({
    required this.artist,
    required this.listeners,
    required this.height,
  });

  final String artist;
  final int? listeners;
  final double height;

  @override
  State<_MiniRotatingSubtitle> createState() => _MiniRotatingSubtitleState();
}

class _MiniRotatingSubtitleState extends State<_MiniRotatingSubtitle> {
  Timer? _timer;
  bool _showListeners = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (widget.listeners != null && mounted) {
        setState(() => _showListeners = !_showListeners);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showListeners = _showListeners && widget.listeners != null;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final label = showListeners ? '${widget.listeners} 人在听' : widget.artist;
    return SizedBox(
      height: widget.height,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) {
            final enteringFromBelow = child.key == const ValueKey('listeners');
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, enteringFromBelow ? 1 : -1),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Align(
            key: ValueKey(showListeners ? 'listeners' : 'artist'),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).thmr.mutedInk,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标题按钮保持无 Tooltip 的紧凑布局。
class _MiniCaptionButton extends StatelessWidget {
  const _MiniCaptionButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return SizedBox(
      width: size,
      height: size - 1,
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            hoverColor: tokens.ink.withValues(alpha: 0.08),
            child: Icon(icon, size: size * 0.55, color: tokens.mutedInk),
          ),
        ),
      ),
    );
  }
}

/// 播放/暂停 + 静音 + 音量滑杆。全部窄订阅,整窗不随秒级 tick 重建。
class _MiniControls extends ConsumerWidget {
  const _MiniControls({this.playbackState});

  final PlaybackState? playbackState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final layout =
        switch (_miniPresetForWidth(MediaQuery.sizeOf(context).width)) {
      MiniPlayerSizePreset.small => (
          play: 28.0,
          playIcon: 18.0,
          gap: 4.0,
          volume: 28.0,
          value: 30.0,
        ),
      MiniPlayerSizePreset.medium => (
          play: 30.0,
          playIcon: 19.0,
          gap: 5.0,
          volume: 30.0,
          value: 32.0,
        ),
      MiniPlayerSizePreset.large => (
          play: 34.0,
          playIcon: 21.0,
          gap: 8.0,
          volume: 34.0,
          value: 36.0,
        ),
    };
    final accent = Theme.of(context).colorScheme.primary;
    final PlaybackPhase phase = playbackState?.phase ??
        ref.watch<PlaybackPhase>(playbackProvider.select((s) => s.phase));
    final double volume = playbackState?.volume ??
        ref.watch<double>(playbackProvider.select((s) => s.volume));
    final busy = phase == PlaybackPhase.connecting ||
        phase == PlaybackPhase.reconnecting;
    final playing =
        phase == PlaybackPhase.online || phase == PlaybackPhase.buffering;

    return Row(
      children: [
        SizedBox(
          width: layout.play,
          height: layout.play,
          child: Material(
            color: accent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                final url = ref.read(streamUrlProvider);
                ref.read(playbackProvider.notifier).toggle(url);
              },
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.onAccent,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: layout.playIcon,
                        color: tokens.onAccent,
                      ),
              ),
            ),
          ),
        ),
        SizedBox(width: layout.gap),
        VolumeWheelControl(
          value: volume,
          onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          child: IconButton(
            constraints: BoxConstraints.tightFor(
                width: layout.volume, height: layout.volume),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              volume <= 0
                  ? Icons.volume_off_rounded
                  : volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 17,
              color: tokens.mutedInk,
            ),
            onPressed: () {
              final pb = ref.read(playbackProvider);
              ref
                  .read(playbackProvider.notifier)
                  .setVolume(pb.volumeAfterMuteToggle);
            },
          ),
        ),
        Expanded(
          child: VolumeSlider(
            value: volume,
            height: layout.play,
            onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          ),
        ),
        SizedBox(
          width: layout.value,
          child: Text(
            '${volume.round()}%',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.mutedInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
