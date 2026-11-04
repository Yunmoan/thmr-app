import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/update/app_update.dart';

class ReleaseAdapter implements HttpClientAdapter {
  int requests = 0;
  int status = 200;
  Object? data = releaseJson('0.1.10');
  Completer<void>? gate;
  bool signResponse = true;
  RequestOptions? request;
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    request = options;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    final body = signResponse &&
            data is Map<String, dynamic> &&
            (data as Map)['program'] == 'THMR'
        ? await signTestRelease(data as Map<String, dynamic>)
        : data;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

const testUpdatePublicKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
final _testKey = Ed25519().newKeyPairFromSeed(List.generate(32, (i) => i));
Future<Map<String, dynamic>> signTestRelease(Map<String, dynamic> data) async {
  final payload = utf8.encode(jsonEncode(data));
  final signature = await Ed25519().sign(payload, keyPair: await _testKey);
  return {
    'schema': 1,
    'algorithm': 'ed25519',
    'payload': base64Encode(payload),
    'signature': base64Encode(signature.bytes)
  };
}

Map<String, dynamic> releaseJson(String version) => {
      'program': 'THMR',
      'version': version,
      'build_number': 2,
      'notes': '更新说明',
      'pub_date': '2026-11-04T00:00:00Z',
      'release_page': 'https://thmr.yunmoan.cn/download',
      'platforms': {
        for (final entry in {
          'windows-x86_64': 'zip',
          'darwin-aarch64': 'zip',
          'darwin-x86_64': 'zip',
          'linux-x86_64': 'tar.gz',
          'android-universal': 'apk',
        }.entries)
          entry.key: {
            'url':
                'https://staticassets.naids.com/thmr/$version/${entry.key}.${entry.value}',
            'sha256': 'a' * 64,
            'size': 3,
            'format': entry.value
          },
      },
    };
AppUpdateService serviceFor(ReleaseAdapter adapter) => AppUpdateService(
    client: Dio()..httpClientAdapter = adapter, publicKey: testUpdatePublicKey);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('client version uses the build identity and installed build number',
      () async {
    PackageInfo.setMockInitialValues(
      appName: 'THMR',
      packageName: 'cn.yunmoan.thmr',
      version: '0.8.4',
      buildNumber: '31',
      buildSignature: '',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect((await container.read(clientVersionProvider.future)).label,
        '${clientReleaseVersion.isEmpty ? '0.8.4' : clientReleaseVersion}+31');
  });

  test('release assets match each desktop and Android build', () async {
    final adapter = ReleaseAdapter();
    final release = (await serviceFor(adapter).latestRelease())!;
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.android,
    ]) {
      expect(release.downloadFor(platform), isNotNull);
    }
    expect(release.downloadFor(TargetPlatform.iOS), isNull);
    expect(adapter.request!.headers.containsKey('Authorization'), isFalse);
    expect(adapter.request!.uri.path, '/updater/thmr');
  });

  test('non-HTTPS download URLs are rejected even inside a signed manifest',
      () async {
    final data = releaseJson('0.2.0');
    (data['platforms'] as Map)['windows-x86_64']['url'] =
        'http://example.com/update.zip';
    final adapter = ReleaseAdapter()..data = data;
    await expectLater(serviceFor(adapter).latestRelease(),
        throwsA(isA<UpdateCheckException>()));
  });

  test('API mirror locations preserve signed binary identity and cached URLs',
      () async {
    final signed = await signTestRelease(releaseJson('0.2.0'));
    final adapter = ReleaseAdapter()
      ..signResponse = false
      ..data = {
        ...signed,
        'download_urls': {
          'windows-x86_64': 'https://mirror.example.com/THMR/windows.zip',
          'darwin-x86_64': 'https://mirror.example.com/THMR/macos.zip',
          'darwin-aarch64': 'https://mirror.example.com/THMR/macos.zip',
        }
      };
    final release = (await serviceFor(adapter).latestRelease())!;
    expect(
        release.artifactFor('windows-x86_64')!.url.host, 'mirror.example.com');
    expect(release.downloadFor(TargetPlatform.macOS)!.path, '/THMR/macos.zip');
    expect(release.downloadFor(TargetPlatform.linux)!.host,
        'staticassets.naids.com');
    expect(release.artifactFor('windows-x86_64')!.sha256, 'a' * 64);
    expect(release.artifactFor('windows-x86_64')!.size, 3);
    expect(release.identity, '0.2.0+2');
    expect(release.toJson()['payload'], signed['payload']);
    expect(release.toJson()['signature'], signed['signature']);
    adapter.data = jsonDecode(jsonEncode(release.toJson()));
    expect(
        (await serviceFor(adapter).latestRelease())!
            .downloadFor(TargetPlatform.windows),
        release.downloadFor(TargetPlatform.windows));
    adapter.data = {
      ...(adapter.data as Map<String, dynamic>),
      'payload': base64Encode(utf8.encode(jsonEncode(releaseJson('9.0.0'))))
    };
    await expectLater(serviceFor(adapter).latestRelease(),
        throwsA(isA<UpdateCheckException>()));
  });

  test('invalid or non-HTTPS mirror locations cannot enable a download',
      () async {
    final signed = await signTestRelease(releaseJson('0.2.0'));
    final adapter = ReleaseAdapter()..signResponse = false;
    for (final overrides in [
      [],
      {'windows-x86_64': 'http://mirror.example.com/a.zip'},
      {'windows-x86_64': 'https://user:secret@mirror.example.com/a.zip'},
      {'windows-x86_64': 'https://mirror.example.com/a.zip#fragment'},
      {'windows-x86_64': 42},
      {'unknown-platform': 'https://mirror.example.com/a.zip'},
    ]) {
      adapter.data = {...signed, 'download_urls': overrides};
      await expectLater(serviceFor(adapter).latestRelease(),
          throwsA(isA<UpdateCheckException>()));
    }
  });

  test('tampered metadata and missing pinned key cannot enable updates',
      () async {
    final signed = await signTestRelease(releaseJson('0.2.0'));
    final adapter = ReleaseAdapter()
      ..signResponse = false
      ..data = {
        ...signed,
        'payload': base64Encode(utf8.encode(jsonEncode(releaseJson('9.0.0'))))
      };
    await expectLater(serviceFor(adapter).latestRelease(),
        throwsA(isA<UpdateCheckException>()));
    await expectLater(
        AppUpdateService(
                client: Dio()..httpClientAdapter = adapter, publicKey: '')
            .latestRelease(),
        throwsA(isA<UpdateCheckException>()));
  });

  test('semantic versions compare numerically; build number is not an update',
      () async {
    final adapter = ReleaseAdapter();
    final controller = AppUpdateController(
      service: serviceFor(adapter),
      installedVersion: () async => const ClientVersion('0.1.2', '99'),
    );
    addTearDown(controller.dispose);
    await controller.check(manual: true);
    expect(controller.state.status, UpdateStatus.available);
    adapter.data = releaseJson('0.1.2');
    await controller.check(manual: true);
    expect(controller.state.status, UpdateStatus.current);
    expect(controller.state.release, isNull);
    adapter.data = releaseJson('0.1.1');
    await controller.check(manual: true);
    expect(controller.state.status, UpdateStatus.current);
  });

  test('a stable release updates an installed prerelease', () async {
    final controller = AppUpdateController(
      service: serviceFor(ReleaseAdapter()..data = releaseJson('0.2.0')),
      installedVersion: () async => const ClientVersion('0.2.0-rc.1', '1'),
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.state.status, UpdateStatus.available);
  });

  test('prereleases do not trigger stable updates', () async {
    final adapter = ReleaseAdapter()..data = releaseJson('0.2.0-beta.1');
    expect(await serviceFor(adapter).latestRelease(), isNull);
  });

  test('missing release is separate from rate limiting and invalid responses',
      () async {
    final adapter = ReleaseAdapter()..status = 204;
    final service = serviceFor(adapter);
    expect(await service.latestRelease(), isNull);
    for (final status in [403, 404, 429, 500]) {
      adapter.status = status;
      await expectLater(
          service.latestRelease(), throwsA(isA<UpdateCheckException>()));
    }
    adapter.status = 200;
    for (final data in [
      <Object>[],
      {'tag_name': 'not-a-version'}
    ]) {
      adapter.data = data;
      await expectLater(
          service.latestRelease(), throwsA(isA<UpdateCheckException>()));
    }
  });

  test('automatic checks honor preferences; manual checks override them',
      () async {
    SharedPreferences.setMockInitialValues({'appUpdate.autoCheck': false});
    final adapter = ReleaseAdapter();
    final controller = AppUpdateController(
      service: serviceFor(adapter),
      installedVersion: () async => const ClientVersion('0.1.2', '1'),
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(adapter.requests, 0);
    await controller.check(manual: true);
    expect(adapter.requests, 1);
    expect(controller.state.status, UpdateStatus.available);
  });

  test('24 hour throttle survives restarts without losing the update notice',
      () async {
    var now = DateTime(2026, 11, 4, 12);
    final adapter = ReleaseAdapter();
    AppUpdateController makeController() => AppUpdateController(
          service: serviceFor(adapter),
          installedVersion: () async => const ClientVersion('0.1.2', '1'),
          now: () => now,
        );
    final first = makeController();
    await first.check();
    expect(first.state.showNotice, isTrue);
    first.dispose();
    final second = makeController();
    addTearDown(second.dispose);
    await second.check();
    expect(adapter.requests, 1);
    expect(second.state.showNotice, isTrue);
    now = now.add(const Duration(hours: 24));
    await second.check();
    expect(adapter.requests, 2);
  });

  test('ignored version stays ignored across restarts; next version is shown',
      () async {
    final adapter = ReleaseAdapter();
    AppUpdateController makeController() => AppUpdateController(
          service: serviceFor(adapter),
          installedVersion: () async => const ClientVersion('0.1.2', '1'),
        );
    final first = makeController();
    await first.check();
    await first.ignoreRelease();
    first.dispose();
    final second = makeController();
    addTearDown(second.dispose);
    await second.ready;
    expect(second.state.showNotice, isFalse);
    await second.check(manual: true);
    expect(second.state.status, UpdateStatus.available);
    expect(second.state.showNotice, isFalse);
    adapter.data = releaseJson('0.2.0');
    await second.check(manual: true);
    expect(second.state.showNotice, isTrue);
  });

  test('failed check is retryable and does not record success', () async {
    final adapter = ReleaseAdapter()..status = 500;
    final controller = AppUpdateController(
      service: serviceFor(adapter),
      installedVersion: () async => const ClientVersion('0.1.2', '1'),
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.state.status, UpdateStatus.failed);
    expect(controller.state.lastChecked, isNull);
    adapter.status = 200;
    await controller.check(manual: true);
    expect(controller.state.status, UpdateStatus.available);
  });

  test('concurrent requests are coalesced and disposal is safe', () async {
    final adapter = ReleaseAdapter()..gate = Completer<void>();
    final controller = AppUpdateController(
      service: serviceFor(adapter),
      installedVersion: () async => const ClientVersion('0.1.2', '1'),
    );
    await controller.ready;
    final first = controller.check();
    final second = controller.check(manual: true);
    await adapter.started.future;
    expect(adapter.requests, 1);
    controller.dispose();
    adapter.gate!.complete();
    await Future.wait([first, second]);
  });
}
