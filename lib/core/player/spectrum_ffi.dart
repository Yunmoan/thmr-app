// Windows spectrum source: thmr_capture.dll via dart:ffi.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'spectrum.dart';

typedef _StartNative = Int32 Function();
typedef _StartDart = int Function();
typedef _StopNative = Void Function();
typedef _StopDart = void Function();
typedef _PollNative = Int32 Function(Pointer<Float>, Int32);
typedef _PollDart = int Function(Pointer<Float>, int);

class SpectrumCapture implements SpectrumSource {
  SpectrumCapture._(this._startFn, this._stopFn, this._pollFn);

  static SpectrumCapture? _instance;

  static SpectrumCapture? tryCreate() {
    _instance ??= _build();
    return _instance;
  }

  final _StartDart _startFn;
  final _StopDart _stopFn;
  final _PollDart _pollFn;

  Pointer<Float>? _native;
  int _bands = 0;
  int _refs = 0;

  static SpectrumCapture? _build() {
    try {
      final lib = DynamicLibrary.open('thmr_capture.dll');
      final start = lib.lookupFunction<_StartNative, _StartDart>('thmr_start');
      final stop = lib.lookupFunction<_StopNative, _StopDart>('thmr_stop');
      final poll = lib.lookupFunction<_PollNative, _PollDart>('thmr_poll');
      return SpectrumCapture._(start, stop, poll);
    } catch (_) {
      return null;
    }
  }

  // Reference-counted: several widgets share one capture session; a
  // disposed widget must not tear down capture for the others.
  @override
  void start() {
    _refs++;
    if (_refs == 1) _startFn();
  }

  @override
  void stop() {
    if (_refs <= 0) return;
    _refs--;
    if (_refs == 0) {
      _stopFn();
      if (_native != null) {
        calloc.free(_native!);
        _native = null;
        _bands = 0;
      }
    }
  }

  @override
  Float32List? poll(int bands) {
    if (bands <= 0) return null;
    if (_native == null || _bands != bands) {
      if (_native != null) calloc.free(_native!);
      _native = calloc<Float>(bands);
      _bands = bands;
    }
    final code = _pollFn(_native!, bands);
    if (code < 0) return null;
    final view = _native!.asTypedList(bands);
    if (code == 0) {
      for (var i = 0; i < bands; i++) {
        view[i] *= 0.6;
      }
    }
    return Float32List.fromList(view);
  }
}
