import 'package:flutter_test/flutter_test.dart';

import 'package:thmr_app/core/models/models.dart';

void main() {
  test('StationStatus.from 解析核心字段(ID 一律字符串)', () {
    final status = StationStatus.fromJson({
      'station': {
        'id': 'main',
        'name': '东方音乐电台 THMR',
        'enabled': true,
        'public': {'enabled': true, 'accentColor': '#c65a69'},
        'streamAuthEnabled': false,
        'bitrates': [
          {'id': '96k', 'bitrateKbps': 96, 'enabled': true},
          {'id': '320k', 'bitrateKbps': 320, 'enabled': false},
        ],
      },
      'totals': {'listeners': 12, 'uniqueIps': 8},
      'current': {
        'trackId': 12345, // 后端偶发数字 → 应转字符串
        'title': 'Necro Fantasia',
        'artist': 'Alstroemeria Records',
        'coverUrl': '/api/stations/main/tracks/x/cover',
        'startedAtMs': 1758770000000,
        'expectedEndMs': 1758770200000,
        'positionSec': 30,
        'durationSec': 200,
      },
      'queue': <Object>[],
    });

    expect(status.current!.trackId, '12345');
    expect(status.listeners, 12);
    expect(status.station.enabledBitrates.map((p) => p.id), ['96k']);
    expect(
      absolutizeCover(status.current!.coverUrl, 'https://radio.yunmoan.cn'),
      'https://radio.yunmoan.cn/api/stations/main/tracks/x/cover',
    );
  });

  test('absolutizeCover:绝对 URL 与空串透传', () {
    expect(absolutizeCover('', 'https://r.example'), '');
    expect(
      absolutizeCover('https://a.example/c.jpg', 'https://r.example'),
      'https://a.example/c.jpg',
    );
  });
}
