import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';
import 'large_screen_player.dart';

const _frames = <(String, Size)>[
  ('16:9', Size(1280, 720)),
  ('16:10', Size(1280, 800)),
  ('4:3', Size(1024, 768)),
  ('9:16', Size(720, 1280)),
];

/// The actual stage at a virtual display size. It never owns the real window's
/// animation callbacks, audio controls, focus or pointer input.
class LargeScreenPreview extends StatefulWidget {
  const LargeScreenPreview({super.key, this.canExpand = true});
  final bool canExpand;

  static Future<void> open(BuildContext context) => showDialog<void>(
      context: context,
      animationStyle: ThmrMotion.style(context),
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
  State<LargeScreenPreview> createState() => _LargeScreenPreviewState();
}

class _LargeScreenPreviewState extends State<LargeScreenPreview> {
  int _frame = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frame = _frames[_frame];
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
                  PopupMenuButton<int>(
                      tooltip: '预览比例',
                      popUpAnimationStyle: ThmrMotion.style(context),
                      initialValue: _frame,
                      onSelected: (value) => setState(() => _frame = value),
                      itemBuilder: (_) => [
                            for (var i = 0; i < _frames.length; i++)
                              PopupMenuItem(
                                  value: i, child: Text(_frames[i].$1)),
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
              child: _PreviewFrame(size: frame.$2, label: frame.$1)),
          const SizedBox(height: 8),
          Text('修改会实时显示在预览中',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.thmr.mutedInk)),
        ]);
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.size, required this.label});
  final Size size;
  final String label;

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
                data: media, child: const LargeScreenPlayer(preview: true)));
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
