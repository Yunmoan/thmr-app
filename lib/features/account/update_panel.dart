import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/thmr_motion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/focus_outline.dart';
import '../../core/theme/thmr_colors.dart';
import '../../core/theme/thmr_theme.dart';
import '../../core/update/app_update.dart';
import '../../shared/markdown/markdown_view.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../large_screen/large_screen_controller.dart';

bool get supportsAppUpdates =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

/// 更新弹窗正文宽度与两侧内边距；进度带需要横贯弹窗，因此留白由内容自己处理。
const _updateBodyWidth = 460.0;
const _updateBodyPadding = 24.0;

/// 在 Navigator 下全局挂载一次，所有标签页都能收到更新提示。
class AppUpdateMonitor extends ConsumerStatefulWidget {
  const AppUpdateMonitor({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppUpdateMonitor> createState() => _AppUpdateMonitorState();
}

class _AppUpdateMonitorState extends ConsumerState<AppUpdateMonitor>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!supportsAppUpdates) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check());
  }

  void _check() {
    if (mounted) unawaited(ref.read(appUpdateProvider.notifier).check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsAppUpdates) return widget.child;
    final update = ref.watch(appUpdateProvider);
    final large = ref.watch(largeScreenProvider.select((s) => s.active));
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (update.showNotice && !large)
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _UpdateNotice(
                            update: update,
                            onIgnore: () => ref
                                .read(appUpdateProvider.notifier)
                                .ignoreRelease(),
                            onView: () =>
                                showAppUpdate(context, update.release!),
                          )))),
            )),
    ]);
  }
}

class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice(
      {required this.update, required this.onIgnore, required this.onView});
  final AppUpdateState update;
  final VoidCallback onIgnore;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (update.status) {
      UpdateStatus.ready => '更新已就绪',
      UpdateStatus.downloading => '正在下载更新 ${(update.progress * 100).round()}%',
      UpdateStatus.installing => '正在准备安装…',
      _ => '发现新版本',
    };
    final message = '$label · v${update.release!.version}';
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.labelLarge,
    );
    final view = TextButton(
        onPressed: onView, style: buttonStyle, child: const Text('查看更新'));
    final dismiss = IconButton(
      tooltip: '忽略此版本',
      onPressed: update.status == UpdateStatus.installing ? null : onIgnore,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: const EdgeInsets.all(8),
      iconSize: 18,
      icon: const Icon(Icons.close),
    );
    return Material(
      key: const ValueKey('app-update-notice'),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 480 ||
                  MediaQuery.textScalerOf(context).scale(13) > 18;
              final text = Expanded(
                  child: Tooltip(
                message: '$label · v${update.release!.identity}',
                child: Text(message,
                    maxLines: narrow ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontSize: 13, height: 1.4)),
              ));
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Icon(
                      update.status == UpdateStatus.ready
                          ? Icons.task_alt
                          : Icons.system_update_alt,
                      size: 18,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  text,
                  const SizedBox(width: 8),
                  if (!narrow) view,
                  dismiss,
                ]),
                if (narrow)
                  Align(alignment: Alignment.centerRight, child: view),
              ]);
            }),
          ),
          SizedBox(
              height: 2,
              child: update.status == UpdateStatus.downloading
                  ? LinearProgressIndicator(
                      value: update.progress, minHeight: 2)
                  : null),
        ]),
      ),
    );
  }
}

