import 'package:dio/dio.dart';

import '../config.dart';
import '../models/models.dart';
import 'radio_api.dart';

/// THMR 账号后端(FLUTTER.md 7.2)。
/// App 采用 Bearer 方案:WebView 提取一次 thmr_session,之后全部走 header。
class ThmrApi {
  ThmrApi() : _dio = Dio() {
    _dio.options
      ..baseUrl = appConfig.thmrBaseUrl
      ..connectTimeout = const Duration(seconds: 8)
      ..receiveTimeout = const Duration(seconds: 15)
      ..validateStatus = (s) => s != null && s < 500;
    // Dart 默认 UA(Dart/x.x)会被站点防火墙按机器人拦截,显式声明客户端 UA
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

  /// 他人分享(公开)。410 = 分享已过期。
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
    // Backend replies {ok, nickname}; refresh the full profile.
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
    // The endpoint returns a bare JSON array (FLUTTER.md: first item =
    // default collection). Be liberal in what we accept.
    final data = r.data;
    final List raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data['collections'] ?? data['data'] ?? const []) as List;
    } else {
      raw = const [];
    }
    return raw.map((e) => Collection.fromJson(e)).toList();
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

  /// Export payload as text (json / m3u / csv).
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

  Future<VoteStatus> castVote(String stationId) async {
    final r =
        await _dio.post<Object?>('/api/vote', data: {'stationId': stationId});
    if (r.statusCode != 200) _throwApiError(r);
    return VoteStatus.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<void> cancelVote(String stationId) async {
    final r = await _dio.delete<Object?>('/api/vote',
        queryParameters: {'stationId': stationId});
    if (r.statusCode != 200) _throwApiError(r);
  }
}

/// The public endpoint omits account-only fields such as collection.share.
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
