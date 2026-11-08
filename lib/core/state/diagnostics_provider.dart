import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/diagnostics.dart';
import '../platform/client_version.dart';
import '../network/network_probe.dart';

export '../diagnostics/diagnostics.dart';

class DiagnosticsController extends StateNotifier<DiagnosticsSnapshot> {
  DiagnosticsController(
      {required this.version, DiagnosticsService Function()? serviceFactory})
      : serviceFactory = serviceFactory ?? DiagnosticsService.new,
        super(const DiagnosticsSnapshot());

  final Future<String> Function() version;
  final DiagnosticsService Function() serviceFactory;
  DiagnosticsService? _service;
  int _generation = 0;

  Future<void> run() async {
    if (state.running) return;
    final generation = ++_generation;
    final service = serviceFactory();
    _service = service;
    state = DiagnosticsSnapshot(startedAt: DateTime.now(), running: true);
    bool current() => mounted && generation == _generation;
    Future<void> environment() async {
      try {
        var installed = '未获取';
        try {
          installed = await version().timeout(const Duration(seconds: 3));
        } catch (_) {
          /* Environment information remains useful without a version. */
        }
        final values = await service
            .environment(installed)
            .timeout(const Duration(seconds: 5));
        if (current()) state = state.copyWith(environment: values);
      } catch (_) {
        if (current()) {
          state = state.copyWith(environment: {'本机环境': '读取失败，可重新诊断'});
        }
      }
    }

    Future<void> check(DiagnosticTarget target) async {
      NetworkProbeResult result;
      try {
        result = await service.check(target);
      } catch (_) {
        result = NetworkProbeResult(uri: Uri.parse(target.url), error: '检测失败');
      }
      if (current()) {
        state =
            state.copyWith(services: {...state.services, target.id: result});
      }
    }

    Future<void> ip() async {
      try {
        final location = await service.publicIp();
        if (current()) state = state.copyWith(ipLocation: location);
      } catch (_) {
        if (current()) state = state.copyWith(ipError: '公网 IP / 属地查询失败，可重新诊断');
      }
    }

    try {
      await Future.wait([
        environment(),
        ip(),
        for (final target in diagnosticTargets) check(target),
      ]);
    } finally {
      service.close();
      if (current()) {
        _service = null;
        state = state.copyWith(running: false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _service?.close();
    super.dispose();
  }
}

final diagnosticsProvider = StateNotifierProvider
    .autoDispose<DiagnosticsController, DiagnosticsSnapshot>(
        (ref) => DiagnosticsController(
              version: () async =>
                  (await ref.read(clientVersionProvider.future)).label,
            ));
