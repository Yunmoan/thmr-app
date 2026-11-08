import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/thmr_theme.dart';
import '../../core/update/app_update.dart';
import '../../shared/widgets/thmr_panel.dart';

bool get supportsAppUpdates =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

/// Mounted once under the Navigator so update notices work on every tab.
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
    return Column(children: [
      if (update.showNotice)
        SafeArea(
          bottom: false,
          child: _UpdateNotice(
            update: update,
            onIgnore: () =>
                ref.read(appUpdateProvider.notifier).ignoreRelease(),
            onView: () => showAppUpdate(context, update.release!),
          ),
        ),
      Expanded(child: widget.child),
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
          if (update.status == UpdateStatus.downloading)
            LinearProgressIndicator(value: update.progress, minHeight: 2),
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
            Switch(
              value: state.autoCheck,
              onChanged: (value) => controller.setAutoCheck(value),
            ),
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
            Switch(
                value: state.autoDownload,
                onChanged: (value) => controller.setAutoDownload(value)),
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
    showDialog<void>(
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
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
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
              width: 460,
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .55),
                  child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        Text('v${current.version}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text('构建 ${current.buildNumber}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                        if (artifact != null)
                          Text(
                              '${(artifact.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                      ]),
                      const SizedBox(height: 16),
                      Text('更新内容',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _UpdateNotes(notes: current.notes),
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
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      if (downloading || installing) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                            value: installing || state.progress >= 1
                                ? null
                                : state.progress,
                            minHeight: 3),
                        if (downloading)
                          Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                  state.progress >= 1
                                      ? '正在校验更新包…'
                                      : '${(state.progress * 100).round()}%',
                                  style: theme.textTheme.labelSmall)),
                      ],
                      if (state.error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: theme.colorScheme.error
                                    .withValues(alpha: .06),
                                border: Border.all(
                                    color: theme.colorScheme.error
                                        .withValues(alpha: .25)),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(state.error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error))),
                      ],
                      if (state.installNotice != null)
                        Text(state.installNotice!),
                    ],
                  )))),
          actions: [
            TextButton(
                onPressed: state.status == UpdateStatus.installing
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('稍后')),
            TextButton(
                onPressed: () => _openUpdateLink(context, current.pageUrl),
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
                  child: const Text('下载更新')),
          ],
        );
      }),
    );

class _UpdateNotes extends StatelessWidget {
  const _UpdateNotes({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontSize: 14, height: 1.6);
    final lines =
        notes.trim().isEmpty ? ['该版本未提供更新说明。'] : notes.trim().split('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RegExp(r'^\s*[-*]\s+').hasMatch(line)
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text('•  ', style: style),
                          Expanded(
                              child: SelectableText(
                                  line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''),
                                  style: style)),
                        ])
                  : SelectableText(line, style: style)),
    ]);
  }
}

Future<void> _openUpdateLink(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {/* Report a missing browser handler below. */}
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开系统浏览器')));
  }
}
