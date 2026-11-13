import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/radio_api.dart';
import '../../../core/models/models.dart';
import '../../../core/player/playback_controller.dart';
import '../../../core/player/spectrum.dart'
    show SpectrumSource, RetryableSpectrumSource, getPlatformSpectrum;
import '../../../core/state/app_providers.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/channel_provider.dart';
import '../../../core/state/station_provider.dart';
import '../../../core/theme/thmr_theme.dart';
import '../../../shared/widgets/player_panel_layout.dart';
import '../../../shared/widgets/volume_slider.dart';
import '../../../shared/widgets/focus_outline.dart';
import '../../../shared/widgets/volume_wheel_control.dart';
import 'bitrate_row.dart';
import 'feedback_sheet.dart';

/// 正在放送面板:封面 + 曲名 + 直播进度 + 控制排(收藏 / 播放 / 反馈)。
///
/// 重建范围刻意收窄:本面板只订阅低频状态(电台 10s 轮询、收藏状态);
/// 秒级变化由 [_PlayBar] / [_VolumeControl] 各自窄订阅,
/// 整面板不再每秒重建。
class NowPlayingPanel extends ConsumerStatefulWidget {
  const NowPlayingPanel(
      {super.key, required this.status, this.inlineBitrate = true});

  final StationStatus status;

  /// Mobile: quality chips live inside the panel; desktop keeps a separate
  /// panel (its own row) instead.
  final bool inlineBitrate;

  @override
  ConsumerState<NowPlayingPanel> createState() => _NowPlayingPanelState();
}

class _NowPlayingPanelState extends ConsumerState<NowPlayingPanel> {
  Future<void> _onMainButton() {
    return ref
        .read(playbackProvider.notifier)
        .toggle(ref.read(streamUrlProvider));
  }

  Future<void> _toggleFavorite(CurrentTrack cur) async {
    final auth = ref.read(authProvider);
    if (!auth.signedIn) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登录后即可收藏曲目,在「我的」页登录')));
      return;
    }
    final api = ref.read(authProvider.notifier).api;
    final stationId = widget.status.station.id;
    final fs = ref.read(favoritesStatusProvider).asData?.value;
    try {
      if (fs != null &&
          fs.favorited &&
          fs.itemId != null &&
          fs.collectionId != null) {
        await api.removeItem(fs.collectionId!, fs.itemId!);
      } else {
        // 默认收藏夹 = collections 首个(position 最小)
        final String defaultCid;
        if (fs != null && fs.collections.isNotEmpty) {
          defaultCid = fs.collections.first.collectionId;
        } else {
          final cols = await api.collections();
          if (!mounted) return;
          if (cols.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('还没有收藏夹,请先在「收藏夹」页新建')),
            );
            return;
          }
          defaultCid = cols.first.id;
        }
        await api.addToCollection(defaultCid,
            stationId: stationId, trackId: cur.trackId);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('这首已经在收藏夹里了')));
      } else if (e.statusCode == 401) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录已过期,请重新登录')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败:${e.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('网络异常,稍后再试')));
    } finally {
      if (mounted) {
        ref.invalidate(favoritesStatusProvider);
        ref.invalidate(collectionsProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.status.current;
    final favorited = ref.watch(favoritesStatusProvider
        .select((v) => v.asData?.value.favorited ?? false));

    return PlayerPanelLayout(
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover96(cur: cur),
          const SizedBox(width: 14),
          Expanded(
              child: NowPlayingTrackInfo(
            cur: cur,
            favorited: favorited,
            onFavorite: cur == null ? null : () => _toggleFavorite(cur),
            onFeedback: cur == null
                ? null
                : () => showFeedbackSheet(context,
                    track: cur, stationId: widget.status.station.id),
          )),
        ],
      ),
      playback: Column(mainAxisSize: MainAxisSize.min, children: [
        _PlayBar(onToggle: _onMainButton),
        const _PlaybackError()
      ]),
      volume: _VolumeControl(desktopInline: !widget.inlineBitrate),
      quality: widget.inlineBitrate ? const BitrateRow() : null,
    );
  }
}

class _Cover96 extends StatelessWidget {
  const _Cover96({required this.cur});

  final CurrentTrack? cur;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final track = cur;
    // 限制解码尺寸:96px 封面不必解码原图
    final cacheWidth = (96 * MediaQuery.devicePixelRatioOf(context)).round();
    final child = (track == null || track.coverUrl.isEmpty)
        ? Image.asset('assets/brand/cover-fallback.png',
            fit: BoxFit.cover, cacheWidth: cacheWidth)
        : Image.network(
            track.coverUrl,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Image.asset(
                'assets/brand/cover-fallback.png',
                fit: BoxFit.cover,
                cacheWidth: cacheWidth),
          );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOut,
          child: KeyedSubtree(
            key: ValueKey(track?.coverUrl ?? 'no-cover'),
            child: SizedBox(width: 96, height: 96, child: child),
          ),
        ),
      ),
    );
  }
}

