// 集成测试使用隔离的安装计划，调用正式安装器并等待其就绪后退出，复现 GUI 进程的交接。
import 'dart:convert';
import 'dart:io';

import 'package:thmr_app/core/platform/windows_update_process.dart';

Future<void> main(List<String> args) async {
  final planFile = File(args[1]);
  final plan =
      jsonDecode(await planFile.readAsString()) as Map<String, dynamic>;
  plan['processId'] = pid;
  await planFile.writeAsString(jsonEncode(plan), flush: true);
  final process = await startWindowsUpdateProcess(
    helper: args[0],
    plan: planFile.path,
    workingDirectory: planFile.parent.path,
    elevated: false,
  );
  try {
    for (var i = 0; i < 300; i++) {
      final ready = File(plan['ready'] as String);
      if (await ready.exists() && await ready.readAsString() == plan['token']) {
        exit(0);
      }
      if (process.exitCode != null) exit(process.exitCode!);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await File('${planFile.parent.path}/cancel')
        .writeAsString('cancel', flush: true);
    exit(2);
  } finally {
    process.close();
  }
}
