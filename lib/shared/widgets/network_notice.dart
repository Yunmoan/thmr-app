import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import 'thmr_panel.dart';

class OfflineCacheBanner extends StatelessWidget {
  const OfflineCacheBanner(
      {super.key, required this.savedAt, required this.onRetry});

  final DateTime? savedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final time = savedAt?.toLocal();
    final synced = time == null
        ? ''
        : ' · 上次同步 ${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return ThmrPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text('离线浏览缓存$synced · 修改需联网',
                maxLines: 2,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.mutedInk)),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class NetworkIssueView extends StatelessWidget {
  const NetworkIssueView({
    super.key,
    required this.onRetry,
    this.hasCache = false,
    this.networkFailure = true,
    this.message,
  });

  final VoidCallback onRetry;
  final bool hasCache;
  final bool networkFailure;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    networkFailure
                        ? Icons.wifi_off_rounded
                        : Icons.cloud_off_rounded,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 14),
                Text(networkFailure ? '网络连接不可用' : '暂时无法加载',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  message ??
                      (networkFailure
                          ? hasCache
                              ? '这部分内容还没有同步到本机。连接网络后重试。'
                              : '请检查网络连接。首次查看收藏需要联网同步。'
                          : '服务器暂时没有返回内容，请稍后重试。'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: tokens.mutedInk),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
