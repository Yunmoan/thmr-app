import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/network/network_probe.dart';
import '../../core/state/diagnostics_provider.dart';
import '../../core/state/radio_source_provider.dart';
import '../../core/state/settings_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';

typedef DiagnosticReportSaver = Future<String?> Function(
    String text, String filename);

Uint8List diagnosticReportBytes(String text) =>
    Uint8List.fromList(utf8.encode('\uFEFF$text'));

final diagnosticReportSaverProvider = Provider<DiagnosticReportSaver>(
    (ref) => (text, filename) => FilePicker.saveFile(
          dialogTitle: '保存 THMR 网络诊断报告',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['txt'],
          bytes: diagnosticReportBytes(text),
          lockParentWindow: true,
        ));

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(ref.read(diagnosticsProvider.notifier).run());
    });
  }

  Future<void> _export() async {
    final snapshot = ref.read(diagnosticsProvider);
    if (_saving || snapshot.running || snapshot.startedAt == null) return;
    setState(() => _saving = true);
    try {
      final source = ref.read(radioSourceProvider);
      final profile =
          ref.read(settingsProvider).bitrateFor(appConfig.stationId);
      final screen = MediaQuery.of(context);
      final text = snapshot.toText(playback: {
        '选择模式': source.preference.label,
        '当前播放源':
            '${source.selected.label} · ${publicUrl(Uri.parse(source.selected.baseUrl))}',
        '电台': appConfig.stationId,
        '音质偏好': profile.isEmpty ? '电台默认' : profile,
        if (source.testedAt != null)
          '最近测速': source.testedAt!.toLocal().toIso8601String(),
        for (final measurement in source.measurements)
          '${measurement.source.label}测速': measurement.usable
              ? '${measurement.probe.elapsed.inMilliseconds} ms / 32 KiB'
              : measurement.probe.statusLabel,
      }, display: {
        '窗口逻辑尺寸':
            '${screen.size.width.toStringAsFixed(0)} × ${screen.size.height.toStringAsFixed(0)}',
        '像素倍率': screen.devicePixelRatio.toStringAsFixed(2),
      });
      final stamp = DateTime.now()
          .toIso8601String()
          .split('.')
          .first
          .replaceAll(RegExp(r'[:T]'), '-');
      final saved = await ref.read(diagnosticReportSaverProvider)(
          text, 'thmr-diagnostics-$stamp.txt');
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('诊断报告已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('报告保存失败，请检查保存位置后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(diagnosticsProvider);
    final tokens = Theme.of(context).thmr;
    final connected =
        data.services.values.where((result) => result.reachable).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('网络诊断'),
        backgroundColor: tokens.solidPanel.withValues(alpha: 0.94),
        actions: [
          IconButton(
              tooltip: '重新诊断',
              onPressed: data.running
                  ? null
                  : () => ref.read(diagnosticsProvider.notifier).run(),
              icon: const Icon(Icons.refresh_rounded)),
          IconButton(
              tooltip: '导出 TXT',
              onPressed: data.running || data.startedAt == null || _saving
                  ? null
                  : _export,
              icon: const Icon(Icons.download_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: SelectionArea(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          ThmrPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(data.running ? '正在检查连接…' : '诊断结果',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text('$connected / ${diagnosticTargets.length} 个服务已连通',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: tokens.mutedInk)),
                    ]),
                const SizedBox(height: 8),
                Text('检查服务连接、CDN 对端与本机环境。检测结果反映本次请求，不代表持续可用性。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.mutedInk)),
                if (data.startedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        '检测时间：${data.startedAt!.toLocal().toString().split('.').first}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: tokens.mutedInk)),
                  ),
                if (data.running)
                  const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: LinearProgressIndicator()),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: data.running
                          ? null
                          : () => ref.read(diagnosticsProvider.notifier).run(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重新诊断')),
                  FilledButton.tonalIcon(
                      onPressed:
                          data.running || data.startedAt == null || _saving
                              ? null
                              : _export,
                      icon: const Icon(Icons.save_alt_rounded, size: 18),
                      label: Text(_saving ? '正在保存…' : '导出 TXT')),
                ]),
                const SizedBox(height: 8),
                Text('TXT 包含本页检测结果和 IP 信息，可选择保存位置。',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: tokens.mutedInk)),
              ])),
          const SizedBox(height: 18),
          const SectionHeader(title: 'IP 与网络环境'),
          ThmrPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _Detail(
                    '公网 IP',
                    data.ipLocation?.ip ??
                        data.ipError ??
                        (data.running ? '查询中…' : '未获取')),
                _Detail('IP 属地', data.ipLocation?.description ?? '未获取'),
                const _Detail('查询服务', 'myip.ipip.net/json'),
                if (data.environment['本机 IP / 网络接口'] != null)
                  _Detail('本机 IP / 网络接口', data.environment['本机 IP / 网络接口']!),
              ])),
          const SizedBox(height: 18),
          const SectionHeader(title: '服务可访问性'),
          Text('连接 IP 为本次实际对端。CDN 未公开节点名称时，展示连接 IP、缓存状态和请求标识。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.mutedInk)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final target in diagnosticTargets)
                SizedBox(
                    width: width,
                    child: _ServiceCard(
                        target: target,
                        result: data.services[target.id],
                        running: data.running)),
            ]);
          }),
          const SizedBox(height: 18),
          const SectionHeader(title: '本机环境与内存'),
          ThmrPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (data.environment.isEmpty)
                  Text(data.running ? '正在读取本机环境…' : '未获取'),
                for (final entry in data.environment.entries)
                  if (entry.key != '本机 IP / 网络接口')
                    _Detail(entry.key, entry.value),
              ])),
        ],
      )),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard(
      {required this.target, required this.result, required this.running});
  final DiagnosticTarget target;
  final NetworkProbeResult? result;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final value = result;
    final color = value == null
        ? tokens.mutedInk
        : value.reachable
            ? Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff72cfa0)
                : const Color(0xff267b54)
            : Theme.of(context).colorScheme.error;
    return ThmrPanel(
        frost: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                value == null
                    ? Icons.more_horiz_rounded
                    : value.reachable
                        ? Icons.check_circle_outline_rounded
                        : Icons.info_outline_rounded,
                color: color,
                size: 21),
            const SizedBox(width: 8),
            Expanded(
                child: Text(target.name,
                    style: Theme.of(context).textTheme.titleSmall)),
          ]),
          const SizedBox(height: 7),
          Text(target.url,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.mutedInk)),
          const SizedBox(height: 9),
          Text(value?.statusLabel ?? (running ? '检测中…' : '未完成'),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          if (value != null) ...[
            const Divider(height: 20),
            if (value.uri.toString() != target.url)
              _Detail('检测地址', publicUrl(value.uri)),
            _Detail('响应耗时', '${value.elapsed.inMilliseconds} ms'),
            _Detail('实际连接 IP', value.remoteAddress ?? '未获取'),
            if (value.remotePort != null)
              _Detail('连接端口', '${value.remotePort}'),
            _Detail(
                'DNS 地址',
                value.dnsAddresses.isEmpty
                    ? '未获取'
                    : value.dnsAddresses.join('\n')),
            for (final entry in value.headers.entries)
              _Detail(entry.key, entry.value),
          ],
        ]));
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final caption = Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.mutedInk));
            final content =
                Text(value, style: Theme.of(context).textTheme.bodySmall);
            if (constraints.maxWidth < 430) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [caption, const SizedBox(height: 3), content]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 155, child: caption),
              const SizedBox(width: 12),
              Expanded(child: content),
            ]);
          },
        ));
  }
}
