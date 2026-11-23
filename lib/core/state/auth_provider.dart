import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/radio_api.dart';
import '../api/network_failure.dart';
import '../api/thmr_api.dart';
import '../models/models.dart';
import 'collection_cache.dart';

/// 登录状态、当前用户和初始化进度。
class AuthState {
  final bool initialized;
  final ThmrUser? user;
  final bool loggingIn; // 登录 WebView 进行中

  const AuthState({
    this.initialized = false,
    this.user,
    this.loggingIn = false,
  });

  bool get signedIn => user != null;

  AuthState copyWith(
          {bool? initialized,
          ThmrUser? user,
          bool clearUser = false,
          bool? loggingIn}) =>
      AuthState(
        initialized: initialized ?? this.initialized,
        user: clearUser ? null : (user ?? this.user),
        loggingIn: loggingIn ?? this.loggingIn,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({ThmrApi? client})
      : api = client ?? ThmrApi(),
        super(const AuthState()) {
    _bootstrap();
  }

  // Windows 上 SharedPreferences 与 SharedPreferencesAsync 共用存储文件。
  // 会话和设置统一使用 SharedPreferences，避免独立实例以旧快照覆盖新值。
  static const _storageKey = 'thmr_session_token';
  static const _cachedUserKey = 'thmr_cached_user_v1';
  final ThmrApi api;

  Future<void> _saveCachedUser(ThmrUser? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      await prefs.remove(_cachedUserKey);
      return;
    }
    await prefs.setString(
        _cachedUserKey,
        jsonEncode({
          'token': prefs.getString(_storageKey),
          'id': user.id,
          'naidsId': user.naidsId,
          'username': user.username,
          'nickname': user.nickname,
          'email': user.email,
          'realnameVerified': user.realnameVerified,
          'createdAt': user.createdAt,
          'needsNickname': user.needsNickname,
        }));
  }

  Future<ThmrUser?> _readCachedUser(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedUserKey);
    if (raw == null) return null;
    try {
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (data['token'] != token) return null;
      return ThmrUser.fromJson(data);
    } catch (_) {
      await prefs.remove(_cachedUserKey);
      return null;
    }
  }

  Future<String?> _readToken() async =>
      (await SharedPreferences.getInstance()).getString(_storageKey);

  Future<void> _writeToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, token);
    }
  }

  Future<void> _bootstrap() async {
    final token = await _readToken();
    if (token != null && token.isNotEmpty) {
      api.token = token;
      try {
        final user = await api.me();
        if (user != null) {
          await _saveCachedUser(user);
          state = state.copyWith(initialized: true, user: user);
          return;
        }
      } on ApiException catch (e) {
        if (e.statusCode != 401) {
          final cached = await _readCachedUser(token);
          state = state.copyWith(initialized: true, user: cached);
          return;
        }
      } catch (error) {
        final cached =
            isNetworkFailure(error) ? await _readCachedUser(token) : null;
        state = state.copyWith(initialized: true, user: cached);
        return;
      }
    }
    // 会话无效或本地无 token 时，清除本地会话和用户快照。
    await _writeToken(null);
    await _saveCachedUser(null);
    api.token = null;
    state = state.copyWith(initialized: true, clearUser: true);
  }

  /// 验证 WebView 取得的会话 token，成功后再持久化。
  Future<void> signInWithToken(String token) async {
    final previousToken = await _readToken();
    api.token = token;
    try {
      final user = await api.me();
      if (user == null) throw ApiException(401, 'authentication required');
      await _writeToken(token);
      await _saveCachedUser(user);
      state = state.copyWith(user: user);
    } catch (_) {
      api.token = previousToken;
      rethrow;
    }
  }

  Future<void> logout() async {
    final userId = state.user?.id;
    try {
      await api.logout();
    } catch (_) {
      // 网络失败也继续清本地
    }
    await _writeToken(null);
    await _saveCachedUser(null);
    if (userId != null) await const CollectionCache().clearUser(userId);
    api.token = null;
    state = state.copyWith(clearUser: true);
  }

  Future<void> setNickname(String nickname) async {
    final user = await api.updateNickname(nickname);
    await _saveCachedUser(user);
    state = state.copyWith(user: user);
  }
}

final authProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController());

final publicThmrApiProvider = Provider<ThmrApi>((ref) => ThmrApi());
