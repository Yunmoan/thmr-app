import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class SystemMemory {
  const SystemMemory({this.total, this.available});
  final int? total;
  final int? available;
}

final class _MemoryStatus extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int load;
  @Uint64()
  external int totalPhysical;
  @Uint64()
  external int availablePhysical;
  @Uint64()
  external int totalPage;
  @Uint64()
  external int availablePage;
  @Uint64()
  external int totalVirtual;
  @Uint64()
  external int availableVirtual;
  @Uint64()
  external int availableExtended;
}

Future<SystemMemory> readSystemMemory() async {
  try {
    if (Platform.isWindows) {
      final status = calloc<_MemoryStatus>();
      try {
        status.ref.length = sizeOf<_MemoryStatus>();
        final read = DynamicLibrary.open('kernel32.dll').lookupFunction<
            Int32 Function(Pointer<_MemoryStatus>),
            int Function(Pointer<_MemoryStatus>)>('GlobalMemoryStatusEx');
        if (read(status) != 0) {
          return SystemMemory(
            total: status.ref.totalPhysical,
            available: status.ref.availablePhysical,
          );
        }
      } finally {
        calloc.free(status);
      }
    } else if (Platform.isLinux || Platform.isAndroid) {
      final values = <String, int>{};
      for (final line in (await File('/proc/meminfo').readAsLines())) {
        final match =
            RegExp(r'^(MemTotal|MemAvailable):\s+(\d+)\s+kB').firstMatch(line);
        if (match != null) values[match[1]!] = int.parse(match[2]!) * 1024;
      }
      return SystemMemory(
          total: values['MemTotal'], available: values['MemAvailable']);
    } else if (Platform.isMacOS || Platform.isIOS) {
      final name = 'hw.memsize'.toNativeUtf8();
      final value = calloc<Uint64>();
      final length = calloc<Size>()..value = sizeOf<Uint64>();
      try {
        final read = DynamicLibrary.process().lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Void>, Pointer<Size>,
                Pointer<Void>, Size),
            int Function(Pointer<Utf8>, Pointer<Void>, Pointer<Size>,
                Pointer<Void>, int)>('sysctlbyname');
        if (read(name, value.cast(), length, nullptr, 0) == 0) {
          return SystemMemory(total: value.value);
        }
      } finally {
        calloc.free(name);
        calloc.free(value);
        calloc.free(length);
      }
    }
  } catch (_) {
    // Some mobile OS versions restrict system-wide memory information.
  }
  return const SystemMemory();
}
