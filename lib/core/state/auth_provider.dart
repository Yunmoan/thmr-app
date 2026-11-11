import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/radio_api.dart';
import '../api/network_failure.dart';
import '../api/thmr_api.dart';
import '../models/models.dart';
import 'collection_cache.dart';

/// 认证状态:token 存储后请求统一 Bearer(FLUTTER.md 第六章)。
/// 注:必须与 SettingsController 用同一套 SharedPreferences(legacy 实例)。
/// Windows 端 legacy 与 SharedPreferencesAsync 是两个独立缓存实例却读写
/// 同一个文件,混用会互相整份覆盖(登录 token 曾因此丢失)。
/// M2 若接入 flutter_secure_storage(Windows 需 VS 组件 "C++ ATL"),
/// 需把此处整体迁走,不要与 legacy 混写同一键。
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
    // 401 / 无 token → 清除引导重登(会话 TTL 168h)
    await _writeToken(null);
    await _saveCachedUser(null);
    api.token = null;
    state = state.copyWith(initialized: true, clearUser: true);
  }

  /// WebView 登录流程提取到的会话 token(M2 完整接入)。
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
