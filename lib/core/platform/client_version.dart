import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

// CI 向各平台传入统一的发布版本。Apple 的构建版本需为数字，因此预发布版本名通过此编译定义提供。
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
