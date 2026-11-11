// Runs with the standalone Dart VM and an empty PATH: no Flutter engine,
// ffmpeg executable, audio device or external network service is required.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:thmr_app/core/player/shared_radio_stream_io.dart';
import 'package:thmr_app/core/player/spectrum_linux_worker.dart';

Future<void> checkTone(
    String library, String fixture, int hz, int sampleRate) async {
  final audio = await File(fixture).readAsBytes();
  final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final relay = SharedRadioStream();
  final player = HttpClient();
  final release = Completer<void>();
  var requests = 0;
  upstream.listen((request) async {
    requests++;
    request.response.bufferOutput = false;
    request.response.headers.contentType = ContentType('audio', 'mpeg');
    try {
      // Deliberately split MP3 frames across irregular network chunks.
      // Repeat the two-second fixture to cover the adaptation hold and glide.
      final repeated = Uint8List(audio.length * 5);
      for (var i = 0; i < 5; i++) {
        repeated.setRange(i * audio.length, (i + 1) * audio.length, audio);
      }
      for (var offset = 0; offset < repeated.length; offset += 257) {
        request.response.add(repeated.sublist(offset,
            offset + 257 < repeated.length ? offset + 257 : repeated.length));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await release.future;
      await request.response.close();
    } catch (_) {}
  });
  final events = ReceivePort();
  final done = Completer<void>();
  final frame = Completer<List<Object>>();
  final adapted = Completer<double>();
  SendPort? commands;
  Isolate? worker;
  StreamSubscription<List<int>>? playSubscription;
  events.listen((message) {
    if (message is SendPort) {
      commands = message;
    } else if (message == null) {
      if (!done.isCompleted) done.complete();
    } else if (message is List && message.first == 'frame') {
      if (!frame.isCompleted) frame.complete([message[1], message[2]]);
      final upper = message[3] as double;
      if (upper < 4500 && !adapted.isCompleted) adapted.complete(upper);
    } else if (message is List && !frame.isCompleted) {
      frame.completeError(StateError(message.toString()));
    }
  });
  try {
    final uri =
        await relay.activate('http://127.0.0.1:${upstream.port}/live.mp3');
    final response = await (await player.getUrl(uri)).close();
    playSubscription = response.listen((_) {});
    worker = await Isolate.spawn(runLinuxSpectrumWorker,
        <Object>[events.sendPort, relay.spectrumUri.toString(), library],
        onError: events.sendPort, onExit: events.sendPort);
    final decoded = await frame.future.timeout(const Duration(seconds: 8));
    final magnitudes = decoded[0] as Float32List;
    final rate = decoded[1] as int;
    if (rate != sampleRate) throw StateError('Wrong sample rate: $rate');
    var peak = 1;
    for (var i = 2; i < magnitudes.length; i++) {
      if (magnitudes[i] > magnitudes[peak]) peak = i;
    }
    final frequency = peak * rate / ((magnitudes.length - 1) * 2);
    if ((frequency - hz).abs() > rate / 2048) {
      throw StateError('Expected $hz Hz, decoded $frequency Hz');
    }
    if (magnitudes[peak] < 0.01) throw StateError('No decoded audio energy');
    final upper = await adapted.future.timeout(const Duration(seconds: 8));
    if (upper < 4000) throw StateError('Bandwidth floor was lost: $upper');
    if (requests != 1) throw StateError('Extra upstream requests: $requests');
    commands!.send('stop');
    await done.future.timeout(const Duration(seconds: 3));
    stdout.writeln(
        '$fixture: $frequency Hz, $rate Hz PCM, adaptive upper ${upper.round()} Hz, one upstream connection');
  } finally {
    commands?.send('stop');
    worker?.kill(priority: Isolate.immediate);
    events.close();
    if (!release.isCompleted) release.complete();
    player.close(force: true);
    await playSubscription?.cancel();
    await relay.dispose();
    await upstream.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  final library = File(args.isEmpty
          ? 'build/linux/x64/debug/bundle/lib/libthmr_mp3.so'
          : args.single)
      .absolute
      .path;
  if (!File(library).existsSync()) {
    throw StateError('Build the Linux app first');
  }
  await checkTone(
      library, 'test/fixtures/sine_1000hz_44100_stereo.mp3', 1000, 44100);
  await checkTone(
      library, 'test/fixtures/sine_440hz_48000_mono.mp3', 440, 48000);
  stdout.writeln(
      'Bundled MP3 + FFT checks passed (PATH=${Platform.environment['PATH']})');
}