/// track copy block: eyebrow + title + artist row + actions (web layout).
class NowPlayingTrackInfo extends ConsumerWidget {
  const NowPlayingTrackInfo({
    super.key,
    required this.cur,
    required this.favorited,
    this.onFavorite,
    this.onFeedback,
  });

  final CurrentTrack? cur;
  final bool favorited;
  final VoidCallback? onFavorite;
  final VoidCallback? onFeedback;

  Future<void> _copyTrackInfo(BuildContext context) async {
    final track = cur;
    if (track == null) return;
    await Clipboard.setData(ClipboardData(
      text: trackSearchText(title: track.title, artist: track.artist),
    ));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('歌曲信息已复制')));
  }

  Future<void> _handleFavoriteTap(BuildContext context, WidgetRef ref) async {
    if (cur == null || onFavorite == null) return;
    final stationId = ref.read(activeStationIdProvider);
    final fs = ref.read(favoritesStatusProvider).asData?.value;
    final cols = fs?.collections ?? const <FavCollectionRef>[];
    // Single collection (or unknown): keep the direct toggle path.
    if (cols.length <= 1) {
      onFavorite!();
      return;
    }
    // Multiple collections: anchored pick menu, mirrors web fav-menu.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      onFavorite!();
      return;
    }
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final picked = await showMenu<FavCollectionRef>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + size.height + 6,
        pos.dx + size.width,
        pos.dy + size.height,
      ),
      items: [
        for (final c in cols)
          PopupMenuItem(
            value: c,
            child: AncestorFocusOutline(
                child: Row(
              children: [
                Icon(
                  c.favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 15,
                  color: c.favorited
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).thmr.mutedInk,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).thmr.ink)),
                ),
                const SizedBox(width: 10),
                Text(
                  c.favorited ? '已收藏' : '收藏',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: c.favorited
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).thmr.mutedInk),
                ),
              ],
            )),
          ),
      ],
    );
    if (picked == null || !context.mounted) return;
    try {
      final api = ref.read(authProvider.notifier).api;
      if (picked.favorited && picked.itemId != null) {
        await api.removeItem(picked.collectionId, picked.itemId!);
      } else {
        await api.addToCollection(picked.collectionId,
            stationId: stationId, trackId: cur!.trackId);
      }
      if (!context.mounted) return;
      ref.invalidate(favoritesStatusProvider);
      ref.invalidate(collectionsProvider);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.statusCode == 409 ? '已在该收藏夹中' : '操作失败:${e.message}')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('网络异常,稍后再试')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '当前曲目',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.mutedInk,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Text(
            cur?.title ?? '暂无播放',
            key: ValueKey(cur?.trackId ?? 'none'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Text(
            cur?.artist ?? '等待下一首',
            key: ValueKey('a${cur?.trackId ?? 'none'}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.mutedInk),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Builder(
              builder: (buttonContext) => _TextAction(
                label: favorited ? '已收藏' : '收藏',
                active: favorited,
                onTap: onFavorite == null
                    ? null
                    : () => _handleFavoriteTap(buttonContext, ref),
              ),
            ),
            _TextAction(label: '反馈', onTap: onFeedback),
            _TextAction(
              label: '复制信息',
              onTap: cur == null ? null : () => _copyTrackInfo(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// small bordered text button, mirrors web .track-feedback-button.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: active ? tokens.accentSoft : tokens.fieldBg,
      borderRadius: BorderRadius.circular(6),
      child: FocusOutline(
          radius: 6,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.5)
                      : tokens.panelBorder,
                ),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: active ? accent : tokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          )),
    );
  }
}

