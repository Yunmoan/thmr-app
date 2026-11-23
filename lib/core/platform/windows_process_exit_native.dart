import 'dart:ffi';
import 'dart:io' show Platform, exit;

typedef _GetCurrentProcessNative = Pointer<Void> Function();
typedef _GetCurrentProcessDart = Pointer<Void> Function();
typedef _TerminateProcessNative = Int32 Function(Pointer<Void>, Uint32);
typedef _TerminateProcessDart = int Function(Pointer<Void>, int);

/// 直接终止 Windows 进程，跳过原生 DLL 的卸载流程。Flutter UI 线程退出时，
/// 媒体插件可能阻塞 ExitProcess。
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
      // Win32 API 不可用时，回退到 Dart 的常规进程退出流程。
    }
  }
  exit(0);
}
