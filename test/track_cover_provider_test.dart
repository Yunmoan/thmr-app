import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/track_cover.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

Future<int> _decodeWidth(String url, int width) {
  final stream = TrackCover.providerFor(url, cacheWidth: width)
      .resolve(ImageConfiguration.empty);
  final result = Completer<int>();
  final listener = ImageStreamListener((info, _) {
    result.complete(info.image.width);
    info.dispose();
  }, onError: result.completeError);
  stream.addListener(listener);
  return result.future.whenComplete(() => stream.removeListener(listener));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cover sizes share both a pending download and cached bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bytes = await File('assets/brand/logo.png').readAsBytes();
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.add(bytes);
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/cover';

    await HttpOverrides.runWithHttpOverrides(() async {
      final first = _decodeWidth(url, 48);
      final second = _decodeWidth(url, 96);
      expect(await Future.wait([first, second]), [48, 96]);
      expect(await _decodeWidth(url, 128), 128);
    }, _LoopbackHttpOverrides());
    expect(requests, 1);
  });

  test('invalid cover bytes can be fetched again for the same URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bytes = await File('assets/brand/logo.png').readAsBytes();
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.add(requests == 1 ? [0, 1, 2] : bytes);
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/retry';

    await HttpOverrides.runWithHttpOverrides(() async {
      await expectLater(_decodeWidth(url, 48), throwsA(anything));
      // ResizeImage 在错误回调之后清理位图缓存。
      await Future<void>.delayed(Duration.zero);
      expect(await _decodeWidth(url, 48), 48);
    }, _LoopbackHttpOverrides());
    expect(requests, 2);
  });
}