class _PlayBar extends ConsumerWidget {
  const _PlayBar({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final scheme = Theme.of(context).colorScheme;
    // Only phase changes rebuild the controls; the clock owns its second tick.
    final phase = ref.watch(playbackProvider.select((s) => s.phase));
    final busy = phase == PlaybackPhase.connecting ||
        phase == PlaybackPhase.reconnecting;
    final playing =
        phase == PlaybackPhase.online || phase == PlaybackPhase.buffering;
    final label = switch (phase) {
      PlaybackPhase.idle => '播放',
      PlaybackPhase.connecting => '连接中',
      PlaybackPhase.online => '正在播放',
      PlaybackPhase.buffering => '正在播放',
      PlaybackPhase.reconnecting => '重连中',
    };

    return FocusOutline(
        child: Material(
      color: tokens.fieldBg,
      borderRadius: BorderRadius.circular(8),
      child: Semantics(
        label: busy
            ? '取消连接'
            : playing
                ? '暂停播放'
                : '播放',
        button: true,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.panelBorder),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 52,
                  child: _ListeningClock(),
                ),
                const SizedBox(width: 12),
                Expanded(child: AudioStrip(playing: playing, busy: busy)),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: playing ? scheme.primary : tokens.mutedInk,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _ListeningClock extends ConsumerWidget {
  const _ListeningClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elapsed = ref.watch(playbackProvider.select((s) => s.listenedSec));
    return Text(
      formatDuration(elapsed),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Live audio spectrum. When decoding is unavailable the strip settles to rest
/// instead of showing motion unrelated to the playing audio.
///
/// 性能:单一 Ticker 节流到 ~20fps(被 TickerMode 静音时零开销,切页即停),
/// 并以 CustomPaint 一次绘制全部频谱条,替代逐帧构建上百个 widget。
class AudioStrip extends StatefulWidget {
  const AudioStrip({
    super.key,
    required this.playing,
    this.busy = false,
    this.source,
  });

  final bool playing;
  final bool busy;
  final SpectrumSource? source;

  @override
  State<AudioStrip> createState() => _AudioStripState();
}

class _AudioStripState extends State<AudioStrip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  late final SpectrumSource? _cap = widget.source ?? getPlatformSpectrum();
  final _frames = ValueNotifier(0);
  List<double> _values = [];
  Duration _last = Duration.zero;
  bool _capturing = false;
  bool _unavailable = false;

  bool get _canAnimate {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return true;
    // Desktop windows remain visible when another window takes input focus.
    // Keep sampling until the window is actually hidden/minimized.
    return state == AppLifecycleState.inactive &&
        switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.macOS =>
            true,
          _ => false,
        };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.playing && _canAnimate && TickerMode.valuesOf(context).enabled) {
      _begin();
    } else {
      _stopCapture();
      _ticker.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_canAnimate && widget.playing) {
      _begin();
    } else {
      _stopCapture();
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(AudioStrip old) {
    super.didUpdateWidget(old);
    // 暂停时不立刻停表:让 tick 走完衰减到静止再自动停
    if (widget.playing && !old.playing) _begin();
    if (!widget.playing && old.playing) _stopCapture();
  }

  void _begin() {
    if (_cap == null || !_canAnimate || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    if (!_capturing) {
      _cap.start();
      _capturing = true;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _stopCapture() {
    if (!_capturing) return;
    _cap?.stop();
    _capturing = false;
  }

  Future<void> _retrySpectrum() async {
    final source = _cap;
    if (source is! RetryableSpectrumSource) return;
    final ready = await source.retry();
    if (!mounted) return;
    setState(() {});
    if (!ready) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(source.unavailableReason ?? '实时频谱暂不可用，请重试。'),
      ));
    }
  }

  void _onTick(Duration elapsed) {
    // ~20fps is plenty; skip the in-between frames.
    if (elapsed - _last < const Duration(milliseconds: 48)) return;
    _last = elapsed;
    var settled = false;
    if (widget.playing) {
      _step();
    } else {
      for (var i = 0; i < _values.length; i++) {
        _values[i] += (0.05 - _values[i]) * 0.32;
      }
      settled = _values.every((v) => v <= 0.065);
    }
    if (settled) {
      // 衰减到静止 → 停表,暂停时零开销
      _ticker.stop();
      _last = Duration.zero;
    }
    final source = _cap;
    final unavailable =
        source is RetryableSpectrumSource && source.isUnavailable;
    if (unavailable != _unavailable) {
      setState(() => _unavailable = unavailable);
    }
    // The envelope updates pixels only. Keep layout, buttons and semantics out
    // of the ~20 Hz path, including on high refresh rate displays.
    _frames.value++;
  }

  void _step() {
    final n = _values.length;
    if (n == 0) return;
    final real = _cap?.poll(n);
    if (real != null) {
      for (var i = 0; i < n; i++) {
        // asymmetric envelope: moderate attack, graceful release
        final nv = real[i];
        final k = nv > _values[i] ? 0.42 : 0.09;
        _values[i] += (nv - _values[i]) * k;
      }
      return;
    }
    for (var i = 0; i < n; i++) {
      _values[i] += (0.02 - _values[i]) * 0.22;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _stopCapture();
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(builder: (context, box) {
      // one bar per ~8px, clamped
      final count = (box.maxWidth / 8).round().clamp(28, 110);
      if (_values.length != count) {
        final old = _values;
        _values = List.generate(count, (i) => i < old.length ? old[i] : 0.08);
      }
      final retryable = _cap is RetryableSpectrumSource ? _cap : null;
      _unavailable = retryable?.isUnavailable ?? false;
      final needsAction =
          widget.playing && retryable != null && retryable.isUnavailable;
      return RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: CustomPaint(
                painter: _SpectrumPainter(
                  values: _values,
                  color: accent,
                  playing: widget.playing,
                  repaint: _frames,
                ),
                child: const SizedBox(width: double.infinity, height: 36),
              ),
            ),
            if (needsAction)
              box.maxWidth < 180
                  ? Tooltip(
                      message: '重试实时频谱',
                      child: TextButton(
                        onPressed: _retrySpectrum,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('频谱'),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _retrySpectrum,
                      icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                      label: const Text('重试实时频谱'),
                    ),
          ],
        ),
      );
    });
  }
}

/// Draws one rounded bar per value, growing symmetrically around the
/// vertical midline — visually identical to the old Row-of-Containers.
class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.values,
    required this.color,
    required this.playing,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<double> values;
  final Color color;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0 || size.width <= 0) return;
    final slot = size.width / n;
    final barW = (slot - 2.0).clamp(1.2, slot);
    final radius = Radius.circular(math.min(2.0, barW / 2));
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final h = 2.0 + 32.0 * v;
      paint.color = color.withValues(alpha: playing ? 0.4 + 0.6 * v : 0.22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * slot + (slot - barW) / 2,
            (size.height - h) / 2,
            barW,
            h,
          ),
          radius,
        ),
        paint,
      );
    }
  }

  // In-place envelope changes arrive through the repaint Listenable.
  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      values != oldDelegate.values ||
      color != oldDelegate.color ||
      playing != oldDelegate.playing;
}

