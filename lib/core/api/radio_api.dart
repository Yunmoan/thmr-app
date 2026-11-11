import 'package:dio/dio.dart';

import '../config.dart';
import '../models/models.dart';

/// Radio 后端 — 全部免登录(FLUTTER.md 7.1)。
/// 所有 /api/* 响应带 Cache-Control: no-store,不做 HTTP 层缓存。
class RadioApi {
  RadioApi({RadioApi? debugClient, String? baseUrl})
      : _dio = (debugClient?._dio ?? Dio()) {
    _dio.options
      ..baseUrl = baseUrl ?? appConfig.radioBaseUrl
      ..connectTimeout = const Duration(seconds: 8)
      ..receiveTimeout = const Duration(seconds: 12)
      ..validateStatus = (s) => s != null && s < 500;
  }

  final Dio _dio;
  String get baseUrl => _dio.options.baseUrl;

  /// streamToken 存在时追加到流地址 / 反馈接口(状态、封面可不带,带上也无害)。
  Map<String, String> get _tokenQuery => appConfig.streamToken.isEmpty
      ? const {}
      : {'token': appConfig.streamToken};

  Never _throwApiError(Response<Object?> r) {
    final data = r.data;
    String msg = 'HTTP ${r.statusCode}';
    if (data is Map && data['error'] is String) msg = data['error'] as String;
    throw ApiException(r.statusCode ?? 0, msg);
  }

  Future<Map<String, dynamic>> _getJson(String path,
      {Map<String, dynamic>? query}) async {
    final r = await _dio.get<Object?>(path, queryParameters: query);
    if (r.statusCode != 200) _throwApiError(r);
    return (_resolveCovers(r.data) as Map).cast<String, dynamic>();
  }

  Object? _resolveCovers(Object? value) {
    if (value is List) return value.map(_resolveCovers).toList();
    if (value is Map) {
      // Must rebuild as Map<String, dynamic>: Map.map() would widen nested
      // maps to Map<dynamic, Object?>, breaking the strict casts in models.
      final resolved = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key as String;
        final item = entry.value;
        resolved[key] = key == 'coverUrl' && item is String
            ? absolutizeCover(item, baseUrl)
            : _resolveCovers(item);
      }
      return resolved;
    }
    return value;
  }

  Future<StationStatus> status(String stationId) async {
    final j = await _getJson('/api/stations/$stationId/status',
        query: _tokenQuery.isEmpty ? null : _tokenQuery);
    return StationStatus.fromJson(j);
  }

  /// 全站客户端数，按 Radio 后端返回的所有频道汇总。
  Future<int> siteListeners() async {
    final response = await _dio.get<Object?>('/api/stations');
    if (response.statusCode != 200) _throwApiError(response);
    final stations = response.data;
    if (stations is! List) throw const FormatException('Invalid station list');

    var total = 0;
    for (final station in stations) {
      final count = switch (station is Map ? station['listeners'] : null) {
        num value => value,
        String value => num.tryParse(value),
        _ => null,
      };
      if (count != null && count.isFinite && count >= 0) {
        total += count.toInt();
      }
    }
    return total;
  }

  Future<List<QueueEntry>> playlist(String stationId) async {
    final r = await _dio.get<Object?>('/api/stations/$stationId/playlist',
        queryParameters: _tokenQuery.isEmpty ? null : _tokenQuery);
    if (r.statusCode != 200) _throwApiError(r);
    final data = _resolveCovers(r.data);
    final raw = data is Map ? data['queue'] as List? : data as List?;
    return (raw ?? const []).map((e) => QueueEntry.fromJson(e)).toList();
  }

  /// 昨日实际播放记录，保留接口返回的顺序与重复播放。
  Future<List<CollectionItem>> yesterdayPlaylist(String stationId) async {
    final json = await _getJson(
        '/api/stations/${Uri.encodeComponent(stationId)}/yesterday');
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Invalid yesterday playlist');
    }
    return [
      for (final item in items)
        CollectionItem.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// 直播流地址(直连 MP3)。profileId 取自 station.bitrates 中 enabled 条目。
  String streamUrl(String stationId, String profileId) {
    final base = '$baseUrl/radio/$stationId/$profileId';
    return appConfig.streamToken.isEmpty
        ? base
        : '$base?token=${Uri.encodeQueryComponent(appConfig.streamToken)}';
  }

  /// 曲目反馈(7.3)。返回 autoSkipped 等字段。
  Future<FeedbackResult> feedback({
    required String stationId,
    required String type,
    required String contact,
    String message = '',
    TrackRef? track,
  }) async {
    final r = await _dio.post<Object?>(
      '/api/stations/$stationId/feedback',
      queryParameters: _tokenQuery.isEmpty ? null : _tokenQuery,
      data: {
        'type': type,
        'contact': contact,
        'message': message,
        'pageUrl': '',
        if (track != null)
          'track': {
            'trackId': track.trackId,
            'title': track.title,
            'artist': track.artist,
          },
      },
    );
    if (r.statusCode != 200 && r.statusCode != 201) _throwApiError(r);
    final j = (r.data as Map).cast<String, dynamic>();
    return FeedbackResult(
      ok: j['ok'] == true,
      autoSkipped: j['autoSkipped'] == true,
      trackMatchesCurrent: j['trackMatchesCurrent'] == true,
    );
  }
}

class FeedbackResult {
  final bool ok;
  final bool autoSkipped;
  final bool trackMatchesCurrent;

  const FeedbackResult({
    required this.ok,
    required this.autoSkipped,
    required this.trackMatchesCurrent,
  });
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}
