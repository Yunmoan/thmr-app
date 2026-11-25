import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/shared_radio_stream_io.dart';

class _BlockedSocket extends Fake implements Socket {
  final writable = Completer<void>();
  var bytesWritten = 0;
  var destroyed = false;

  @override
  void add(List<int> bytes) => bytesWritten += bytes.length;

  @override
  Future<void> flush() => writable.future;

  @override
  void destroy() {
    destroyed = true;
    if (!writable.isCompleted) writable.complete();
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('a stalled consumer is disconnected while another keeps draining',
      () async {
    final slow = _BlockedSocket();
    final fast = _BlockedSocket()..writable.complete();
    final stalled = RelayOutput(slow);
    final healthy = RelayOutput(fast);
    final chunk = Uint8List(RelayOutput.maxPendingBytes ~/ 2);
    for (var i = 0; i < 3; i++) {
      stalled.add(chunk);
      healthy.add(chunk);
      await Future<void>.delayed(Duration.zero);
    }
    expect(slow.destroyed, isTrue);
    expect(slow.bytesWritten, chunk.length);
    expect(fast.destroyed, isFalse);
    expect(fast.bytesWritten, 3 * chunk.length);
    healthy.finish();
  });
  test('a failed bind can be retried on the same relay', () async {
    final relay = SharedRadioStream();
    addTearDown(relay.dispose);
    await IOOverrides.runZoned(
      () => expectLater(relay.activate('https://example.invalid/radio'),
          throwsA(isA<SocketException>())),
      serverSocketBind: (_, __,
              {backlog = 0, shared = false, v6Only = false}) async =>
          throw const SocketException('暂时无法绑定'),
    );
    final uri = await relay.activate('https://example.invalid/radio');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.headUrl(uri)).close();
    expect(response.statusCode, HttpStatus.ok);
    await response.drain<void>();
  });

  test('disposing a pending failed bind leaves a new binding intact', () async {
    final relay = SharedRadioStream();
    addTearDown(relay.dispose);
    final binding = Completer<ServerSocket>();
    final failed = IOOverrides.runZoned(
      () => expectLater(relay.activate('https://example.invalid/old'),
          throwsA(isA<SocketException>())),
      serverSocketBind: (_, __,
              {backlog = 0, shared = false, v6Only = false}) =>
          binding.future,
    );
    final disposing = relay.dispose();
    final uri = await relay.activate('https://example.invalid/new');
    binding.completeError(const SocketException('绑定失败'));
    await failed;
    await disposing;
    expect(relay.spectrumUri?.port, uri.port);
    expect(
        (await relay.activate('https://example.invalid/again')).port, uri.port);
  });

  test('player and spectrum share one upstream radio request', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = SharedRadioStream();
    final playerClient = HttpClient();
    final spectrumClient = HttpClient();
    addTearDown(() async {
      await relay.dispose();
      playerClient.close(force: true);
      spectrumClient.close(force: true);
      await upstream.close(force: true);
    });

    var upstreamRequests = 0;
    final releaseLastChunk = Completer<void>();
    upstream.listen((request) async {
      upstreamRequests++;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.bufferOutput = false;
      request.response.add(List<int>.filled(1024, 0x41));
      await request.response.flush();
      await releaseLastChunk.future;
      request.response.add(List<int>.filled(1024, 0x42));
      await request.response.close();
    });

    final playUri =
        await relay.activate('http://127.0.0.1:${upstream.port}/live.mp3');
    final playRequest = await playerClient.getUrl(playUri);
    final playResponse = await playRequest.close();
    final firstChunk = Completer<void>();
    final playDone = Completer<List<int>>();
    final playBytes = <int>[];
    playResponse.listen(
      (chunk) {
        playBytes.addAll(chunk);
        if (!firstChunk.isCompleted) firstChunk.complete();
      },
      onDone: () => playDone.complete(playBytes),
      onError: playDone.completeError,
    );
    await firstChunk.future.timeout(const Duration(seconds: 5));

    final spectrumRequest = await spectrumClient.getUrl(relay.spectrumUri!);
    final spectrumResponse = await spectrumRequest.close();
    final spectrumDone =
        spectrumResponse.fold<List<int>>(<int>[], (bytes, part) {
      bytes.addAll(part);
      return bytes;
    });
    releaseLastChunk.complete();

    final results = await Future.wait([playDone.future, spectrumDone])
        .timeout(const Duration(seconds: 5));
    expect(upstreamRequests, 1);
    expect(results[0], [
      ...List<int>.filled(1024, 0x41),
      ...List<int>.filled(1024, 0x42),
    ]);
    expect(results[1], results[0]);
  });
}
