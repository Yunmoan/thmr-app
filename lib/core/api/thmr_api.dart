import 'package:dio/dio.dart';

import '../config.dart';
import '../models/models.dart';
import 'radio_api.dart';

/// THMR 业务 API。已登录请求使用从 WebView 验证取得的 Bearer 会话。
class ThmrApi {
  ThmrApi({String? baseUrl}) : _dio = Dio() {
    _dio.options
      ..baseUrl = baseUrl ?? appConfig.thmrBaseUrl
      ..connectTimeout = const Duration(seconds: 8)
      ..receiveTimeout = const Duration(seconds: 15)
      ..validateStatus = (s) => s != null && s < 500;
    // 显式发送客户端 User-Agent，避免站点防火墙将 Dart 默认 User-Agent 识别为机器人。
    _dio.options.headers['User-Agent'] =
        'THMR-Client/1.0 (+https://thmr.yunmoan.cn)';
  }

  final Dio _dio;

  set token(String? value) {
    if (value == null || value.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $value';
    }
  }

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
    return (r.data as Map).cast<String, dynamic>();
  }

  // ---- 公开 ----

  Future<ThmrMeta> meta() async {
    final j = await _getJson('/api/meta');
    return ThmrMeta.fromJson(j);
  }

  Future<List<RadioChannel>> channels() async {
    final response = await _dio.get<Object?>('/api/channels');
    if (response.statusCode != 200) _throwApiError(response);
    return RadioChannel.enabledFromJson(response.data);
  }

  /// 读取部署端的静态开关，与网页共用 config.js。
  Future<bool> voteEnabled() async {
    final response = await _dio.get<String>(
      '/config.js',
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Cache-Control': 'no-cache'},
      ),
    );
    if (response.statusCode != 200) _throwApiError(response);
    final source = (response.data ?? '').replaceAllMapped(
      RegExp(
          r'''("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|//[^\r\n]*|/\*[\s\S]*?\*/'''),
      (match) => switch (match[1]) {
        '"features"' || "'features'" => 'features',
        '"vote"' || "'vote'" => 'vote',
        null => ' ',
        _ => '""',
      },
    );
    final config =
        RegExp(r'\bwindow\.RADIO_PUBLIC_CONFIG\s*=\s*\{').firstMatch(source);
    if (config == null) return false;
    final features = RegExp(r'(?:^|,)\s*features\s*:\s*\{([^{}]*)\}')
        .firstMatch(source.substring(config.end))?[1];
    return features != null &&
        RegExp(r'(?:^|,)\s*vote\s*:\s*true\s*(?:,|$)').hasMatch(features);
  }

  /// 读取公开分享，HTTP 410 表示分享已过期。
  Future<(Collection, List<CollectionItem>)> sharedCollection(
      String slug) async {
    final j = await _getJson('/api/collections/${Uri.encodeComponent(slug)}');
    return parseSharedCollection(j);
  }

  Future<VoteStatus> voteStatus(String stationId) async {
    final j =
        await _getJson('/api/vote/status', query: {'stationId': stationId});
    return VoteStatus.fromJson(j);
  }

  // ---- 登录态 ----

  Future<ThmrUser?> me() async {
    final r = await _dio.get<Object?>('/api/auth/me');
    if (r.statusCode == 401) return null;
    if (r.statusCode != 200) _throwApiError(r);
    final j = (r.data as Map).cast<String, dynamic>();
    return ThmrUser.fromJson(j['user'] as Map<String, dynamic>);
  }

  Future<ThmrUser> updateNickname(String nickname) async {
    final r = await _dio
        .patch<Object?>('/api/auth/profile', data: {'nickname': nickname});
    if (r.statusCode != 200) _throwApiError(r);
    // 昵称更新只返回 {ok, nickname}，随后重新获取完整用户资料。
    final user = await me();
    if (user == null) {
      throw ApiException(401, 'authentication required');
    }
    return user;
  }

  Future<void> logout() async {
    await _dio.post<Object?>('/api/auth/logout');
  }

  Future<List<Collection>> collections() async {
    final r = await _dio.get<Object?>('/api/me/collections');
    if (r.statusCode != 200) _throwApiError(r);
    // 兼容直接返回列表，以及将列表放在 collections 或 data 字段中的响应。
    final data = r.data;
    final raw = data is Map ? data['collections'] ?? data['data'] : data;
    if (raw is! List) {
      throw const FormatException('收藏夹响应缺少列表');
    }
    return raw.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('收藏夹条目格式无效');
      }
      final id = entry['id'];
      if (id is! int && (id is! String || id.trim().isEmpty)) {
        throw const FormatException('收藏夹条目缺少有效 ID');
      }
      return Collection.fromJson(entry);
    }).toList();
  }

  Future<Collection> createCollection(String name,
      {String description = ''}) async {
    final r = await _dio.post<Object?>('/api/me/collections',
        data: {'name': name, 'description': description});
    if (r.statusCode != 200 && r.statusCode != 201) _throwApiError(r);
    return Collection.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteCollection(String cid) async {
    final r = await _dio.delete<Object?>('/api/me/collections/$cid');
    if (r.statusCode != 200) _throwApiError(r);
  }

  Future<(Collection, List<CollectionItem>)> collectionDetail(String cid,
      {String sort = 'position', String order = 'asc'}) async {
    final j = await _getJson('/api/me/collections/$cid',
        query: {'sort': sort, 'order': order});
    final collection =
        Collection.fromJson(j['collection'] as Map<String, dynamic>);
    final items = ((j['items'] as List?) ?? const [])
        .map((e) => CollectionItem.fromJson(e))
        .toList();
    return (collection, items);
  }

  Future<CollectionItem> addToCollection(String cid,
      {required String stationId, required String trackId}) async {
    final r = await _dio.post<Object?>('/api/me/collections/$cid/items',
        data: {'stationId': stationId, 'trackId': trackId});
    if (r.statusCode != 200 && r.statusCode != 201) _throwApiError(r);
    return CollectionItem.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> removeItem(String cid, String itemId) async {
    final r =
        await _dio.delete<Object?>('/api/me/collections/$cid/items/$itemId');
    if (r.statusCode != 200) _throwApiError(r);
  }

  Future<FavoritesStatus> favoritesStatus(
      {required String stationId, required String trackId}) async {
    final j = await _getJson('/api/me/favorites/status',
        query: {'stationId': stationId, 'trackId': trackId});
    return FavoritesStatus.fromJson(j);
  }

  /// 以文本形式返回导出内容，支持 JSON、M3U 和 CSV。
  Future<String> exportContent(String cid, String format) async {
    final r = await _dio.get<Object?>(
      '/api/me/collections/$cid/export',
      queryParameters: {'format': format},
      options: Options(responseType: ResponseType.plain),
    );
    if (r.statusCode != 200) _throwApiError(r);
    return r.data?.toString() ?? '';
  }

  Future<void> setShare(String cid, {required bool enabled}) async {
    final r = await _dio.post<Object?>('/api/me/collections/$cid/share',
        data: {'enabled': enabled});
    if (r.statusCode != 200) _throwApiError(r);
  }

  Future<List<LibraryTrack>> searchTracks({
    required String stationId,
    required String q,
    int page = 1,
    int pageSize = 50,
    String sort = 'title',
  }) async {
    final j = await _getJson('/api/tracks/search', query: {
      'stationId': stationId,
      if (q.isNotEmpty) 'q': q,
      'page': page,
      'pageSize': pageSize,
      'sort': sort,
    });
    return ((j['tracks'] as List?) ?? const [])
        .map((e) => LibraryTrack.fromJson(e))
        .toList();
  }

  /// 返回是否已请求电台切换下一首。
  Future<bool> castVote(String stationId) async {
    final r =
        await _dio.post<Object?>('/api/vote', data: {'stationId': stationId});
    if (r.statusCode != 200) _throwApiError(r);
    return (r.data as Map)['skipTriggered'] == true;
  }

  Future<void> cancelVote(String stationId) async {
    final r = await _dio.delete<Object?>('/api/vote',
        queryParameters: {'stationId': stationId});
    if (r.statusCode != 200) _throwApiError(r);
  }
}

/// 公开接口省略 collection.share 等账号私有字段。
(Collection, List<CollectionItem>) parseSharedCollection(
    Map<String, dynamic> payload) {
  final collection = Collection.fromJson(
      Map<String, dynamic>.from(payload['collection'] as Map));
  final items = ((payload['items'] as List?) ?? const [])
      .map((item) =>
          CollectionItem.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
  return (collection, items);
}
