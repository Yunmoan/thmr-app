import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/features/collections/shared_collection_screen.dart';

void main() {
  test('official share URL and bare code resolve to the same slug', () {
    expect(parseShareSlug('abc_12-XY'), 'abc_12-XY');
    expect(parseShareSlug('https://thmr.yunmoan.cn/share/abc_12-XY?x=1'),
        'abc_12-XY');
    expect(parseShareSlug('/share/abc_12-XY'), 'abc_12-XY');
  });

  test('invalid or unrelated links never reach the collection API', () {
    expect(parseShareSlug(''), isNull);
    expect(parseShareSlug('https://example.com/share/abc'), isNull);
    expect(parseShareSlug('https://thmr.yunmoan.cn/not-share/abc'), isNull);
    expect(parseShareSlug('abc/def'), isNull);
  });

  test('public share response without account-only share field parses', () {
    final payload = <String, dynamic>{
      'collection': <dynamic, dynamic>{
        'name': '用户的收藏',
        'description': '个人收藏夹',
        'owner': 'Yunmoan',
        'itemCount': 1,
      },
      'items': [
        <dynamic, dynamic>{
          'id': '8',
          'stationId': 'touhou',
          'trackId': 'afd0963e1e17ead3',
          'position': 1,
          'title': 'Special Smile',
          'artist': '築山さえ',
          'album': 'Special Smile',
          'durationSec': 350,
          'coverUrl': 'http://radio.yunmoan.cn/cover',
        },
      ],
    };

    final (collection, items) = parseSharedCollection(payload);
    expect(collection.name, '用户的收藏');
    expect(collection.itemCount, 1);
    expect(collection.share.enabled, isFalse);
    expect(items.single.title, 'Special Smile');
  });
}
