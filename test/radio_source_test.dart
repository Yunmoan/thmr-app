import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/network/network_probe.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';

SourceMeasurement measurement(int index, int milliseconds,
        {int status = 200,
        String contentType = 'audio/mpeg',
        int bytes = 32768}) =>
    SourceMeasurement(
      radioSources[index],
      NetworkProbeResult(
        uri: Uri.parse(radioSources[index].baseUrl),
        statusCode: status,
        contentType: contentType,
        bytesRead: bytes,
        elapsed: Duration(milliseconds: milliseconds),
      ),
    );

class _Tester extends RadioSourceTester {
  _Tester(this.result);
  final Future<List<SourceMeasurement>> result;
  bool closed = false;
  String? measuredProfile;
  @override
  Future<List<SourceMeasurement>> measure(
      {String? stationId,
      String profileId = '128k',
      List<RadioSource>? sources}) {
    measuredProfile = profileId;
    return result;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _Radio extends Fake implements RadioApi {
  final statusResult = Completer<StationStatus>();
  @override
  Future<StationStatus> status(String stationId) => statusResult.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cold-start measurement waits for the enabled playback profile',
      () async {
    final radio = _Radio();
    final poller = StationPoller(radio, 'only320');
    addTearDown(poller.dispose);
    final tester = _Tester(Future.value([]));
    final controller = RadioSourceController(
        stationId: () => 'only320',
        profileForStation: (id) =>
            measurementProfile(id, '128k', poller.state, poller.stream),
        testerFactory: () => tester);
    addTearDown(controller.dispose);
    final testing = controller.ensureSelected();
    expect(tester.measuredProfile, isNull);
    radio.statusResult.complete(StationStatus.fromJson({
      'station': {
        'id': 'only320',
        'bitrates': [
          {'id': '128k', 'enabled': false},
          {'id': '320k'}
        ]
      }
    }));
    await testing;
    expect(tester.measuredProfile, '320k');
  });
  test('automatic selection compares successful complete audio samples',
      () async {
    final tester =
        _Tester(Future.value([measurement(0, 120), measurement(1, 65)]));
    final controller = RadioSourceController(testerFactory: () => tester);
    addTearDown(controller.dispose);
    await controller.ensureSelected();
    expect(controller.state.selected.id, RadioSourcePreference.source2);
    expect(controller.state.ready, isTrue);
    expect(controller.state.testing, isFalse);
    expect(tester.closed, isTrue);
    expect(
        fastestRadioSource([
          measurement(0, 1, status: 403),
          measurement(1, 50),
        ])?.id,
        RadioSourcePreference.source2);
    expect(
        fastestRadioSource([
          measurement(0, 1, contentType: 'text/html'),
          measurement(1, 50),
        ])?.id,
        RadioSourcePreference.source2);
    expect(
        fastestRadioSource([
          measurement(0, 1, bytes: 20),
          measurement(1, 50),
        ])?.id,
        RadioSourcePreference.source2);
  });

  test('automatic selection keeps the current source on noise-level margins',
      () async {
    final controller = RadioSourceController(
        testerFactory: () => _Tester(
            Future.value([measurement(0, 1200), measurement(1, 1150)])));
    addTearDown(controller.dispose);
    await controller.ensureSelected();
    // 播放源 2 的探测用时仅少约 4%，达不到切换并重连的阈值。
    expect(controller.state.selected.id, RadioSourcePreference.source1);
    expect(controller.state.tested, isTrue);
  });

  test('a small improvement also retains source two when it is current', () {
    expect(
        chooseRadioSource(
                [measurement(0, 600), measurement(1, 640)], radioSources[1])
            .id,
        RadioSourcePreference.source2);
  });

  test('a speed test leaves a manually selected source unchanged', () async {
    final controller = RadioSourceController(
        preference: RadioSourcePreference.source1,
        testerFactory: () =>
            _Tester(Future.value([measurement(0, 120), measurement(1, 65)])));
    addTearDown(controller.dispose);
    await controller.testSources();
    expect(controller.state.selected.id, RadioSourcePreference.source1);
    expect(controller.state.measurements, hasLength(2));
  });

  test('manual selection wins over a late automatic measurement', () async {
    final pending = Completer<List<SourceMeasurement>>();
    final tester = _Tester(pending.future);
    final controller = RadioSourceController(testerFactory: () => tester);
    addTearDown(controller.dispose);
    final test = controller.ensureSelected();
    controller.setPreference(RadioSourcePreference.source1);
    pending.complete([measurement(0, 120), measurement(1, 65)]);
    await test;
    expect(controller.state.preference, RadioSourcePreference.source1);
    expect(controller.state.selected.id, RadioSourcePreference.source1);
    expect(controller.state.testing, isFalse);
    expect(tester.closed, isTrue);
  });

  test('failed measurements permit a manual retry with the current source',
      () async {
    final controller = RadioSourceController(
        testerFactory: () => _Tester(Future.value(
            [measurement(0, 10, status: 503), measurement(1, 10, bytes: 0)])));
    addTearDown(controller.dispose);
    await controller.ensureSelected();
    expect(controller.state.ready, isTrue);
    expect(controller.state.notice, isNotNull);
    expect(controller.state.selected.id, RadioSourcePreference.source1);
  });

  test(
      'source preference defaults to automatic and survives controller restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = SettingsController();
    await first.ready;
    expect(first.state.radioSource, RadioSourcePreference.automatic);
    await first.setRadioSource(RadioSourcePreference.source2);
    first.dispose();
    final second = SettingsController();
    addTearDown(second.dispose);
    await second.ready;
    expect(second.state.radioSource, RadioSourcePreference.source2);
    expect(second.state.copyWith(autoPlay: true).radioSource,
        RadioSourcePreference.source2);
  });

  test('changing the stream origin preserves quality and token', () {
    expect(
        retargetRadioUrl(
            'https://radio.yunmoan.cn/radio/touhou/320k?token=secret',
            'https://radio.zyghit.cn'),
        'https://radio.zyghit.cn/radio/touhou/320k?token=secret');
  });
}
