import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/station_provider.dart';

class _DelayedRadioApi extends RadioApi {
  final requests = <Completer<StationStatus>>[];

  @override
  Future<StationStatus> status(String stationId) {
    final request = Completer<StationStatus>();
    requests.add(request);
    return request.future;
  }
}

StationStatus _status(int listeners) => StationStatus(
      station: const StationInfo(
        id: 'main',
        name: 'THMR',
        enabled: true,
        public: null,
        streamAuthEnabled: false,
        bitrates: [],
      ),
      listeners: listeners,
      uniqueIps: listeners,
      current: null,
      previous: null,
      queue: const [],
    );

void main() {
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
}
