import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/api/radio_api.dart';

/// Shapes copied from the real `/api/stations/:id/status` payload: nested
/// JSON objects and a relative cover path.
const _statusJson = {
  'station': {
    'id': 'touhou',
    'name': '东方音乐电台',
    'enabled': true,
    'public': {
      'enabled': true,
      'title': '东方音乐电台',
      'description': 'fixture',
      'accentColor': '#c96a3d',
    },
    'streamAuthEnabled': false,
    'bitrates': [
      {
        'id': '128k',
        'bitrateKbps': 128,
        'sampleRate': 44100,
        'channels': 2,
        'enabled': true,
      },
    ],
  },
  'totals': {'listeners': 3, 'uniqueIps': 2},
  'current': {
    'trackId': 't-current',
    'title': '当前曲目',
    'artist': '社团',
    'coverUrl': '/covers/current.jpg',
    'startedAtMs': 1700000000000,
    'expectedEndMs': 1700000000200,
    'positionSec': 10,
    'durationSec': 200,
  },
  'previous': {
    'trackId': 't-previous',
    'title': '上一曲',
    'artist': '社团',
    'coverUrl': '/covers/previous.jpg',
  },
  'queue': [
    {
      'trackId': 't-next',
      'title': '下一曲',
      'artist': '社团',
      'coverUrl': '/covers/next.jpg',
      'plannedStartMs': 1700000000300,
      'plannedEndMs': 1700000000500,
      'durationSec': 200,
    },
  ],
};

const _playlistJson = {
  'queue': [
    {
      'trackId': 't-queue',
      'title': '队列曲目',
      'artist': '社团',
      'coverUrl': '/covers/queue.jpg',
      'plannedStartMs': 1700000001000,
      'plannedEndMs': 1700000001200,
      'durationSec': 200,
    },
  ],
};

const _stationListJson = [
  {'id': 'main', 'enabled': false, 'listeners': 0},
  {'id': 'touhou', 'enabled': true, 'listeners': 14, 'uniqueIps': 9},
  {'id': 'touhou-curated', 'enabled': true, 'listeners': 3, 'uniqueIps': 2},
];

const _yesterdayTrack = {
  'stationId': 'touhou-curated',
  'trackId': 't-history',
  'title': '昨日曲目',
  'artist': '社团',
  'coverUrl': '/api/stations/touhou-curated/tracks/t-history/cover',
};

const _yesterdayJson = {
  'collection': {'id': 'yesterday-touhou-curated', 'itemCount': 3},
  'items': [
    {..._yesterdayTrack, 'id': '1', 'position': 0, 'playedAtMs': 1794326700000},
    {
      'id': '2',
      'position': 1,
      'stationId': 'touhou-curated',
      'trackId': 't-other',
      'coverUrl': '',
    },
    {..._yesterdayTrack, 'id': '3', 'position': 2},
  ],
};

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      final json = switch (request.uri.path) {
        '/api/stations' => _stationListJson,
        '/api/stations/touhou/playlist' => _playlistJson,
        '/api/stations/touhou-curated/yesterday' => _yesterdayJson,
        '/api/stations/touhou/yesterday' => {'items': []},
        _ => _statusJson,
      };
      response.write(jsonEncode(json));
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('nested status JSON survives cover resolution and parses strictly',
      () async {
    final api = RadioApi(baseUrl: 'http://127.0.0.1:${server.port}');
    final status = await api.status('touhou');
    expect(status.station.id, 'touhou');
    expect(status.station.public?.title, '东方音乐电台');
    expect(status.station.enabledBitrates.single.id, '128k');
    expect(status.listeners, 3);
    expect(status.current?.title, '当前曲目');
    // Covers resolve against the selected source, not appConfig.
    expect(status.current?.coverUrl,
        'http://127.0.0.1:${server.port}/covers/current.jpg');
    expect(status.previous?.coverUrl,
        'http://127.0.0.1:${server.port}/covers/previous.jpg');
    expect(status.queue.single.coverUrl,
        'http://127.0.0.1:${server.port}/covers/next.jpg');
  });

  test('playlist queue entries parse with resolved covers', () async {
    final api = RadioApi(baseUrl: 'http://127.0.0.1:${server.port}');
    final queue = await api.playlist('touhou');
    expect(queue, hasLength(1));
    expect(queue.single.trackId, 't-queue');
    expect(queue.single.coverUrl,
        'http://127.0.0.1:${server.port}/covers/queue.jpg');
  });

  test('site listener total sums all Radio stations', () async {
    final api = RadioApi(baseUrl: 'http://127.0.0.1:${server.port}');
    expect(await api.siteListeners(), 17);
  });

  test('yesterday playlist preserves play order and resolves station covers',
      () async {
    final baseUrl = 'http://127.0.0.1:${server.port}';
    final api = RadioApi(baseUrl: baseUrl);
    final items = await api.yesterdayPlaylist('touhou-curated');

    expect(items.map((item) => item.id), ['1', '2', '3']);
    expect(items.map((item) => item.trackId), [
      't-history',
      't-other',
      't-history',
    ]);
    expect(items.first.stationId, 'touhou-curated');
    expect(items.first.playedAtMs, 1794326700000);
    expect(items[1].playedAtMs, isNull);
    expect(items.first.coverUrl, '$baseUrl${_yesterdayTrack['coverUrl']}');
    expect(items[1].coverUrl, isEmpty);
    expect(await api.yesterdayPlaylist('touhou'), isEmpty);
    await expectLater(api.yesterdayPlaylist('other'), throwsFormatException);
  });
}
