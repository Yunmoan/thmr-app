import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/mobile_presentation.dart';
import '../../core/player/playback_controller.dart';
import '../../core/state/large_screen_settings.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_menu.dart';
import 'large_screen_player.dart';

const _tabletFrame = ('4:3', Size(1024, 768), false);
const _phonePortrait = ('手机竖屏', Size(390, 844), true);
const _phoneLandscape = ('手机横屏', Size(844, 390), true);
const _frames = <(String, Size, bool)>[
  ('16:9', Size(1280, 720), false),
  ('16:10', Size(1280, 800), false),
  _tabletFrame,
  ('9:16', Size(720, 1280), false),
  _phonePortrait,
  _phoneLandscape,
];

/// 用虚拟屏幕尺寸渲染实际的大屏布局。预览不接管真实窗口的动画回调、音频控制、焦点或指针输入。
class LargeScreenPreview extends ConsumerStatefulWidget {
  const LargeScreenPreview({super.key, this.canExpand = true});
  final bool canExpand;

  static Future<void> open(BuildContext context) => showThmrDialog<void>(
      context: context,
      animationStyle: ThmrMotion.style(context),
      fade: false,
      builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text('大屏预览',
                              style: Theme.of(context).textTheme.titleMedium)),
                      IconButton(
                          tooltip: '关闭预览',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 20)),
                    ]),
                    const SizedBox(height: 12),
                    const Expanded(child: LargeScreenPreview(canExpand: false)),
                  ])))));

  @override
  ConsumerState<LargeScreenPreview> createState() => _LargeScreenPreviewState();
}

class _LargeScreenPreviewState extends ConsumerState<LargeScreenPreview> {
  (String, Size, bool)? _selectedFrame;
  int _demoRun = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frame = _selectedFrame ??
        (usesPhoneLayout(context, ref)
            ? MediaQuery.orientationOf(context) == Orientation.portrait
                ? _phonePortrait
                : _phoneLandscape
            : hasMobilePresentation
                ? _tabletFrame
                : _frames.first);
    final effect =
        ref.watch(largeScreenSettingsProvider.select((s) => s.musicEffect));
    final hasEffect = effect != LargeScreenMusicEffect.off;
    final liveSpectrum = effect == LargeScreenMusicEffect.spectrum &&
        ref.watch(
            playbackProvider.select((s) => s.phase == PlaybackPhase.online));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final previewHint = !hasEffect
        ? '修改会实时显示在预览中'
        : reduceMotion
            ? '系统已开启减少动态效果'
            : liveSpectrum
                ? '频谱预览使用当前播放的音频'
                : '动效预览使用示例节奏';
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('画面预览', style: theme.textTheme.titleSmall),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  ThmrMenuButton<(String, Size, bool)>(
                      tooltip: '预览比例',
                      initialValue: frame,
                      onSelected: (value) =>
                          setState(() => _selectedFrame = value),
                      itemBuilder: (_) => [
                            for (final choice in _frames)
                              PopupMenuItem(
                                  value: choice, child: Text(choice.$1)),
                          ],
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(frame.$1, style: theme.textTheme.labelMedium),
                            const Icon(Icons.expand_more, size: 18),
                          ]))),
                  if (widget.canExpand)
                    IconButton(
                        tooltip: '放大预览',
                        onPressed: () => LargeScreenPreview.open(context),
                        icon: const Icon(Icons.open_in_full, size: 18)),
                ]),
              ]),
          const SizedBox(height: 8),
          Flexible(
              fit: FlexFit.loose,
              child: _PreviewFrame(
                  size: frame.$2,
                  label: frame.$1,
                  phone: frame.$3,
                  demoRun: _demoRun,
                  liveSpectrum: liveSpectrum)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(previewHint,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.thmr.mutedInk)),
              if (hasEffect && !reduceMotion && !liveSpectrum)
                TextButton.icon(
                  onPressed: () => setState(() => _demoRun++),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('重播动效'),
                ),
            ],
          ),
        ]);
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame(
      {required this.size,
      required this.label,
      required this.phone,
      required this.demoRun,
      required this.liveSpectrum});
  final Size size;
  final String label;
  final bool phone;
  final int demoRun;
  final bool liveSpectrum;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, available) {
        final scale = math.min(
            available.maxWidth / size.width,
            available.hasBoundedHeight
                ? available.maxHeight / size.height
                : double.infinity);
        final media = MediaQuery.of(context).copyWith(
            size: size,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
            devicePixelRatio:
                (MediaQuery.devicePixelRatioOf(context) * scale).clamp(.2, 4));
        final stage = SizedBox.fromSize(
            size: size,
            child: MediaQuery(
                data: media,
                child: LargeScreenPlayer(
                    preview: true,
                    phonePreview: phone,
                    demoRun: demoRun,
                    liveSpectrumPreview: liveSpectrum)));
        return Align(
            alignment: Alignment.topCenter,
            widthFactor: 1,
            heightFactor: 1,
            child: SizedBox(
                key: const ValueKey('large-screen-preview-frame'),
                width: size.width * scale,
                height: size.height * scale,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: Theme.of(context).thmr.panelBorder)),
                    child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: ClipRect(
                            child: Semantics(
                                label: '大屏布局预览，$label',
                                image: true,
                                child: ExcludeSemantics(
                                    child: ExcludeFocus(
                                        child: IgnorePointer(
                                            child: FittedBox(
                                                fit: BoxFit.contain,
                                                child: stage))))))))));
      });
}
