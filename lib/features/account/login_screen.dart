// In-app WebView login (Natayark OAuth), see FLUTTER.md 6.2.
//
// Loopback flow (localhost origins are whitelisted by the backend):
//   1. this screen starts a tiny HTTP server on 127.0.0.1:<random>;
//   2. the OAuth redirect param points at http://127.0.0.1:<port>/callback;
//   3. after authorization the backend sets the session cookie and 302s to
//      our loopback URL — the webview renders a self-contained "done" page,
//      never the web app;
//   4. meanwhile we read the webview cookies and validate each candidate
//      against /api/auth/me (the production cookie name is deploy-specific,
//      so we never hard-code it).
// Fallback: if the backend rejects the loopback origin it redirects to the
// web landing page — we freeze it there and keep polling cookies.

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show ContentType, HttpServer, InternetAddress;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/config.dart';
import '../../core/api/radio_api.dart';
import '../../core/api/thmr_api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _env;
  bool _envReady = false;
  HttpServer? _loopback;
  int _port = 0;
  bool _loopbackDecided = false;
  double _progress = 0;
  bool _checking = false;
  Timer? _retry;
  int _attempts = 0;
  // 已验证过的 cookie 值:重试轮只验证新出现的,避免重复请求触发 WAF 限频
  final Set<String> _triedTokens = {};
  String? _diag;

  @override
  void initState() {
    super.initState();
    _initEnv();
    _startLoopback();
  }

  Future<void> _initEnv() async {
    // WebViewEnvironment is a WebView2-only API. Android and iOS create their
    // platform WebView directly and use the default CookieManager instance.
    if (defaultTargetPlatform != TargetPlatform.windows) {
      if (mounted) setState(() => _envReady = true);
      return;
    }
    try {
      _env = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: 'thmr_webview'),
      );
      _envReady = true;
    } catch (e) {
      if (mounted) setState(() => _diag = 'WebView 环境初始化失败:$e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _startLoopback() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = server.port;
      _loopback = server;
      server.listen((request) async {
        // Any hit on our loopback means the backend has finished the OAuth
        // exchange and the session cookie is already stored.
        try {
          request.response.headers.contentType = ContentType.html;
          request.response.add(utf8.encode(_successPage));
          await request.response.close();
        } catch (_) {
          // webview may cancel the connection on close
        }
        if (mounted) {
          setState(() => _diag = '已收到登录回调,正在建立会话…');
          await _checkSession(onLanding: true);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _diag = '本地回调服务不可用,改用页面内完成检测');
      }
    }
    if (mounted) setState(() => _loopbackDecided = true);
  }

  Uri get _loginUri {
    final redirect =
        _port > 0 ? 'http://127.0.0.1:$_port/callback' : '$shareWebOrigin/';
    return Uri.parse(
        '${appConfig.thmrBaseUrl}/api/auth/login?redirect=${Uri.encodeComponent(redirect)}');
  }

  bool _isWebLanding(Uri url) =>
      url.host == Uri.parse(appConfig.thmrBaseUrl).host &&
      !url.path.startsWith('/api/auth');

  @override
  void dispose() {
    _retry?.cancel();
    _loopback?.close(force: true);
    // WindowsWebViewEnvironment.dispose throws MissingPluginException in
    // this plugin version; the OS reclaims the env with the process.
    _env?.dispose().catchError((_) {});
    super.dispose();
  }

  Future<void> _checkSession({required bool onLanding}) async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      // The cookie reader must share the webview's WebViewEnvironment.
      final cm = CookieManager.instance(webViewEnvironment: _env);
      final cookies = await cm.getCookies(url: WebUri(appConfig.thmrBaseUrl));
      // The production session cookie name is deploy-specific: validate
      // every cookie value against /api/auth/me instead of trusting names.
      final api = ThmrApi();
      for (final c in cookies) {
        final value = c.value;
        if (value == null || value.isEmpty) continue;
        if (!_triedTokens.add(value)) continue;
        try {
          api.token = value;
          final user = await api.me();
          if (user != null) {
            _retry?.cancel();
            if (mounted) Navigator.of(context).pop(value);
            return;
          }
        } on ApiException catch (e) {
          if (e.statusCode != 401) rethrow;
        }
      }
      // Not found yet: retry a few times (cookie may still be settling).
      if (onLanding && _attempts < 12) {
        _attempts++;
        _retry?.cancel();
        _retry = Timer(const Duration(milliseconds: 800), () {
          _checking = false;
          _checkSession(onLanding: true);
        });
        if (mounted) {
          setState(() => _diag = '已授权,正在建立会话…(第 $_attempts 次)');
        }
        return;
      }
      final names = cookies.map((c) => c.name).toSet().toList();
      if (mounted) {
        setState(() => _diag = names.isEmpty
            ? '未读到任何 Cookie(环境异常,请重启应用再试)'
            : '会话验证失败,当前 Cookie:$names');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _diag = e is ApiException && e.statusCode == 403
            ? '请求被站点防火墙拦截,请稍后重试或联系管理员'
            : '会话读取失败,请截图反馈:$e');
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _envReady && _loopbackDecided;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('登录 · Natayark 统一认证'),
        actions: [
          IconButton(
            tooltip: '重新加载',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _attempts = 0;
              _triedTokens.clear();
              _controller?.reload();
            },
          ),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_diag != null)
            Material(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Text(_diag!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.85))),
                ),
              ),
            ),
          Expanded(
            child: !ready
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    webViewEnvironment: _env,
                    initialUrlRequest:
                        URLRequest(url: WebUri(_loginUri.toString())),
                    initialSettings: InAppWebViewSettings(
                        // 保持 WebView2 默认 Edge UA:畸形的自定义 UA
                        // 会被站点防火墙按可疑请求拦截
                        ),
                    onWebViewCreated: (c) => _controller = c,
                    onProgressChanged: (_, p) =>
                        setState(() => _progress = p / 100),
                    onLoadStop: (_, url) {
                      // Loopback success page or (fallback) web landing page.
                      final landed = url != null &&
                          (url.host == '127.0.0.1' ||
                              url.host == 'localhost' ||
                              _isWebLanding(url));
                      if (url != null && _isWebLanding(url)) {
                        _controller?.stopLoading();
                      }
                      _checkSession(onLanding: landed);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Self-contained success page shown by the loopback server — same design
/// language as the app (paper pink, serif, crimson).
const String _successPage = '''
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>登录成功 · THMR</title>
<style>
  body { margin: 0; height: 100vh; display: flex; align-items: center;
         justify-content: center; background: linear-gradient(180deg, #fbf2f4, #ead8de);
         color: #24161a; font-family: "Source Han Serif SC", "Noto Serif SC", serif; }
  .card { text-align: center; padding: 42px 52px; background: rgba(255,251,252,.92);
          border: 1px solid rgba(84,34,46,.16); border-radius: 10px;
          box-shadow: 0 12px 34px rgba(84,34,46,.10); }
  .eyebrow { font-size: 12px; letter-spacing: .28em; color: #c65a69; font-weight: 700; }
  h1 { font-size: 30px; margin: 14px 0 8px; font-weight: 900; }
  p { margin: 0; color: #6f5960; font-size: 14px; }
</style>
</head>
<body>
  <div class="card">
    <div class="eyebrow">TOUHOU MUSIC RADIO</div>
    <h1>登录成功</h1>
    <p>会话已建立,正在返回客户端…</p>
  </div>
</body>
</html>
''';