class UpdatePanel extends ConsumerWidget {
  const UpdatePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!supportsAppUpdates) return const SizedBox.shrink();
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final titleStyle = theme.textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600, color: tokens.ink);
    final captionStyle =
        theme.textTheme.labelSmall?.copyWith(color: tokens.mutedInk);
    final message = switch (state.status) {
      UpdateStatus.idle => '检查并获取最新正式版本',
      UpdateStatus.checking => '正在检查更新…',
      UpdateStatus.available => '发现新版本 v${state.release!.identity}',
      UpdateStatus.current => '当前已是最新版本',
      UpdateStatus.noRelease => '暂无已发布的正式版本',
      UpdateStatus.failed => state.error ?? '检查更新失败，请重试',
      UpdateStatus.downloading => state.progress >= 1
          ? '正在校验更新包…'
          : '正在下载更新 ${(state.progress * 100).round()}%',
      UpdateStatus.ready => '更新已就绪，可立即安装',
      UpdateStatus.installing => '正在准备安装更新…',
    };
    return ThmrPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.update_rounded, size: 20, color: tokens.mutedInk),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自动检查更新', style: titleStyle),
                Text('启动或返回应用时检查，每 24 小时最多检查一次', style: captionStyle),
              ],
            )),
            FocusOutline(
                child: Switch(
              value: state.autoCheck,
              onChanged: (value) => controller.setAutoCheck(value),
            )),
          ]),
          const Divider(height: 22),
          Row(children: [
            Icon(Icons.download_outlined, size: 20, color: tokens.mutedInk),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自动下载更新', style: titleStyle),
                Text('发现新版本后在后台下载并校验，安装前会提示', style: captionStyle),
              ],
            )),
            FocusOutline(
                child: Switch(
                    value: state.autoDownload,
                    onChanged: (value) => controller.setAutoDownload(value))),
          ]),
          const Divider(height: 22),
          if (state.status == UpdateStatus.downloading) ...[
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 8)
          ],
          Text(message,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: state.status == UpdateStatus.failed
                      ? theme.colorScheme.error
                      : tokens.ink)),
          if (state.error != null && state.status != UpdateStatus.failed)
            Text(state.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          if (state.installNotice != null)
            Text(state.installNotice!,
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink)),
          if (state.lastChecked != null) ...[
            const SizedBox(height: 4),
            Text('上次成功检查：${_formatTime(state.lastChecked!.toLocal())}',
                style: captionStyle),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : () async {
                      await controller.check(manual: true);
                      if (!context.mounted) return;
                      final result = ref.read(appUpdateProvider);
                      if (result.release != null) {
                        await showAppUpdate(context, result.release!);
                      }
                    },
              icon: const Icon(Icons.system_update_alt_rounded, size: 18),
              label:
                  Text(state.status == UpdateStatus.checking ? '检查中…' : '检查更新'),
            ),
            if (state.release != null)
              TextButton(
                onPressed: () => showAppUpdate(context, state.release!),
                child: const Text('查看更新'),
              ),
          ]),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

String _formatTime(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

Future<void> showAppUpdate(BuildContext context, AppRelease release) =>
    showThmrDialog<void>(
      animationStyle: ThmrMotion.style(context),
      context: context,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final state = ref.watch(appUpdateProvider);
        final controller = ref.read(appUpdateProvider.notifier);
        final current = state.release ?? release;
        final artifact = current.artifactFor();
        final theme = Theme.of(context);
        final ready = state.status == UpdateStatus.ready;
        final installing = state.status == UpdateStatus.installing;
        final downloading = state.status == UpdateStatus.downloading;
        final progress = _updateProgressFor(state);
        final title = state.error != null
            ? '更新未完成'
            : installing
                ? '正在准备安装'
                : downloading
                    ? '正在下载更新'
                    : ready
                        ? '更新已就绪'
                        : '发现新版本';
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          contentPadding: EdgeInsets.zero,
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(children: [
            Icon(
                state.error != null
                    ? Icons.error_outline
                    : ready
                        ? Icons.task_alt
                        : Icons.system_update_alt,
                size: 22,
                color: state.error != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontSize: 20, fontWeight: FontWeight.w600))),
          ]),
          content: SizedBox(
              // 正文宽度加上两侧内边距后与弹窗同宽。
              width: _updateBodyWidth + _updateBodyPadding * 2,
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .55),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                                _updateBodyPadding, 0, _updateBodyPadding, 8),
                            child: _UpdateDetails(
                                release: current,
                                artifact: artifact,
                                state: state)),
                      ),
                      if (progress != null)
                        _UpdateProgressBar(
                            value: progress.value, label: progress.label),
                    ],
                  ))),
          actions: [
            TextButton(
                onPressed: state.status == UpdateStatus.installing
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('稍后')),
            TextButton(
                onPressed: () => _openExternalLink(context, current.pageUrl),
                child: const Text('发布页')),
            if (state.status == UpdateStatus.downloading)
              TextButton(
                  onPressed: controller.cancelDownload,
                  child: const Text('取消下载'))
            else if (state.status == UpdateStatus.ready ||
                state.status == UpdateStatus.installing)
              FilledButton(
                  onPressed: state.status == UpdateStatus.installing
                      ? null
                      : controller.installUpdate,
                  child: Text(state.status == UpdateStatus.installing
                      ? '准备安装…'
                      : defaultTargetPlatform == TargetPlatform.android
                          ? '安装更新'
                          : '安装并重启'))
            else if (artifact != null)
              FilledButton(
                  onPressed: state.busy ? null : controller.downloadUpdate,
                  child: Text(state.error != null ? '重新下载' : '下载更新')),
          ],
        );
      }),
    );

