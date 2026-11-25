import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 播放器和本地频谱解码器共用一条上游直播连接，两者从 loopback 读取数据。
/// 中继保留最近一小段字节供新订阅者识别 MP3 帧。
class SharedRadioStream {
  static const _maxTailBytes = 256 * 1024;

  Future<HttpServer>? _serverFuture;
  HttpClient? _upstream;
  final Set<HttpResponse> _consumers = {};
  final Queue<Uint8List> _tail = Queue();
  int _tailBytes = 0;
  int _generation = 0;
  String? _sourceUrl;
  String? _session;
  Uri? _spectrumUri;

  Uri? get spectrumUri => _spectrumUri;

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_serve);
    return server;
  }

  Future<Uri> activate(String sourceUrl) async {
    final binding = _serverFuture ??= _bind();
    final HttpServer server;
    try {
      server = await binding;
    } catch (_) {
      if (identical(_serverFuture, binding)) _serverFuture = null;
      rethrow;
    }
    if (!identical(_serverFuture, binding)) {
      throw StateError('中继已关闭');
    }
    stop();
    final random = Random.secure();
    final token = base64UrlEncode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    _sourceUrl = sourceUrl;
    _session = token;
    final base = 'http://127.0.0.1:${server.port}';
    _spectrumUri = Uri.parse('$base/spectrum/$token');
    return Uri.parse('$base/play/$token');
  }

  void stop() {
    _generation++;
    _upstream?.close(force: true);
    _upstream = null;
    for (final response in _consumers) {
      unawaited(response.close().catchError((Object _) {}));
    }
    _consumers.clear();
    _tail.clear();
    _tailBytes = 0;
    _sourceUrl = null;
    _session = null;
    _spectrumUri = null;
  }

  Future<void> dispose() async {
    final binding = _serverFuture;
    _serverFuture = null;
    stop();
    final HttpServer? server;
    try {
      server = await binding;
    } catch (_) {
      // 绑定失败时没有监听套接字需要关闭。
      return;
    }
    await server?.close(force: true);
  }

  void _serve(HttpRequest request) {
    final parts = request.uri.pathSegments;
    final role = parts.isEmpty ? '' : parts.first;
    if (parts.length != 2 ||
        parts.last != _session ||
        (role != 'play' && role != 'spectrum')) {
      request.response.statusCode = HttpStatus.notFound;
      unawaited(request.response.close());
      return;
    }
    final response = request.response;
    response.headers.contentType = ContentType('audio', 'mpeg');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    if (request.method == 'HEAD') {
      unawaited(response.close());
      return;
    }
    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      unawaited(response.close());
      return;
    }

    response.bufferOutput = false;
    final generation = _generation;
    if (role == 'spectrum') {
      for (final bytes in _tail) {
        response.add(bytes);
      }
    }
    _consumers.add(response);
    response.done.then(
      (_) => _consumers.remove(response),
      onError: (Object _) => _consumers.remove(response),
    );
    if (role == 'play' && _upstream == null) {
      unawaited(_pump(generation, _sourceUrl!));
    }
  }

  Future<void> _pump(int generation, String sourceUrl) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..autoUncompress = false;
    _upstream = client;
    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      request.headers.set('Icy-MetaData', '0');
      final stream = await request.close();
      if (stream.statusCode != HttpStatus.ok) {
        throw HttpException('Radio returned ${stream.statusCode}');
      }
      await for (final chunk in stream) {
        if (generation != _generation) break;
        final bytes = Uint8List.fromList(chunk);
        _tail.addLast(bytes);
        _tailBytes += bytes.length;
        while (_tailBytes > _maxTailBytes && _tail.length > 1) {
          _tailBytes -= _tail.removeFirst().length;
        }
        for (final consumer in _consumers.toList()) {
          try {
            consumer.add(bytes);
          } catch (_) {
            _consumers.remove(consumer);
            unawaited(consumer.close().catchError((Object _) {}));
          }
        }
      }
    } catch (_) {
      // 上游中断后关闭本地响应，由播放器原有的重连逻辑开启新的中继会话。
    } finally {
      if (generation == _generation) {
        for (final response in _consumers) {
          unawaited(response.close().catchError((Object _) {}));
        }
        _consumers.clear();
        _upstream = null;
      }
      client.close(force: true);
    }
  }
}

final sharedRadioStream = SharedRadioStream();
