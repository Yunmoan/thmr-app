import 'dart:ffi';
import 'dart:io' show Platform, exit;

typedef _GetCurrentProcessNative = Pointer<Void> Function();
typedef _GetCurrentProcessDart = Pointer<Void> Function();
typedef _TerminateProcessNative = Int32 Function(Pointer<Void>, Uint32);
typedef _TerminateProcessDart = int Function(Pointer<Void>, int);

/// Terminate this Windows process without waiting for native DLL shutdown.
/// A media plugin can block ExitProcess while Flutter's UI thread is exiting.
Never terminateWindowsProcess() {
  if (Platform.isWindows) {
    try {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final current = kernel.lookupFunction<_GetCurrentProcessNative,
          _GetCurrentProcessDart>('GetCurrentProcess');
      final terminate =
          kernel.lookupFunction<_TerminateProcessNative, _TerminateProcessDart>(
              'TerminateProcess');
      terminate(current(), 0);
    } catch (_) {
      // Fall back to Dart's normal process exit when the Win32 API is absent.
    }
  }
  exit(0);
}