class _UpdateProgress {
  const _UpdateProgress(this.label, this.value);

  final String label;

  /// 为 null 表示不确定进度，显示流动动画和状态文字。
  final double? value;
}

/// 进度带只在下载、校验和准备安装时出现。
_UpdateProgress? _updateProgressFor(AppUpdateState state) {
  switch (state.status) {
    case UpdateStatus.downloading:
      if (state.progress >= 1) {
        return const _UpdateProgress('正在校验更新包…', null);
      }
      final progress = state.progress.clamp(0.0, 1.0).toDouble();
      return _UpdateProgress('${(progress * 100).round()}%', progress);
    case UpdateStatus.installing:
      return const _UpdateProgress('正在准备安装…', null);
    default:
      return null;
  }
}

/// 横贯弹窗底部的细进度条。
///
/// 横带只有 3px 细线高；百分比文字直接压在线上，文字下的弹窗同色背景
/// 会把细线和重叠的正文/按钮内容挡住，形成挖空效果。
/// [value] 为 null 时显示不定态动画和状态文字。
class _UpdateProgressBar extends StatelessWidget {
  const _UpdateProgressBar({required this.label, required this.value});

  final String label;
  final double? value;

  static const _barThickness = 3.0;
  // 文字周围留出的同色背景边距，以及文字尾部保留的填充长度。
  static const _labelGap = 4.0;
  static const _labelVerticalGap = 2.0;
  static const _fillTail = 8.0;
  static const _bandKey = ValueKey('update-progress');
  static const _fillKey = ValueKey('update-progress-fill');
  static const _backdropKey = ValueKey('update-progress-backdrop');
  static const _labelKey = ValueKey('update-progress-label');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final textScaler = MediaQuery.textScalerOf(context);
    final textStyle =
        (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontSize: 11,
      height: 1,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final indeterminate = value == null;
    final labelStyle = textStyle.copyWith(
        color: indeterminate
            ? tokens.ink
            : ThmrColors.textAccent(
                theme.colorScheme.primary, theme.colorScheme.surface));
    final labelWidth = _measureLabel(context, labelStyle);
    final labelHeight = textScaler.scale(11);
    const height = _barThickness;
    final labelTop = (height - labelHeight) / 2;
    final labelWidget = Text(
      label,
      key: _labelKey,
      style: labelStyle,
      maxLines: 1,
      softWrap: false,
    );
    final track = Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: double.infinity,
        height: _barThickness,
        child: ColoredBox(color: tokens.panelBorder),
      ),
    );

    // 弹窗同色背景：既挖空细线，也挡住和文字重叠的正文/按钮内容。
    Widget backdropAt(double left) => Positioned(
          left: math.max(0.0, left - _labelGap),
          top: labelTop - _labelVerticalGap,
          width: labelWidth + _labelGap * 2,
          height: labelHeight + _labelVerticalGap * 2,
          child: ColoredBox(
            key: _backdropKey,
            color: theme.colorScheme.surface,
          ),
        );

    Widget labelAt(double left) => Positioned(
          left: left,
          top: labelTop,
          child: labelWidget,
        );

    return Semantics(
      container: true,
      label: '更新进度',
      value: label,
      child: ExcludeSemantics(
        child: SizedBox(
          key: _bandKey,
          width: double.infinity,
          height: height,
          child: indeterminate
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final left = _clampLabelLeft(
                        width - 8 - labelWidth, width, labelWidth);
                    return Stack(clipBehavior: Clip.none, children: [
                      track,
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: _barThickness,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      backdropAt(left),
                      labelAt(left),
                    ]);
                  },
                )
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                      begin: 0, end: value!.clamp(0.0, 1.0).toDouble()),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final fillWidth = width * progress;
                        final left = _clampLabelLeft(
                            fillWidth - _fillTail - _labelGap - labelWidth,
                            width,
                            labelWidth);
                        return Stack(clipBehavior: Clip.none, children: [
                          track,
                          Positioned(
                            left: 0,
                            top: 0,
                            width: fillWidth,
                            height: _barThickness,
                            child: ColoredBox(
                              key: _fillKey,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          backdropAt(left),
                          labelAt(left),
                        ]);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// 文字左边界：优先贴住填充尾部，空间不足时退回左侧 8px 处。
  double _clampLabelLeft(double ideal, double width, double labelWidth) {
    final maxLeft = math.max(8.0, width - 8 - labelWidth);
    return ideal.clamp(8.0, maxLeft).toDouble();
  }

  /// 用与渲染一致的字体缩放测量文字宽度，保证挖空位置准确。
  double _measureLabel(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// 弹窗中可滚动的主体：版本信息、更新说明和安装状态。
class _UpdateDetails extends StatelessWidget {
  const _UpdateDetails({
    required this.release,
    required this.artifact,
    required this.state,
  });

  final AppRelease release;
  final UpdateArtifact? artifact;
  final AppUpdateState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artifact = this.artifact;
    final ready = state.status == UpdateStatus.ready;
    final installing = state.status == UpdateStatus.installing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 12, runSpacing: 4, children: [
          Text('v${release.version}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text('构建 ${release.buildNumber}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (artifact != null)
            Text('${(artifact.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 16),
        // 更新说明通常自带 Markdown 标题，不再重复「更新内容」标签。
        _UpdateNotes(notes: release.notes),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Text(
            artifact == null
                ? '此版本暂未提供当前架构的安装包。'
                : installing
                    ? '正在准备安装，请留意系统的授权提示。'
                    : ready
                        ? '更新包已下载并通过校验。安装后将自动重启应用。'
                        : '下载完成并校验后，即可安装更新。',
            style: theme.textTheme.bodySmall),
        if (artifact != null &&
            defaultTargetPlatform == TargetPlatform.windows) ...[
          const SizedBox(height: 6),
          Text('需要管理员权限时，Windows 会请求授权。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: .06),
                  border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: .25)),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(state.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error))),
        ],
        if (state.installNotice != null) Text(state.installNotice!),
      ],
    );
  }
}

/// 更新说明使用轻量 Markdown 渲染，链接交给系统浏览器打开。
class _UpdateNotes extends StatelessWidget {
  const _UpdateNotes({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownView(
      data: notes,
      emptyText: '该版本未提供更新说明。',
      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.6),
      onLinkTap: (url) => unawaited(_openExternalLink(context, url)),
    );
  }
}

Future<void> _openExternalLink(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {/* 由下方逻辑提示无法打开浏览器。 */}
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showThmrSnackBar(context, const SnackBar(content: Text('无法打开系统浏览器')));
  }
}
