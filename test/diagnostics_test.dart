import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/network/network_probe.dart';
import 'package:thmr_app/core/state/diagnostics_provider.dart';

class _Service extends DiagnosticsService {
  _Service({this.failIp = false, this.pending});
  final bool failIp;
  final Completer<void>? pending;
  bool closed = false;
  @override
  Future<Map<String, String>> environment(String clientVersion) async => {
        '客户端版本': clientVersion,
        '应用当前内存（RSS）': '123 MiB',
      };
  @override
  Future<IpLocation> publicIp() async {
    if (failIp) throw const FormatException('fixture');
    return const IpLocation('192.0.2.42', ['中国', '测试省', '测试市', '', '测试运营商']);
  }

  @override
  Future<NetworkProbeResult> check(DiagnosticTarget target) async {
    if (pending != null) await pending!.future;
    if (target.id == 'account') throw const FormatException('fixture');
    return NetworkProbeResult(
        uri: Uri.parse(target.url),
        statusCode: 200,
        remoteAddress: '192.0.2.123',
        elapsed: const Duration(milliseconds: 45),
        headers: const {
          'eo-cache-status': 'HIT',
          'eo-log-uuid': 'fixture-request'
        });
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test('parses the IPIP JSON schema without inventing location fields', () {
    final location = IpLocation.fromJson({
      'ret': 'ok',
      'data': {
        'ip': '192.0.2.42',
        'location': ['中国', '测试省', '测试市', '', '运营商'],
      }
    });
    expect(location.ip, '192.0.2.42');
    expect(location.description, '中国 · 测试省 · 测试市 · 运营商');
    for (final bad in [
      {'ret': 1, 'data': {}},
      {
        'ret': 0,
        'data': {'ip': 'not-an-ip', 'location': []}
      },
      {
        'ret': 0,
        'data': {'ip': '192.0.2.42', 'location': 'somewhere'}
      },
    ]) {
      expect(() => IpLocation.fromJson(bad), throwsFormatException);
    }
  });

  test('partial failures retain independent services and environment data',
      () async {
    final service = _Service(failIp: true);
    final controller = DiagnosticsController(
        version: () async => '0.1.5+1', serviceFactory: () => service);
    addTearDown(controller.dispose);
    await controller.run();
    expect(controller.state.running, isFalse);
    expect(controller.state.environment['客户端版本'], '0.1.5+1');
    expect(controller.state.services, hasLength(7));
    expect(controller.state.services['account']?.error, isNotNull);
    expect(controller.state.services['source1']?.successful, isTrue);
    expect(controller.state.ipError, isNotNull);
    expect(service.closed, isTrue);
  });

  test('a missing package version does not suppress device information',
      () async {
    final controller = DiagnosticsController(
        version: () async => throw StateError('plugin unavailable'),
        serviceFactory: () => _Service());
    addTearDown(controller.dispose);
    await controller.run();
    expect(controller.state.environment['应用当前内存（RSS）'], '123 MiB');
    expect(controller.state.environment['客户端版本'], '未获取');
  });

  test('leaving the page closes pending probes and ignores late results',
      () async {
    final pending = Completer<void>();
    final service = _Service(pending: pending);
    final controller = DiagnosticsController(
        version: () async => 'test', serviceFactory: () => service);
    final run = controller.run();
    controller.dispose();
    pending.complete();
    await run;
    expect(service.closed, isTrue);
  });

  test('the TXT report includes all targets, IP, CDN and memory results',
      () async {
    final controller = DiagnosticsController(
        version: () async => 'test', serviceFactory: () => _Service());
    addTearDown(controller.dispose);
    await controller.run();
    final text = controller.state.toText(playback: {'当前播放源': '源 2'});
    for (final target in diagnosticTargets) {
      expect(text, contains(target.url));
    }
    expect(text, contains('192.0.2.42'));
    expect(text, contains('123 MiB'));
    expect(text, contains('fixture-request'));
    expect(text, contains('源 2'));
    expect(text, contains('检测失败'));
  });
}
