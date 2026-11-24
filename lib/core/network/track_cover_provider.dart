import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/painting.dart';

/// 封面的下载按 URL 复用，位图仍由 Flutter 按各处需要的尺寸解码并缓存。
class TrackCoverProvider extends ImageProvider<TrackCoverProvider> {
  const TrackCoverProvider(this.url);

  final String url;

  static final _client = Dio(BaseOptions(
    responseType: ResponseType.bytes,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  static const _maxEntries = 64;
  static const _maxBytes = 16 * 1024 * 1024;
  static final _encoded = <String, Uint8List>{};
  static final _pending = <String, Future<Uint8List>>{};
  static int _encodedBytes = 0;

  @override
  Future<TrackCoverProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      TrackCoverProvider key, ImageDecoderCallback decode) {
    final completer = MultiFrameImageStreamCompleter(
      codec: key._decode(decode),
      scale: 1,
    );
    completer.addEphemeralErrorListener((_, __) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await _loadEncoded(url);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // 解码失败后可以重新下载，且旧请求的失败不会清掉较新的缓存。
      if (identical(_encoded[url], bytes)) _evictEncoded(url);
      rethrow;
    }
  }

  static Future<Uint8List> _loadEncoded(String url) {
    final cached = _encoded.remove(url);
    if (cached != null) {
      _encoded[url] = cached;
      return SynchronousFuture(cached);
    }
    return _pending.putIfAbsent(url, () async {
      // 清理发生在请求完成之后，期间不同尺寸共用同一个下载。
      try {
        return await _download(url);
      } finally {
        _pending.remove(url);
      }
    });
  }

  static Future<Uint8List> _download(String url) async {
    final response = await _client.getUri<Uint8List>(Uri.base.resolve(url));
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw StateError('封面响应为空');

    if (bytes.lengthInBytes <= _maxBytes) {
      _encoded[url] = bytes;
      _encodedBytes += bytes.lengthInBytes;
      while (_encoded.length > _maxEntries || _encodedBytes > _maxBytes) {
        _evictEncoded(_encoded.keys.first);
      }
    }
    return bytes;
  }

  static void _evictEncoded(String url) {
    _encodedBytes -= _encoded.remove(url)!.lengthInBytes;
  }

  @override
  bool operator ==(Object other) =>
      other is TrackCoverProvider && url == other.url;

  @override
  int get hashCode => url.hashCode;
}
