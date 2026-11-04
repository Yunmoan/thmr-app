import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

// CI injects the same release identity on every platform. In particular, Apple
// requires a numeric bundle version, so prerelease names live in this define.
const clientReleaseVersion = String.fromEnvironment('THMR_CLIENT_VERSION');

class ClientVersion {
  const ClientVersion(this.version, this.buildNumber);

  final String version;
  final String buildNumber;

  String get label => buildNumber.isEmpty ? version : '$version+$buildNumber';
}

final clientVersionProvider = FutureProvider<ClientVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return ClientVersion(
    clientReleaseVersion.isEmpty ? info.version : clientReleaseVersion,
    info.buildNumber,
  );
});
