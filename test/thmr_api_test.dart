import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/collection_cache.dart';

void main() {
  test('only a valid empty catalog prunes the saved list and details',
      () async {
    final folder = {'id': 'one', 'name': '收藏'};
    Object catalog = [folder];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      final data = switch (request.uri.path) {
        '/api/auth/me' => {
            'user': {'id': 'account'}
          },
        '/api/me/collections' => catalog,
        _ => {'collection': folder, 'items': []},
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      request.response.close();
    });
    SharedPreferences.setMockInitialValues({'thmr_session_token': 'token'});
    final api = ThmrApi(baseUrl: 'http://127.0.0.1:${server.port}');
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthController(client: api)),
    ]);
    addTearDown(container.dispose);
    final ready = container.read(authProvider.notifier);
    await ready.stream.firstWhere((s) => s.initialized);
    const cache = CollectionCache();
    await cache.saveDetail('account', Collection.fromJson(folder), []);
    for (final valid in [
      [folder],
      {
        'collections': [folder]
      },
      {
        'data': [folder]
      }
    ]) {
      catalog = valid;
      expect(
          (await container.refresh(collectionsProvider.future))
              .collections
              .single
              .id,
          'one');
    }
    for (final invalid in [
      {'message': '维护中'},
      '维护中',
      {'data': null},
      [folder, {}]
    ]) {
      catalog = invalid;
      await expectLater(
          container.refresh(collectionsProvider.future), throwsFormatException);
      expect((await cache.readList('account'))?.collections.single.id, 'one');
      expect(await cache.readDetail('account', 'one'), isNotNull);
    }
    catalog = {'collections': []};
    expect((await container.refresh(collectionsProvider.future)).collections,
        isEmpty);
    expect((await cache.readList('account'))?.collections, isEmpty);
    expect(await cache.readDetail('account', 'one'), isNull);
  });

  test('reads the live config switch without matching commented values',
      () async {
    var config = '''
window.RADIO_PUBLIC_CONFIG = {
  baseUrl: "https://radio.test",
  features: { /* vote: false */ vote: true }
};
''';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/config.js');
      expect(request.headers.value(HttpHeaders.cacheControlHeader), 'no-cache');
      request.response.headers.contentType =
          ContentType('application', 'javascript');
      request.response.write(config);
      await request.response.close();
    });
    final api = ThmrApi(baseUrl: 'http://127.0.0.1:${server.port}');
    expect(await api.voteEnabled(), isTrue);

    config = '''
window.RADIO_PUBLIC_CONFIG = {
  "features": {
    // vote: true
    "vote": false
  }
};
''';
    expect(await api.voteEnabled(), isFalse);
  });
}
