import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/api/thmr_api.dart';

void main() {
  test('reads the live config switch without matching commented values',
      () async {
    var config = '''
window.RADIO_PUBLIC_CONFIG = {
  baseUrl: "https://radio.test",
  features: { /* vote: false */ vote: true }
};
''';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/config.js');
      expect(request.headers.value(HttpHeaders.cacheControlHeader), 'no-cache');
      request.response.headers.contentType =
          ContentType('application', 'javascript');
      request.response.write(config);
      await request.response.close();
    });
    final api = ThmrApi(baseUrl: 'http://127.0.0.1:${server.port}');
    expect(await api.voteEnabled(), isTrue);

    config = '''
window.RADIO_PUBLIC_CONFIG = {
  "features": {
    // vote: true
    "vote": false
  }
};
''';
    expect(await api.voteEnabled(), isFalse);
  });
}
