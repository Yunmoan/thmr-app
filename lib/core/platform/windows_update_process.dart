import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _ShellExecuteInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  external Pointer<Void> hwnd;
  external Pointer<Utf16> lpVerb;
  external Pointer<Utf16> lpFile;
  external Pointer<Utf16> lpParameters;
  external Pointer<Utf16> lpDirectory;
  @Int32()
  external int nShow;
  external Pointer<Void> hInstApp;
  external Pointer<Void> lpIDList;
  external Pointer<Utf16> lpClass;
  external Pointer<Void> hkeyClass;
  @Uint32()
  external int dwHotKey;
  external Pointer<Void> hIconOrMonitor;
  external Pointer<Void> hProcess;
}

class WindowsUpdateStartException implements Exception {
  const WindowsUpdateStartException(this.code);
  final int code;
}

/// ShellExecute supplies a proper Windows console host while SW_HIDE keeps the
/// helper hidden. Dart's detached process mode cannot start Windows PowerShell
/// reliably. Only the installer requests UAC; the player stays unelevated.
Future<WindowsUpdateProcess> startWindowsUpdateProcess({
  required String helper,
  required String plan,
  required String workingDirectory,
  required bool elevated,
}) async {
  final handle = await Isolate.run(
      () => _launch(helper, plan, workingDirectory, elevated));
  return WindowsUpdateProcess(handle);
}

int _launch(String helper, String plan, String directory, bool elevated) {
  if (!Platform.isWindows) throw UnsupportedError('Windows installer');
  // Windows paths cannot contain quotes, so each path is one quoted argument.
  if ([helper, plan, directory]
      .any((value) => value.contains('"') || value.contains('\u0000'))) {
    throw const WindowsUpdateStartException(87);
  }
  final shell = DynamicLibrary.open('shell32.dll').lookupFunction<
      Int32 Function(Pointer<_ShellExecuteInfo>),
      int Function(Pointer<_ShellExecuteInfo>)>('ShellExecuteExW');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final lastError =
      kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  final ole = DynamicLibrary.open('ole32.dll');
  final initialize = ole.lookupFunction<Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('CoInitializeEx');
  final uninitialize =
      ole.lookupFunction<Void Function(), void Function()>('CoUninitialize');
  final initialized = initialize(nullptr, 2 | 4);
  final info = calloc<_ShellExecuteInfo>();
  final verb = (elevated ? 'runas' : 'open').toNativeUtf16();
  final executable =
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
          .toNativeUtf16();
  final arguments =
      '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$helper" -PlanPath "$plan"'
          .toNativeUtf16();
  final folder = directory.toNativeUtf16();
  try {
    info.ref
      ..cbSize = sizeOf<_ShellExecuteInfo>()
      ..fMask = 0x40 | 0x100 | 0x400
      ..lpVerb = verb
      ..lpFile = executable
      ..lpParameters = arguments
      ..lpDirectory = folder
      ..nShow = 0;
    if (shell(info) == 0) throw WindowsUpdateStartException(lastError());
    if (info.ref.hProcess == nullptr) {
      throw const WindowsUpdateStartException(6);
    }
    return info.ref.hProcess.address;
  } finally {
    calloc.free(verb);
    calloc.free(executable);
    calloc.free(arguments);
    calloc.free(folder);
    calloc.free(info);
    if (initialized >= 0) uninitialize();
  }
}

class WindowsUpdateProcess {
  WindowsUpdateProcess(this._address);
  int _address;

  int? get exitCode {
    if (_address == 0) return null;
    final getExitCode = DynamicLibrary.open('kernel32.dll').lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint32>),
        int Function(Pointer<Void>, Pointer<Uint32>)>('GetExitCodeProcess');
    final code = calloc<Uint32>();
    try {
      if (getExitCode(Pointer.fromAddress(_address), code) == 0 ||
          code.value == 259) {
        return null;
      }
      return code.value;
    } finally {
      calloc.free(code);
    }
  }

  void close() {
    if (_address == 0) return;
    DynamicLibrary.open('kernel32.dll').lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(
            Pointer<Void>)>('CloseHandle')(Pointer.fromAddress(_address));
    _address = 0;
  }
}
