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
}
