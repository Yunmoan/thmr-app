import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum_ffi.dart';

// Model a slow synchronous native API on the production isolate transport.
void _slowCapture(List<Object> args) {
  final output = args[0] as SendPort;
  final input = ReceivePort();
  Timer? frames;
  output.send(input.sendPort);
  input.listen((command) {
    final message = command as List;
    switch (message[0]) {
      case 'start':
        sleep(const Duration(milliseconds: 300));
        frames?.cancel();
        frames = Timer.periodic(const Duration(milliseconds: 20), (_) {
          output.send([
            'frame',
            message[1],
            48000,
            Float32List(513)..fillRange(0, 513, 0.2)
          ]);
        });
      case 'stop':
        sleep(const Duration(milliseconds: 300));
        frames?.cancel();
      case 'dispose':
        frames?.cancel();
        input.close();
    }
  });
}

Future<void> _waitForFrame(SpectrumCapture source) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (source.poll(64) == null) {
    if (DateTime.now().isAfter(end)) fail('Worker did not deliver audio data');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('slow native start/stop leaves the UI event loop responsive', () async {
    final source = SpectrumCapture.forTesting(_slowCapture);
    addTearDown(source.dispose);
    final clock = Stopwatch()..start();
    source.start();
    expect(clock.elapsedMilliseconds, lessThan(200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(source.poll(64), isNull);
    await _waitForFrame(source);
    source.start();
    source.stop();
    expect(source.poll(64), isNotNull,
        reason: 'A second visible strip still owns capture');
    clock.reset();
    source.stop();
    expect(clock.elapsedMilliseconds, lessThan(200));
    expect(source.poll(64), isNull);
    source.start();
    expect(source.poll(64), isNull,
        reason: 'A new session cannot reuse old FFT data');
    await _waitForFrame(source);
    await source.dispose().timeout(const Duration(seconds: 5));
    expect(source.poll(64), isNull);
  });

  test('stop and dispose before the startup handshake do not leak a worker',
      () async {
    final source = SpectrumCapture.forTesting(_slowCapture);
    source.start();
    source.stop();
    await source.dispose().timeout(const Duration(seconds: 5));
    source.start();
    expect(source.poll(64), isNull);
  });
}
