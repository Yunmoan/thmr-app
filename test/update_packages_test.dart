import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/update/app_update.dart';
import 'package:thmr_app/core/update/update_packages.dart';

import 'app_update_test.dart' show ReleaseAdapter, serviceFor, releaseJson;

class _BytesAdapter implements HttpClientAdapter {
  List<int> bytes = [97, 98, 99];
  int requests = 0;
  bool fail = false;
  bool redirectInsecure = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    if (redirectInsecure) {
      return ResponseBody.fromBytes([], 302,
          headers: {
            'location': ['http://example.com/app.zip']
          });
    }
    if (fail) {
      return ResponseBody(
          Stream<Uint8List>.error(const SocketException('interrupted')), 200);
    }
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

AppRelease _release() => AppRelease(
        version: Version.parse('0.2.0'),
        buildNumber: 2,
        notes: '',
        pageUrl: Uri.parse('https://example.com/releases'),
        envelope: const {},
        artifacts: {
          'windows-x86_64': UpdateArtifact(
              url: Uri.parse('https://example.com/app.zip'),
              sha256: sha256.convert([97, 98, 99]).toString(),
              size: 3,
              format: 'zip')
        });

class _ControllerPackages extends UpdatePackageManager {
  int downloads = 0;
  int installs = 0;
  bool failInstall = false;
  bool invalidPackage = false;
  @override
  Future<File> download(
      AppRelease release, void Function(double) progress) async {
    downloads++;
    progress(.5);
    progress(1);
    return File('test-verified-package');
  }

  @override
  Future<void> install(AppRelease release, File file) async {
    installs++;
    if (invalidPackage) {
      throw const UpdatePackageInvalidException('安装包已被删除，请重新下载');
    }
    if (failInstall) throw const UpdateCheckException('test install failed');
  }

  @override
  Future<String?> previousInstallResult() async => null;
}

class _DelayedVerification extends UpdatePackageManager {
  _DelayedVerification(Directory directory, _BytesAdapter adapter)
      : super(
            client: Dio()..httpClientAdapter = adapter,
            cacheDirectory: () async => directory,
            platform: () => 'windows-x86_64');

