import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/state/session_store.dart';

class _LostWrite extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

void main() {
  const store = SessionStore();
  final legacy = {
    'thmr_session_token': 'legacy-token',
    'thmr_cached_user_v1': jsonEncode({'id': 'old', 'token': 'legacy-token'}),
    'unrelated': 'keep',
  };
  test(
      'migration verifies both token and offline user before clearing legacy data',
      () async {
    SharedPreferences.setMockInitialValues(legacy);
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
        SessionStore(storage: _LostWrite()).read(), throwsStateError);
    expect(prefs.getString('thmr_session_token'), 'legacy-token');
    expect(
        prefs.getString('thmr_cached_user_v1'), legacy['thmr_cached_user_v1']);
    expect((await store.read())?.user?.id, 'old');
    expect(prefs.getKeys(), {'unrelated'});
    expect((await store.read())?.token, 'legacy-token');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test(
      'a secure session wins over stale preferences after an interrupted migration',
      () async {
    SharedPreferences.setMockInitialValues({});
    await store.save('new-token', null);
    SharedPreferences.setMockInitialValues(legacy);
    expect((await store.read())?.token, 'new-token');
    expect((await SharedPreferences.getInstance()).getKeys(), {'unrelated'});
  });

  test(
      'an old snapshot from a different session never becomes the offline user',
      () async {
    SharedPreferences.setMockInitialValues(
        {...legacy, 'thmr_session_token': 'another-token'});
    final saved = await store.read();
    expect(saved?.token, 'another-token');
    expect(saved?.user, isNull);
  });
}