/// 播放错误条:窄订阅,仅在错误出现/消失时重建。
class _PlaybackError extends ConsumerWidget {
  const _PlaybackError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure =
        ref.watch(playbackProvider.select((s) => (s.error, s.phase)));
    final error = failure.$2 == PlaybackPhase.idle ? failure.$1 : null;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        error,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// 音量控制:桌面 = 常驻内联滑杆;手机 = 图标 + 弹层。
class _VolumeControl extends ConsumerStatefulWidget {
  const _VolumeControl({required this.desktopInline});

  final bool desktopInline;

  @override
  ConsumerState<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends ConsumerState<_VolumeControl> {
  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(playbackProvider.select((s) => s.volume));
    if (!widget.desktopInline) {
      // Mobile: compact icon that opens a popup slider (原行为)
      final muted = volume <= 0;
      return Align(
        alignment: Alignment.centerLeft,
        child: VolumeWheelControl(
          value: volume,
          onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          child: FocusOutline(
              child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              builder: (sheetContext) => const _VolumeSheet(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    muted
                        ? Icons.volume_off_rounded
                        : volume < 50
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                    size: 18,
                    color: Theme.of(context).thmr.mutedInk,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '音量 ${volume.round()}%',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Theme.of(context).thmr.mutedInk),
                  ),
                ],
              ),
            ),
          )),
        ),
      );
    }

    // Desktop: inline slider, always visible.
    final tokens = Theme.of(context).thmr;
    final shown = volume;
    final muted = shown <= 0;
    return Row(
      children: [
        VolumeWheelControl(
          value: shown,
          onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          child: IconButton(
            tooltip: muted ? '取消静音' : '静音',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              muted
                  ? Icons.volume_off_rounded
                  : shown < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 18,
              color: tokens.mutedInk,
            ),
            onPressed: () => ref
                .read(playbackProvider.notifier)
                .setVolume(ref.read(playbackProvider).volumeAfterMuteToggle),
          ),
        ),
        Expanded(
          child: VolumeSlider(
            value: shown,
            onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${shown.round()}%',
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

class _VolumeSheet extends ConsumerWidget {
  const _VolumeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final value = ref.watch(playbackProvider.select((s) => s.volume));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('播放音量',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              VolumeWheelControl(
                value: value,
                onChanged: (v) =>
                    ref.read(playbackProvider.notifier).setVolume(v),
                child: IconButton(
                  tooltip: value <= 0 ? '取消静音' : '静音',
                  icon: Icon(
                      value <= 0
                          ? Icons.volume_off_rounded
                          : value < 50
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      color: tokens.mutedInk),
                  onPressed: () => ref
                      .read(playbackProvider.notifier)
                      .setVolume(
                          ref.read(playbackProvider).volumeAfterMuteToggle),
                ),
              ),
              Expanded(
                  child: VolumeSlider(
                      value: value,
                      onChanged: (v) =>
                          ref.read(playbackProvider.notifier).setVolume(v))),
              SizedBox(
                  width: 48,
                  child: Text('${value.round()}%',
                      textAlign: TextAlign.right,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: tokens.mutedInk))),
            ]),
          ],
        ),
      ),
    );
  }
}
