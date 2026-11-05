// Integration-test harness: launch the production installer and exit only once
// it is ready, exactly like the GUI process. Uses isolated fixture plans only.
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
