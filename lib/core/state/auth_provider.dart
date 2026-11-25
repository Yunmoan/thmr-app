import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/radio_api.dart';
import '../api/network_failure.dart';
import '../api/thmr_api.dart';
import '../models/models.dart';
import 'collection_cache.dart';
import 'session_store.dart';

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
  AuthController({ThmrApi? client, SessionStore store = const SessionStore()})
      : api = client ?? ThmrApi(),
        _store = store,
        super(const AuthState()) {
    _pending = _bootstrap();
  }

  final ThmrApi api;
  final SessionStore _store;
  String? _token;
  late Future<void> _pending;

  // 登录、修改资料和退出共用一条写入队列，旧请求不能覆盖新会话。
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _bootstrap() async {
    try {
      final saved = await _store.read();
      if (saved == null || !mounted) return;
      api.token = _token = saved.token;
      ThmrUser? user;
      try {
        user = await api.me();
      } catch (error) {
        if (error is! ApiException || error.statusCode != 401) {
          if (mounted && (isNetworkFailure(error) || error is ApiException)) {
            state = state.copyWith(user: saved.user);
          }
          return;
        }
      }
      if (!mounted) return;
      if (user == null) {
        api.token = _token = null;
        await _store.clear();
      } else {
        state = state.copyWith(user: user);
        await _store.save(saved.token, user);
      }
    } catch (_) {
      // 钥匙串锁定或迁移失败时保留持久化记录，用户仍可使用公开功能。
    } finally {
      if (mounted) state = state.copyWith(initialized: true);
    }
  }

  /// 验证 WebView 取得的会话令牌，成功写入安全存储后再更新登录状态。
  Future<void> signInWithToken(String token) => _enqueue(() async {
        api.token = token;
        try {
          final user = await api.me();
          if (user == null) throw ApiException(401, 'authentication required');
          await _store.save(token, user);
          _token = token;
          if (mounted) state = state.copyWith(user: user);
        } finally {
          api.token = _token;
        }
      });

  Future<void> logout() => _enqueue(() async {
        final userId = state.user?.id;
        try {
          await api.logout();
        } catch (_) {
          // 网络失败也继续清理本地会话。
        }
        await _store.clear();
        api.token = _token = null;
        if (mounted) state = state.copyWith(clearUser: true);
        if (userId != null) await const CollectionCache().clearUser(userId);
      });

  Future<void> setNickname(String nickname) => _enqueue(() async {
        final token = _token;
        if (token == null) throw ApiException(401, 'authentication required');
        final user = await api.updateNickname(nickname);
        await _store.save(token, user);
        if (mounted) state = state.copyWith(user: user);
      });
}

final authProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController());

final publicThmrApiProvider = Provider<ThmrApi>((ref) => ThmrApi());
