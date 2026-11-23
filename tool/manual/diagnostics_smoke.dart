// Read-only smoke check against the production endpoints, with a local report.
import 'dart:io';

import 'package:thmr_app/core/diagnostics/diagnostics.dart';
import 'package:thmr_app/core/network/radio_sources.dart';

Future<void> main(List<String> args) async {
  final service = DiagnosticsService();
  final tester = RadioSourceTester();
  try {
    final environment = await service.environment('development smoke check');
    IpLocation? ip;
    String? ipError;
    try {
      ip = await service.publicIp();
    } catch (_) {
      ipError = '公网 IP 查询失败';
    }
    final services = Map.fromEntries(await Future.wait(diagnosticTargets.map(
        (target) async => MapEntry(target.id, await service.check(target)))));
    final sources = await tester.measure();
    final fastest = fastestRadioSource(sources);
    final snapshot = DiagnosticsSnapshot(
        startedAt: DateTime.now(),
        environment: environment,
        ipLocation: ip,
        ipError: ipError,
        services: services);
    final output =
        File(args.isEmpty ? 'build/diagnostics-smoke.txt' : args.first);
    await output.parent.create(recursive: true);
    await output.writeAsString(snapshot.toText(playback: {
      '自动选择': fastest?.label ?? '所有播放源均未通过测速',
      for (final source in sources)
        '${source.source.label}测速':
            '${source.probe.elapsed.inMilliseconds} ms, ${source.probe.bytesRead} bytes, audio=${source.probe.audio}, usable=${source.usable}',
    }));
    for (final target in diagnosticTargets) {
      stdout.writeln('${target.name}: ${services[target.id]!.statusLabel}');
    }
    stdout.writeln(
        'IP JSON: ${ip == null ? 'failed' : 'parsed'}; memory: ${environment['应用当前内存（RSS）']}');
    for (final source in sources) {
      stdout.writeln(
          '${source.source.label}: ${source.probe.elapsed.inMilliseconds} ms, '
          '${source.probe.bytesRead} bytes, usable=${source.usable}');
    }
    stdout.writeln(
        'Selected: ${fastest?.label}; local report: ${output.absolute.path}');
  } finally {
    service.close();
    tester.close();
  }
}
