// Windows spectrum: WASAPI lifecycle and native FFT stay off the UI isolate.
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'spectrum.dart';
import 'adaptive_spectrum.dart';

typedef _StartNative = Int32 Function();
typedef _StopNative = Void Function();
typedef _PollNative = Int32 Function(Pointer<Float>, Int32);

class SpectrumCapture implements SpectrumSource {
  SpectrumCapture._() : _entry = _captureWorker;
  SpectrumCapture.forTesting(this._entry);

  static SpectrumCapture? _instance;
  static SpectrumCapture? tryCreate() {
    if (_instance != null) return _instance;
    try {
      // Resolve the ABI only. Starting WASAPI can block for up to 2 seconds.
      final lib = DynamicLibrary.open('thmr_capture.dll');
      for (final name in ['thmr_start', 'thmr_stop', 'thmr_poll_fft']) {
        lib.lookup<Void>(name);
      }
      return _instance = SpectrumCapture._();
    } catch (_) {
      return null;
    }
  }

  final void Function(List<Object>) _entry;
  final _spectrum = AdaptiveSpectrum(autoGain: true);
  final _clock = Stopwatch()..start();
  ReceivePort? _events;
  SendPort? _commands;
  Completer<void>? _finished;
  Duration? _lastFrame;
  int _refs = 0, _generation = 0;
  bool _disposed = false;

  @override
  void start() {
    if (_disposed || ++_refs != 1) return;
    _generation++;
    _spectrum.reset();
    _lastFrame = null;
    if (_events == null) _spawn();
    _commands?.send(['start', _generation]);
  }

  void _spawn() {
    final events = ReceivePort();
    final finished = Completer<void>();
    _events = events;
    _finished = finished;
    events.listen((message) {
      if (message is SendPort) {
        _commands = message;
        message.send(_disposed
            ? ['dispose']
            : _refs > 0
                ? ['start', _generation]
                : ['stop']);
      } else if (message == null) {
        events.close();
        if (identical(_events, events)) {
          _events = null;
          _commands = null;
        }
        if (!finished.isCompleted) finished.complete();
      } else if (!_disposed &&
          _refs > 0 &&
          message is List &&
          message.length == 4 &&
          message[0] == 'frame' &&
          message[1] == _generation) {
        final now = _clock.elapsed;
        _spectrum.add(message[3] as Float32List, message[2] as int, now);
        _lastFrame = now;
      }
    });
    unawaited(Isolate.spawn(_entry, <Object>[events.sendPort],
            onExit: events.sendPort, onError: events.sendPort)
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {
      events.sendPort.send(null);
    }));
  }

  @override
  void stop() {
    if (_refs <= 0 || --_refs != 0) return;
    _lastFrame = null;
    _commands?.send(['stop']);
  }

  @override
  Float32List? poll(int bands) {
    if (_refs == 0 ||
        _lastFrame == null ||
        bands <= 0 ||
        _clock.elapsed - _lastFrame! > const Duration(milliseconds: 250)) {
      return null;
    }
    return _spectrum.bands(bands);
  }

  Future<void> dispose() async {
    _disposed = true;
    _refs = 0;
    _lastFrame = null;
    _commands?.send(['dispose']);
    await _finished?.future;
  }
}

void _captureWorker(List<Object> arguments) {
  final output = arguments[0] as SendPort;
  final commands = ReceivePort();
  output.send(commands.sendPort);
  final lib = DynamicLibrary.open('thmr_capture.dll');
  final start = lib.lookupFunction<_StartNative, int Function()>('thmr_start');
  final stop = lib.lookupFunction<_StopNative, void Function()>('thmr_stop');
  final poll =
      lib.lookupFunction<_PollNative, int Function(Pointer<Float>, int)>(
          'thmr_poll_fft');
  final buffer = calloc<Float>(513);
  Timer? timer;
  var running = false;
  void halt() {
    timer?.cancel();
    timer = null;
    if (running) stop();
    running = false;
  }

  commands.listen((message) {
    if (message is! List) return;
    switch (message[0]) {
      case 'start':
        halt();
        final generation = message[1] as int;
        running = start() == 0;
        if (!running) return;
        timer = Timer.periodic(const Duration(milliseconds: 48), (_) {
          final rate = poll(buffer, 513);
          if (rate > 0) {
            output.send([
              'frame',
              generation,
              rate,
              Float32List.fromList(buffer.asTypedList(513))
            ]);
          }
        });
      case 'stop':
        halt();
      case 'dispose':
        halt();
        calloc.free(buffer);
        commands.close();
    }
  });
}
