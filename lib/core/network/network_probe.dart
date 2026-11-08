import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Public, credential-free details suitable for a user-exported report.
class NetworkProbeResult {
  const NetworkProbeResult({
    required this.uri,
    this.statusCode,
    this.elapsed = Duration.zero,
    this.firstByte,
    this.remoteAddress,
    this.remotePort,
    this.dnsAddresses = const [],
    this.headers = const {},
    this.contentType = '',
    this.bytesRead = 0,
    this.body,
    this.error,
  });

  final Uri uri;
  final int? statusCode;
  final Duration elapsed;
  final Duration? firstByte;
  final String? remoteAddress;
  final int? remotePort;
  final List<String> dnsAddresses;
  final Map<String, String> headers;
  final String contentType;
  final int bytesRead;
  final Uint8List? body;
  final String? error;

  bool get reachable => statusCode != null;
  bool get successful =>
      error == null &&
      statusCode != null &&
      statusCode! >= 200 &&
      statusCode! < 400;
  bool get audio =>
      contentType.startsWith('audio/') ||
      contentType == 'application/octet-stream';

  String get statusLabel {
    if (error != null) return error!;
    final status = statusCode;
    if (status == null) return '未收到响应';
    if (status >= 200 && status < 300) return '可访问 · HTTP $status';
    if (status >= 300 && status < 400) return '可连接 · HTTP $status（重定向）';
    if (status == 401 || status == 403) return '可连接 · HTTP $status（访问受限）';
    return '可连接 · HTTP $status';
  }
}

String publicUrl(Uri uri) => Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();

/// Never exports arbitrary headers, response bodies, cookies or raw exceptions.
const diagnosticHeaderNames = {
  'server',
  'via',
  'x-cache',
  'x-cache-lookup',
  'x-served-by',
  'x-edge-location',
  'x-edge-pop',
  'x-amz-cf-pop',
  'cf-ray',
  'eo-log-uuid',
  'eo-cache-status',
  'x-cdn',
  'server-timing',
};

class NetworkProbe {
  final Set<HttpClient> _clients = {};
  bool _closed = false;

  Future<NetworkProbeResult> get(
    Uri uri, {
    int maxBytes = 4096,
    bool captureBody = false,
    bool resolveDns = true,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final watch = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'THMR-Client/1.0 (+https://thmr.yunmoan.cn)';
    if (_closed) {
      client.close(force: true);
      return NetworkProbeResult(uri: Uri.parse(publicUrl(uri)), error: '检测已取消');
    }
    _clients.add(client);
    var addresses = <String>[];
    NetworkProbeResult? received;
    try {
      Future<NetworkProbeResult> request() async {
        if (resolveDns) {
          try {
            addresses = (await InternetAddress.lookup(uri.host))
                .map((address) => address.address)
                .toSet()
                .toList();
          } on SocketException {
            // Let the actual HTTP request determine reachability as well.
          }
        }
        final request = await client.getUrl(uri);
        request.maxRedirects = 3;
        final response = await request.close();
        final firstByte = watch.elapsed;
        final connection = response.connectionInfo;
        final headers = <String, String>{};
        for (final name in diagnosticHeaderNames) {
          final value = response.headers[name]?.join(', ');
          if (value != null) {
            headers[name] = value
                .replaceAll(RegExp(r'[\r\n]'), ' ')
                .substring(0, value.length > 1024 ? 1024 : value.length);
          }
        }
        NetworkProbeResult result(int count, Uint8List? body) =>
            NetworkProbeResult(
              uri: Uri.parse(publicUrl(uri)),
              statusCode: response.statusCode,
              firstByte: firstByte,
              elapsed: watch.elapsed,
              remoteAddress: connection?.remoteAddress.address,
              remotePort: connection?.remotePort,
              dnsAddresses: addresses,
              headers: headers,
              contentType: response.headers.contentType?.mimeType ?? '',
              bytesRead: count,
              body: body,
            );
        received = result(0, null);
        if (maxBytes == 0) return received!;
        final bytes = captureBody ? BytesBuilder(copy: false) : null;
        var count = 0;
        final iterator = StreamIterator<List<int>>(response);
        try {
          while (count < maxBytes && await iterator.moveNext()) {
            final chunk = iterator.current;
            final remaining = maxBytes - count;
            final length = chunk.length > remaining ? remaining : chunk.length;
            bytes?.add(chunk.sublist(0, length));
            count += length;
          }
          return result(count, bytes?.takeBytes());
        } finally {
          // Radio endpoints never end. Bound sampling and release the socket.
          unawaited(iterator.cancel().catchError((Object _) {}));
        }
      }

      return await request().timeout(timeout);
    } catch (error) {
      final message = switch (error) {
        TimeoutException() => '连接或读取超时',
        HandshakeException() => 'TLS 握手失败',
        SocketException() => 'DNS 解析或网络连接失败',
        HttpException() => 'HTTP 连接异常',
        _ => _closed ? '检测已取消' : '检测失败',
      };
      final previous = received;
      return NetworkProbeResult(
        uri: Uri.parse(publicUrl(uri)),
        elapsed: watch.elapsed,
        statusCode: previous?.statusCode,
        firstByte: previous?.firstByte,
        remoteAddress: previous?.remoteAddress,
        remotePort: previous?.remotePort,
        dnsAddresses: addresses,
        headers: previous?.headers ?? const {},
        contentType: previous?.contentType ?? '',
        error: message,
      );
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  void close() {
    _closed = true;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
