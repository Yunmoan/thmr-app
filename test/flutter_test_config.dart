import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // 测试间隔离账号数据，并避免访问运行机器上的真实钥匙串。
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  await testMain();
}
