import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/config.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';

class _DelayedRadioApi extends RadioApi {
  final requests = <Completer<StationStatus>>[];
  final stationIds = <String>[];

  @override
  Future<StationStatus> status(String stationId) {
    stationIds.add(stationId);
    final request = Completer<StationStatus>();
    requests.add(request);
    return request.future;
  }
}

StationStatus _status(int listeners, {String id = 'main'}) => StationStatus(
      station: StationInfo(
        id: id,
        name: 'THMR',
        enabled: true,
        public: null,
        streamAuthEnabled: false,
        bitrates: const [
          StreamProfile(
              id: '320k',
              bitrateKbps: 320,
              sampleRate: 44100,
              channels: 2,
              enabled: true),
          StreamProfile(
              id: '128k',
              bitrateKbps: 128,
              sampleRate: 44100,
              channels: 2,
              enabled: true),
        ],
      ),
      listeners: listeners,
      uniqueIps: listeners,
      current: null,
      previous: null,
      queue: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a stale poll cannot replace a newer station status', () async {
    final api = _DelayedRadioApi();
    final poller = StationPoller(api, 'main');
    addTearDown(poller.dispose);

    final refresh = poller.refresh();
    api.requests[1].complete(_status(2));
    await refresh;
    expect(poller.state.status?.listeners, 2);

    api.requests[0].complete(_status(1));
    await Future<void>.delayed(Duration.zero);
    expect(poller.state.status?.listeners, 2);
  });

  test('a slow poll can show data while a newer poll is pending', () async {
    final api = _DelayedRadioApi();
    final poller = StationPoller(api, 'main');
    addTearDown(poller.dispose);

    final refresh = poller.refresh();
    api.requests[0].complete(_status(1));
    await Future<void>.delayed(Duration.zero);
    expect(poller.state.status?.listeners, 1);

    api.requests[1].complete(_status(2));
    await refresh;
    expect(poller.state.status?.listeners, 2);
  });

  test('a channel switch drops stale polls and uses the new bitrate preference',
      () async {
    final main = appConfig.stationId;
    const curated = 'touhou-curated';
    SharedPreferences.setMockInitialValues({
      'bitrateByStation': ['$main=320k', '$curated=128k'],
    });
    final api = _DelayedRadioApi();
    final container = ProviderContainer(overrides: [
      radioApiProvider.overrideWithValue(api),
      channelCatalogProvider.overrideWith((ref) async => [
            RadioChannel(id: main, name: '综合'),
            const RadioChannel(id: curated, name: '精选'),
          ]),
    ]);
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.ready;
    final listener = container.listen(streamUrlProvider, (_, __) {});
    addTearDown(listener.close);

    expect(api.stationIds, [main]);
    api.requests[0].complete(_status(12, id: main));
    await container.pump();
    expect(listener.read(), api.streamUrl(main, '320k'));

    final latePoll = container.read(stationProvider.notifier).refresh();
    await settings.selectStation(curated);
    await container.pump();
    expect(api.stationIds, [main, main, curated]);
    expect(listener.read(), isNull);
    expect(container.read(stationProvider).status, isNull);

    api.requests[2].complete(_status(3, id: curated));
    await container.pump();
    api.requests[1].complete(_status(99, id: main));
    await latePoll;
    expect(listener.read(), api.streamUrl(curated, '128k'));
    expect(container.read(stationProvider).status?.listeners, 3);
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.selectedStationId, curated);
  });
}
