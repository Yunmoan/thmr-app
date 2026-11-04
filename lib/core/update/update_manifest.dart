import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:pub_semver/pub_semver.dart';

const updateApiUrl = String.fromEnvironment('THMR_UPDATE_API_URL',
    defaultValue: 'https://api.zyghit.cn/updater/thmr');
const updatePublicKey = String.fromEnvironment('THMR_UPDATE_PUBLIC_KEY',
    defaultValue: 'r6zTlw9W6Sv9/PYPSEm/Zk2YTx0EMI8xbHuwnIeG2r0=');

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}

String currentUpdatePlatform() {
  if (Platform.isAndroid) return 'android-universal';
  return switch (Abi.current()) {
    Abi.windowsX64 => 'windows-x86_64',
    Abi.windowsArm64 => 'windows-aarch64',
    Abi.macosX64 => 'darwin-x86_64',
    Abi.macosArm64 => 'darwin-aarch64',
    Abi.linuxX64 => 'linux-x86_64',
    Abi.linuxArm64 => 'linux-aarch64',
    _ => 'unsupported',
  };
}

class UpdateArtifact {
  const UpdateArtifact(
      {required this.url,
      required this.sha256,
      required this.size,
      required this.format});
  final Uri url;
  final String sha256;
  final int size;
  final String format;
}

class AppRelease {
  const AppRelease(
      {required this.version,
      required this.buildNumber,
      required this.notes,
      required this.pageUrl,
      required this.artifacts,
      required this.envelope});
  final Version version;
  final int buildNumber;
  final String notes;
  final Uri pageUrl;
  final Map<String, UpdateArtifact> artifacts;
  final Map<String, dynamic> envelope;
  String get identity => '$version+$buildNumber';
  Map<String, dynamic> toJson() => envelope;

  UpdateArtifact? artifactFor([String? platform]) =>
      artifacts[platform ?? currentUpdatePlatform()];

  // Useful for platform previews; installation always checks the exact ABI.
  Uri? downloadFor(TargetPlatform platform) => artifacts[switch (platform) {
        TargetPlatform.windows => 'windows-x86_64',
        TargetPlatform.macOS => 'darwin-aarch64',
        TargetPlatform.linux => 'linux-x86_64',
        TargetPlatform.android => 'android-universal',
        _ => '',
      }]
          ?.url;
}

Uri checkedUpdateUrl(Object? value) {
  final url = value is String ? Uri.tryParse(value) : null;
  if (url == null ||
      url.scheme != 'https' ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.hasFragment) {
    throw const FormatException('Update URLs must be HTTPS');
  }
  return url;
}

/// Verify the original payload bytes, before trusting any install metadata.
Future<AppRelease?> verifyUpdateManifest(Object? raw, String publicKey) async {
  if (publicKey.isEmpty) {
    throw const UpdateCheckException('尚未配置更新验签公钥，请按自动更新部署文档配置客户端');
  }
  try {
    final key = base64Decode(publicKey);
    if (key.length != 32) throw const FormatException('Invalid public key');
    if (raw is! Map<String, dynamic> ||
        raw['schema'] != 1 ||
        raw['algorithm'] != 'ed25519') {
      throw const FormatException('Invalid update envelope');
    }
    final payload = base64Decode(raw['payload'] as String);
    final signature = base64Decode(raw['signature'] as String);
    if (payload.length > 512 * 1024 || signature.length != 64) {
      throw const FormatException('Invalid signed payload');
    }
    final valid = await Ed25519().verify(payload,
        signature: Signature(signature,
            publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)));
    if (!valid) throw const UpdateCheckException('更新信息签名校验失败，已停止更新');
    final data =
        (jsonDecode(utf8.decode(payload)) as Map).cast<String, dynamic>();
    if (data['program'] != 'THMR') throw const FormatException('Wrong program');
    final version = Version.parse(data['version'] as String);
    if (version.isPreRelease) return null;
    final build = data['build_number'];
    if (build is! int || build < 1) {
      throw const FormatException('Invalid build');
    }
    final entries = data['platforms'];
    if (entries is! Map || entries.isEmpty) {
      throw const FormatException('No artifacts');
    }
    final artifacts = <String, UpdateArtifact>{};
    for (final entry in entries.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid artifact');
      }
      final item = entry.value as Map;
      final hash = item['sha256'];
      final size = item['size'];
      final format = item['format'];
      if (hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          size is! int ||
          size < 1 ||
          size > 1024 * 1024 * 1024 ||
          !['zip', 'tar.gz', 'apk'].contains(format)) {
        throw const FormatException('Invalid artifact metadata');
      }
      final platform = entry.key as String;
      final expected =
          platform.startsWith('windows-') || platform.startsWith('darwin-')
              ? 'zip'
              : platform.startsWith('linux-')
                  ? 'tar.gz'
                  : platform == 'android-universal'
                      ? 'apk'
                      : null;
      if (expected != format) {
        throw const FormatException('Unsupported artifact format');
      }
      artifacts[platform] = UpdateArtifact(
          url: checkedUpdateUrl(item['url']),
          sha256: hash,
          size: size,
          format: format as String);
    }
    return AppRelease(
        version: version,
        buildNumber: build,
        notes: data['notes'] is String ? data['notes'] as String : '',
        pageUrl: checkedUpdateUrl(data['release_page']),
        artifacts: Map.unmodifiable(artifacts),
        envelope: Map<String, dynamic>.unmodifiable(raw));
  } on UpdateCheckException {
    rethrow;
  } catch (_) {
    throw const UpdateCheckException('更新信息或验签公钥格式无效，已停止更新');
  }
}
