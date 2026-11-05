import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/windows_process_exit.dart';
import 'update_manifest.dart';

Future<Directory> updateCacheDirectory() async => Directory(p.join(
    (Platform.isLinux
            ? await getApplicationCacheDirectory()
            : await getTemporaryDirectory())
        .path,
    'thmr-updates'));

String _randomToken() => List.generate(32, (_) => Random.secure().nextInt(256))
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// All downloaded bytes are checked against the signed manifest before staging.
class UpdatePackageManager {
  UpdatePackageManager(
      {Dio? client,
      Future<Directory> Function()? cacheDirectory,
      String Function()? platform,
      Future<void> Function()? quit})
      : _client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30))),
        _cacheDirectory = cacheDirectory ?? updateCacheDirectory,
        _platform = platform ?? currentUpdatePlatform,
        _quit = quit ?? (() async => terminateWindowsProcess());

  final Dio _client;
  final Future<Directory> Function() _cacheDirectory;
  final String Function() _platform;
  final Future<void> Function() _quit;
  CancelToken? _cancelToken;
  void cancel() => _cancelToken?.cancel('Update download cancelled');
  void close() {
    cancel();
    _client.close(force: true);
  }

  Future<void> verifyFile(File file, UpdateArtifact artifact) async {
    if (!await file.exists() ||
        await file.length() != artifact.size ||
        (await crypto.sha256.bind(file.openRead()).first).toString() !=
            artifact.sha256) {
      throw const UpdateCheckException('更新包完整性校验失败，请重新下载');
    }
  }

  Future<File> download(
      AppRelease release, void Function(double) progress) async {
    final artifact = release.artifactFor(_platform());
    if (artifact == null) throw const UpdateCheckException('此版本没有当前系统架构的自动更新包');
    final cache = await _cacheDirectory();
    await cache.create(recursive: true);
    final file =
        File(p.join(cache.path, '${artifact.sha256}.${artifact.format}'));
    if (await file.exists()) {
      try {
        await verifyFile(file, artifact);
        progress(1);
        return file;
      } on UpdateCheckException {
        await file.delete();
      }
    }
    final partial = File('${file.path}.part');
    final token = _cancelToken = CancelToken();
    IOSink? sink;
    try {
      var url = artifact.url;
      Response<ResponseBody>? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        checkedUpdateUrl(url.toString());
        response = await _client.get<ResponseBody>(url.toString(),
            cancelToken: token,
            options: Options(
                responseType: ResponseType.stream,
                followRedirects: false,
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 400,
                headers: {
                  'User-Agent': 'THMR-App',
                  'Accept-Encoding': 'identity'
                }));
        if (response.statusCode == 200) break;
        final location = response.headers.value('location');
        // Consume redirect bodies so HTTP connections are released.
        await response.data?.stream.drain<void>();
        if (![301, 302, 303, 307, 308].contains(response.statusCode) ||
            location == null ||
            redirects == 5) {
          throw const UpdateCheckException('更新包下载重定向无效');
        }
        url = checkedUpdateUrl(url.resolve(location).toString());
      }
      if (response?.statusCode != 200 || response?.data == null) {
        throw const UpdateCheckException('更新包下载失败');
      }
      final contentLength =
          int.tryParse(response!.headers.value('content-length') ?? '');
      if (contentLength != null && contentLength != artifact.size) {
        throw const UpdateCheckException('更新包大小与签名信息不一致');
      }
      sink = partial.openWrite();
      var received = 0;
      await sink.addStream(response.data!.stream.map((bytes) {
        if (token.isCancelled) throw token.cancelError!;
        received += bytes.length;
        if (received > artifact.size) {
          throw const UpdateCheckException('更新包超过声明大小，已停止下载');
        }
        progress(received / artifact.size);
        return bytes;
      }));
      await sink.flush();
      await sink.close();
      sink = null;
      await verifyFile(partial, artifact);
      return await partial.rename(file.path);
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {/* Continue removing the partial file. */}
      if (await partial.exists()) await partial.delete();
      if (error is UpdateCheckException) rethrow;
      if (error is DioException && CancelToken.isCancel(error)) {
        throw const UpdateCheckException('更新下载已取消');
      }
      throw const UpdateCheckException('下载更新失败，请检查网络、磁盘空间后重试');
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
  }

  Future<String?> previousInstallResult() async {
    try {
      final cache = await _cacheDirectory();
      final pointer =
          await File(p.join(cache.path, 'last-transaction')).readAsString();
      if (!RegExp(r'^tx-[a-f0-9]{64}$').hasMatch(pointer)) return null;
      final raw =
          await File(p.join(cache.path, pointer, 'result.json')).readAsString();
      final result = jsonDecode(raw.replaceFirst('\ufeff', '')) as Map;
      if (result['status'] == 'rollback') return '上次更新启动失败，已自动恢复原版本';
      if (result['status'] == 'failed') return '上次更新未能安装，原版本已保留';
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> install(AppRelease release, File file) async {
    final artifact = release.artifactFor(_platform());
    if (artifact == null) throw const UpdateCheckException('此架构不支持此更新包');
    await verifyFile(file, artifact);
    if (Platform.isAndroid) {
      final result = await const MethodChannel('thmr/updater')
          .invokeMethod<String>('installApk', {
        'path': file.path,
        'version': release.version.toString(),
        'buildNumber': release.buildNumber,
      });
      if (result == 'permission_required') {
        throw const UpdateCheckException('请在系统设置中允许 THMR 安装应用，返回后再次点击安装');
      }
      if (result != 'installer_started') {
        throw const UpdateCheckException('无法打开系统安装器');
      }
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw const UpdateCheckException('当前平台不支持应用内安装更新');
    }
    final executable =
        await File(Platform.resolvedExecutable).resolveSymbolicLinks();
    final target = Platform.isMacOS
        ? p.dirname(p.dirname(p.dirname(executable)))
        : p.dirname(executable);
    final relativeExe = Platform.isMacOS
        ? 'Contents/MacOS/THMR'
        : Platform.isWindows
            ? 'thmr_app.exe'
            : 'thmr_app';
    if (p.normalize(p.join(target, relativeExe)) != p.normalize(executable) ||
        !await Directory(p.join(
                target, Platform.isMacOS ? 'Contents' : 'data/flutter_assets'))
            .exists()) {
      throw const UpdateCheckException('请从完整的 THMR 应用目录运行，开发运行器不能执行自更新');
    }
    final parent = p.dirname(target);
    final token = _randomToken();
    final stage = Directory(p.join(parent, '.thmr-update-$token'));
    final unpack = Directory(p.join(parent, '.thmr-unpack-$token'));
    final backup = p.join(parent, '.thmr-backup-$token');
    var helperStarted = false;
    File? abortFile;
    try {
      await unpack
          .create(); // Fail before quitting if the installation is read-only.
      await _extractChecked(file, artifact, unpack);
      final payload = Platform.isMacOS
          ? Directory(p.join(unpack.path, 'THMR.app'))
          : Platform.isLinux
              ? Directory(p.join(unpack.path, 'bundle'))
              : unpack;
      if (!await File(p.join(payload.path, relativeExe)).exists()) {
        throw const UpdateCheckException('更新包缺少 THMR 主程序');
      }
      if (Platform.isLinux) {
        final versionData = jsonDecode(
            await File(p.join(payload.path, 'data/flutter_assets/version.json'))
                .readAsString()) as Map;
        if (versionData['version'] != release.version.toString() ||
            versionData['build_number'].toString() !=
                '${release.buildNumber}') {
          throw const UpdateCheckException('更新包版本与签名信息不一致');
        }
      }
      if (Platform.isMacOS) {
        final checked = await Process.run('/usr/bin/codesign',
            ['--verify', '--deep', '--strict', payload.path]);
        final bundle = await Process.run('/usr/libexec/PlistBuddy', [
          '-c',
          'Print:CFBundleIdentifier',
          p.join(payload.path, 'Contents/Info.plist')
        ]);
        final version = await Process.run('/usr/libexec/PlistBuddy', [
          '-c',
          'Print:CFBundleShortVersionString',
          p.join(payload.path, 'Contents/Info.plist')
        ]);
        final build = await Process.run('/usr/libexec/PlistBuddy', [
          '-c',
          'Print:CFBundleVersion',
          p.join(payload.path, 'Contents/Info.plist')
        ]);
        if (checked.exitCode != 0 ||
            bundle.exitCode != 0 ||
            bundle.stdout.toString().trim() != 'cn.yunmoan.thmr.thmrApp') {
          throw const UpdateCheckException('macOS 应用签名或 Bundle ID 校验失败');
        }
        if (version.exitCode != 0 ||
            build.exitCode != 0 ||
            version.stdout.toString().trim() != release.version.toString() ||
            build.stdout.toString().trim() != '${release.buildNumber}') {
          throw const UpdateCheckException('更新包版本与签名信息不一致');
        }
      }
      await payload.rename(stage.path);
      if (await unpack.exists()) {
        await _removeStage(unpack, parent, '.thmr-unpack-');
      }
      final cache = await _cacheDirectory();
      final tx = await Directory(p.join(cache.path, 'tx-$token'))
          .create(recursive: true);
      final ack = p.join(tx.path, 'ack');
      abortFile = File(p.join(tx.path, 'cancel'));
      final ready = p.join(tx.path, 'ready');
      final result = p.join(tx.path, 'result.json');
      final plan = {
        'processId': pid,
        'parent': parent,
        'target': target,
        'stage': stage.path,
        'backup': backup,
        'ack': ack,
        'token': token,
        'ready': ready,
        'result': result,
        'timeout': 60,
        'identity': release.identity
      };
      await File(p.join(tx.path, 'plan.json'))
          .writeAsString(jsonEncode(plan), flush: true);
      final windows = Platform.isWindows;
      final helper =
          File(p.join(tx.path, windows ? 'install.ps1' : 'install.sh'));
      await helper.writeAsString(
          await rootBundle.loadString(windows
              ? 'assets/updater/install_windows.ps1'
              : 'assets/updater/install_unix.sh'),
          flush: true);
      await File(p.join(cache.path, 'last-transaction'))
          .writeAsString('tx-$token', flush: true);
      if (windows) {
        final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        await Process.start(
            p.join(
                systemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
            [
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              helper.path,
              '-PlanPath',
              p.join(tx.path, 'plan.json')
            ],
            workingDirectory: parent,
            mode: ProcessStartMode.detached);
      } else {
        await Process.start(
            '/bin/sh',
            [
              helper.path,
              '$pid',
              target,
              stage.path,
              backup,
              ack,
              token,
              relativeExe,
              result,
              ready,
              '60',
              Platform.isMacOS ? 'macos' : 'linux'
            ],
            workingDirectory: parent,
            mode: ProcessStartMode.detached);
      }
      for (var i = 0; i < 100; i++) {
        if (await File(ready).exists() &&
            await File(ready).readAsString() == token) {
          helperStarted = true;
          await _quit();
          return;
        }
        if (await File(result).exists()) {
          throw const UpdateCheckException('安装辅助程序拒绝了更新包，原版本保持可用');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw const UpdateCheckException('安装辅助程序未能启动，请检查目录权限和系统策略');
    } on UpdateCheckException {
      rethrow;
    } catch (_) {
      throw const UpdateCheckException('无法准备安装，请将应用放在当前用户可写的独立目录，并检查磁盘空间');
    } finally {
      if (!helperStarted) {
        await abortFile?.writeAsString('cancel', flush: true);
        if (await stage.exists()) {
          await _removeStage(stage, parent, '.thmr-update-');
        }
        if (await unpack.exists()) {
          await _removeStage(unpack, parent, '.thmr-unpack-');
        }
      }
    }
  }

  Future<void> _extractChecked(
      File file, UpdateArtifact artifact, Directory destination) async {
    File? tar;
    InputFileStream? input;
    try {
      if (artifact.format == 'tar.gz') {
        tar = File(p.join(destination.path, 'payload.tar'));
        final output = OutputFileStream(tar.path);
        input = InputFileStream(file.path);
        try {
          const GZipDecoder().decodeStream(input, output);
        } finally {
          await output.close();
          await input.close();
          input = null;
        }
        if (await tar.length() > 2 * 1024 * 1024 * 1024) {
          throw const FormatException('Archive too large');
        }
      }
      input = InputFileStream(tar?.path ?? file.path);
      final tarDecoder = TarDecoder();
      final archive = artifact.format == 'zip'
          ? ZipDecoder().decodeStream(input, verify: true)
          : tarDecoder.decodeStream(input, verify: true);
      if (tarDecoder.files
          .any((entry) => !['', '0', '2', '5'].contains(entry.typeFlag))) {
        throw const UpdateCheckException('更新包包含不支持的硬链接或特殊文件');
      }
      validateUpdateArchive(archive);
      await input.close();
      input = null;
      if (tar != null) await tar.delete();
      final process = Platform.isMacOS
          ? await Process.run(
              '/usr/bin/ditto', ['-x', '-k', file.path, destination.path])
          : Platform.isWindows
              ? await Process.run(
                  p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows',
                      'System32/tar.exe'),
                  ['-xf', file.path, '-C', destination.path])
              : await Process.run(
                  '/bin/tar', ['-xzf', file.path, '-C', destination.path]);
      if (process.exitCode != 0) throw const UpdateCheckException('解压更新包失败');
    } finally {
      await input?.close();
    }
  }

  Future<void> _removeStage(
      Directory directory, String parent, String prefix) async {
    final path = p.normalize(p.absolute(directory.path));
    if (p.dirname(path) != p.normalize(p.absolute(parent)) ||
        !p.basename(path).startsWith(prefix) ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory ||
        p.normalize(await directory.resolveSymbolicLinks()) != path) {
      throw const UpdateCheckException('拒绝清理不安全的更新目录');
    }
    await directory.delete(recursive: true);
  }
}

void validateUpdateArchive(Archive archive) {
  var size = 0;
  final links = <String>{};
  final files = <String>{};
  final all = <String>{};
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    final normalized = p.posix.normalize(name);
    if (name.isEmpty ||
        name.contains('\u0000') ||
        name.split('/').any((segment) =>
            segment.contains(':') ||
            segment == '..' ||
            segment.endsWith(' ') ||
            segment.endsWith('.')) ||
        p.posix.isAbsolute(name) ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        !all.add(normalized)) {
      throw const UpdateCheckException('更新包包含不安全或重复的路径');
    }
    size += entry.size;
    if (size > 2 * 1024 * 1024 * 1024 || all.length > 100000) {
      throw const UpdateCheckException('更新包解压后过大');
    }
    if (entry.isSymbolicLink) {
      final target = entry.symbolicLink!.replaceAll('\\', '/');
      final resolved =
          p.posix.normalize(p.posix.join(p.posix.dirname(normalized), target));
      if (p.posix.isAbsolute(target) ||
          RegExp(r'^[A-Za-z]:').hasMatch(target) ||
          resolved == '..' ||
          resolved.startsWith('../')) {
        throw const UpdateCheckException('更新包包含越界链接');
      }
      links.add(normalized);
    } else {
      files.add(normalized);
    }
  }
  for (final name in files) {
    var parent = p.posix.dirname(name);
    while (parent != '.') {
      if (links.contains(parent)) {
        throw const UpdateCheckException('更新包尝试通过链接写入文件');
      }
      parent = p.posix.dirname(parent);
    }
  }
}

/// Acknowledge only our own transaction and only after the first Flutter frame.
Future<void> acknowledgeInstalledUpdate(List<String> args) async {
  try {
    final index = args.indexOf('--thmr-update-ack');
    final tokenIndex = args.indexOf('--thmr-update-token');
    final token = tokenIndex >= 0 && tokenIndex + 1 < args.length
        ? args[tokenIndex + 1]
        : Platform.environment['THMR_UPDATE_TOKEN'] ?? '';
    final ackPath = index >= 0 && index + 1 < args.length
        ? args[index + 1]
        : Platform.environment['THMR_UPDATE_ACK'] ?? '';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) return;
    final cache = await updateCacheDirectory();
    final expected = p.join(cache.path, 'tx-$token', 'ack');
    if (p.normalize(ackPath) != p.normalize(expected)) return;
    final plan = jsonDecode(
            await File(p.join(p.dirname(expected), 'plan.json')).readAsString())
        as Map;
    final executable =
        await File(Platform.resolvedExecutable).resolveSymbolicLinks();
    final target = Platform.isMacOS
        ? p.dirname(p.dirname(p.dirname(executable)))
        : p.dirname(executable);
    if (plan['token'] != token ||
        p.normalize(plan['target'] as String) != p.normalize(target)) {
      return;
    }
    await File(expected).writeAsString(token, flush: true);
  } catch (_) {/* The helper will restore the previous version on timeout. */}
}
