import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/app_update.dart';

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
          child: MaterialBanner(
            content: Text(update.status == UpdateStatus.ready
                ? '更新已就绪 v${update.release!.identity}'
                : update.status == UpdateStatus.downloading
                    ? '正在下载更新 ${(update.progress * 100).round()}%'
                    : '发现客户端新版本 v${update.release!.identity}'),
            forceActionsBelow: MediaQuery.sizeOf(context).width < 600,
            actions: [
              TextButton(
                onPressed: () =>
                    ref.read(appUpdateProvider.notifier).ignoreRelease(),
                child: const Text('忽略此版本'),
              ),
              TextButton(
                onPressed: () => showAppUpdate(context, update.release!),
                child: const Text('查看更新'),
              ),
            ],
          ),
        ),
      Expanded(child: widget.child),
    ]);
  }
}

class UpdatePanel extends ConsumerWidget {
  const UpdatePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!supportsAppUpdates) return const SizedBox.shrink();
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final message = switch (state.status) {
      UpdateStatus.idle => '从自有更新 API 检查客户端正式版本',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动检查更新'),
          subtitle: const Text('启动或返回应用时检查，每 24 小时最多检查一次'),
          value: state.autoCheck,
          onChanged: (value) => controller.setAutoCheck(value),
        ),
        SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动下载更新'),
            subtitle: const Text('发现新版本后在后台下载并校验，安装前会提示'),
            value: state.autoDownload,
            onChanged: (value) => controller.setAutoDownload(value)),
        if (state.status == UpdateStatus.downloading) ...[
          LinearProgressIndicator(value: state.progress),
          const SizedBox(height: 8)
        ],
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (state.error != null && state.status != UpdateStatus.failed)
          Text(state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (state.installNotice != null) Text(state.installNotice!),
        if (state.lastChecked != null) ...[
          const SizedBox(height: 4),
          Text('上次成功检查：${_formatTime(state.lastChecked!.toLocal())}',
              style: Theme.of(context).textTheme.labelSmall),
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
      ],
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
        return AlertDialog(
          title: Text('发现新版本 v${current.identity}'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(current.notes.trim().isEmpty
                      ? '该版本未提供更新说明。'
                      : current.notes),
                  const SizedBox(height: 16),
                  Text(artifact == null
                      ? '此版本暂未提供当前架构的安装包。'
                      : defaultTargetPlatform == TargetPlatform.android
                          ? '应用会下载并校验 APK，随后打开系统安装器。首次安装需在系统设置中允许此应用安装更新。'
                          : '应用会自动下载并校验更新包，点击安装后退出并替换程序，再自动重启。启动失败会恢复原版本。'),
                  if (state.status == UpdateStatus.downloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: state.progress),
                    Text(state.progress >= 1
                        ? '正在校验更新包…'
                        : '下载进度 ${(state.progress * 100).round()}%'),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    Text(state.error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))
                  ],
                  if (state.installNotice != null) Text(state.installNotice!),
                ],
              ))),
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
                  child: const Text('下载并自动更新')),
          ],
        );
      }),
    );

Future<void> _openUpdateLink(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {/* Report a missing browser handler below. */}
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开系统浏览器')));
  }
}