  final verifying = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<void> verifyFile(File file, UpdateArtifact artifact) async {
    await super.verifyFile(file, artifact);
    if (!verifying.isCompleted) {
      verifying.complete();
      await resume.future;
    }
  }
}

void main() {
  test('the checked tar is extracted without colliding with package contents',
      () async {
    final temp = await Directory.systemTemp.createTemp('thmr-update-test-');
    addTearDown(() => temp.delete(recursive: true));
    final destination = await Directory('${temp.path}/out').create();
    final file = File('${temp.path}/update.tar.gz');
    final archive = Archive()
      ..addFile(ArchiveFile('payload.tar', 3, [1, 2, 3]));
    await file.writeAsBytes(gzip.encode(TarEncoder().encode(archive)));
    await extractCheckedUpdate(file, 'tar.gz', destination);
    expect(
        await File('${destination.path}/payload.tar').readAsBytes(), [1, 2, 3]);
    final invalid = Archive()
      ..addFile(ArchiveFile.symlink('bad-link', '../outside'));
    await file.writeAsBytes(gzip.encode(TarEncoder().encode(invalid)));
    await expectLater(extractCheckedUpdate(file, 'tar.gz', destination),
        throwsA(isA<UpdateCheckException>()));
    expect(await destination.list().length, 1);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('thmr-download-test-');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => directory.delete(recursive: true));

  UpdatePackageManager manager(_BytesAdapter adapter,
          {String platform = 'windows-x86_64'}) =>
      UpdatePackageManager(
          client: Dio()..httpClientAdapter = adapter,
          cacheDirectory: () async => directory,
          platform: () => platform);

  test('download verifies hash and reuses only valid cached bytes', () async {
    final adapter = _BytesAdapter();
    final updater = manager(adapter);
    addTearDown(updater.close);
    final progress = <double>[];
    final file = await updater.download(_release(), progress.add);
    expect(await file.readAsBytes(), [97, 98, 99]);
    expect(progress.last, 1);
    await updater.download(_release(), (_) {});
    expect(adapter.requests, 1);
    await file.writeAsString('bad');
    await updater.download(_release(), (_) {});
    expect(adapter.requests, 2);
    expect(await file.readAsString(), 'abc');
  });

  test('missing package is reported as needing a re-download', () async {
    final updater = manager(_BytesAdapter());
    addTearDown(updater.close);
    await expectLater(
        updater.verifyFile(File('${directory.path}/missing.zip'),
            _release().artifactFor('windows-x86_64')!),
        throwsA(isA<UpdatePackageInvalidException>()
            .having((error) => error.message, 'message', contains('重新下载'))));
  });

  test(
      'cancelling during cache initialization never requests or writes a package',
      () async {
    final adapter = _BytesAdapter();
    final entered = Completer<void>();
    final cache = Completer<Directory>();
    final updater = UpdatePackageManager(
        client: Dio()..httpClientAdapter = adapter,
        cacheDirectory: () {
          entered.complete();
          return cache.future;
        },
        platform: () => 'windows-x86_64');
    addTearDown(updater.close);
    final cancelled = expectLater(
        updater.download(_release(), (_) {}),
        throwsA(isA<UpdateCheckException>()
            .having((e) => e.message, 'message', contains('已取消'))));
    await entered.future;
    updater.cancel();
    cache.complete(directory);
    await cancelled;
    expect(adapter.requests, 0);
    expect(await directory.list().toList(), isEmpty);
  });

  test('retry waits for a cancelled verification to release the partial file',
      () async {
    final adapter = _BytesAdapter();
    final updater = _DelayedVerification(directory, adapter);
    addTearDown(updater.close);
    final cancelled = expectLater(
        updater.download(_release(), (_) {}),
        throwsA(isA<UpdateCheckException>()
            .having((e) => e.message, 'message', contains('已取消'))));
    await updater.verifying.future;
    updater.cancel();
    final retry = updater.download(_release(), (_) {});
    updater.resume.complete();
    await cancelled;
    final file = await retry;
    expect(adapter.requests, 2);
    expect(await file.readAsString(), 'abc');
    expect(await directory.list().map((e) => e.path).toList(), [file.path]);
  });

  test(
      'bad digest, oversized body and interrupted streams leave no usable package',
      () async {
    for (final bytes in [
      [0, 0, 0],
      [97, 98, 99, 100]
    ]) {
      final updater = manager(_BytesAdapter()..bytes = bytes);
      await expectLater(updater.download(_release(), (_) {}),
          throwsA(isA<UpdateCheckException>()));
      updater.close();
      expect(await directory.list().toList(), isEmpty);
    }
    final updater = manager(_BytesAdapter()..fail = true);
    addTearDown(updater.close);
    await expectLater(updater.download(_release(), (_) {}),
        throwsA(isA<UpdateCheckException>()));
    expect(await directory.list().toList(), isEmpty);
  });

  test('download redirects cannot downgrade HTTPS', () async {
    final adapter = _BytesAdapter()..redirectInsecure = true;
    final updater = manager(adapter);
    addTearDown(updater.close);
    await expectLater(updater.download(_release(), (_) {}),
        throwsA(isA<UpdateCheckException>()));
    expect(adapter.requests, 1);
  });

  test('unsupported architecture cannot download another architecture',
      () async {
    final adapter = _BytesAdapter();
    final updater = manager(adapter, platform: 'windows-aarch64');
    addTearDown(updater.close);
    await expectLater(updater.download(_release(), (_) {}),
        throwsA(isA<UpdateCheckException>()));
    expect(adapter.requests, 0);
  });

  test(
      'archives reject traversal, absolute names, duplicate names and escaping links',
      () {
    for (final name in [
      '../outside',
      '/tmp/outside',
      r'C:\outside',
      'safe/../../outside'
    ]) {
      final archive = Archive()..addFile(ArchiveFile(name, 1, [0]));
      expect(() => validateUpdateArchive(archive),
          throwsA(isA<UpdateCheckException>()));
    }
    final escaping = Archive()
      ..addFile(ArchiveFile.symlink('bundle/link', '../../outside'));
    expect(() => validateUpdateArchive(escaping),
        throwsA(isA<UpdateCheckException>()));
    final duplicate = Archive()
      ..addFile(ArchiveFile('bundle/file', 1, [0]))
      ..addFile(ArchiveFile('bundle/./file', 1, [1]));
    expect(() => validateUpdateArchive(duplicate),
        throwsA(isA<UpdateCheckException>()));
    final throughLink = Archive()
      ..addFile(ArchiveFile.symlink('bundle/link', 'other'))
      ..addFile(ArchiveFile('bundle/link/payload', 1, [0]));
    expect(() => validateUpdateArchive(throughLink),
        throwsA(isA<UpdateCheckException>()));
    final valid = Archive()
      ..addFile(
          ArchiveFile('THMR.app/Contents/Frameworks/F/Versions/A/file', 1, [0]))
      ..addFile(ArchiveFile.symlink(
          'THMR.app/Contents/Frameworks/F/Versions/Current', 'A'));
    expect(() => validateUpdateArchive(valid), returnsNormally);
  });

  test(
      'automatic download reaches ready; install failure keeps a retryable package',
      () async {
    final packages = _ControllerPackages();
    final controller = AppUpdateController(
        service: serviceFor(ReleaseAdapter()),
        packages: packages,
        installedVersion: () async => const ClientVersion('0.1.3', '1'));
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.state.status, UpdateStatus.ready);
    expect(packages.downloads, 1);
    packages.failInstall = true;
    await controller.installUpdate();
    expect(controller.state.status, UpdateStatus.ready);
    expect(controller.state.error, 'test install failed');
    packages.failInstall = false;
    await controller.installUpdate();
    expect(packages.installs, 2);
  });

  test('deleted package returns to downloadable state for a retry', () async {
    final packages = _ControllerPackages();
    final controller = AppUpdateController(
        service: serviceFor(ReleaseAdapter()),
        packages: packages,
        installedVersion: () async => const ClientVersion('0.1.3', '1'));
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.state.status, UpdateStatus.ready);
    packages.invalidPackage = true;
    await controller.installUpdate();
    expect(controller.state.status, UpdateStatus.available);
    expect(controller.state.progress, 0);
    expect(controller.state.error, contains('重新下载'));
    packages.invalidPackage = false;
    await controller.downloadUpdate();
    expect(controller.state.status, UpdateStatus.ready);
    expect(controller.state.error, isNull);
    expect(packages.downloads, 2);
  });

  test('same version with a higher build updates the installed client',
      () async {
    final controller = AppUpdateController(
        service: serviceFor(ReleaseAdapter()..data = releaseJson('0.1.3')),
        installedVersion: () async => const ClientVersion('0.1.3', '1'));
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.state.status, UpdateStatus.available);
    expect(controller.state.release!.identity, '0.1.3+2');
  });
}
