import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

typedef StoredSession = ({String token, ThmrUser? user});

/// 将令牌和对应的离线用户资料作为同一条记录保存，避免切换账号时混用快照。
class SessionStore {
  const SessionStore({
    this.storage = const FlutterSecureStorage(
      // macOS 发行包使用登录钥匙串，无需额外申请钥匙串共享权限。
      mOptions: MacOsOptions(useDataProtectionKeyChain: false),
    ),
  });

  final FlutterSecureStorage storage;
  static const _key = 'thmr_auth_session_v2';
  static const _oldToken = 'thmr_session_token';
  static const _oldUser = 'thmr_cached_user_v1';

  Future<StoredSession?> read() async {
    final raw = await storage.read(key: _key);
    final prefs = await SharedPreferences.getInstance();
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;
      final session = (
        token: data['token'] as String,
        user: user == null ? null : ThmrUser.fromJson(user),
      );
      // 上次迁移可能在写入安全存储后、清理旧键前中断。
      await _removeLegacy(prefs);
      return session;
    }
    final token = prefs.getString(_oldToken);
    if (token == null || token.isEmpty) {
      await _removeLegacy(prefs);
      return null;
    }
    ThmrUser? user;
    final cached = prefs.getString(_oldUser);
    if (cached != null) {
      try {
        final data = jsonDecode(cached);
        if (data is Map<String, dynamic> && data['token'] == token) {
          user = ThmrUser.fromJson(data);
        }
      } catch (_) {
        // 旧资料损坏时仍迁移令牌，联网验证后会刷新用户资料。
      }
    }
    await save(token, user);
    return (token: token, user: user);
  }

  Future<void> save(String token, ThmrUser? user) async {
    final raw = jsonEncode({
      'token': token,
      'user': user == null
          ? null
          : {
              'id': user.id,
              'naidsId': user.naidsId,
              'username': user.username,
              'nickname': user.nickname,
              'email': user.email,
              'realnameVerified': user.realnameVerified,
              'createdAt': user.createdAt,
              'needsNickname': user.needsNickname,
            },
    });
    await storage.write(key: _key, value: raw);
    if (await storage.read(key: _key) != raw) {
      throw StateError('无法确认安全存储已保存会话');
    }
    await _removeLegacy(await SharedPreferences.getInstance());
  }

  Future<void> clear() async {
    await _removeLegacy(await SharedPreferences.getInstance());
    await storage.delete(key: _key);
  }

  Future<void> _removeLegacy(SharedPreferences prefs) async {
    for (final key in [_oldUser, _oldToken]) {
      if (prefs.containsKey(key) && !await prefs.remove(key)) {
        throw StateError('无法清理旧会话');
      }
    }
  }
}
