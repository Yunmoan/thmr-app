// 应用内 WebView 登录使用 Natayark OAuth。
//
// 本地回调模式在 127.0.0.1 的随机端口启动 HTTP 服务，并把 /callback 作为 OAuth 重定向地址。
// 后端写入会话 Cookie 后通过 HTTP 302 跳转到本地完成页。客户端读取原站点的 WebView Cookie，
// 并以 /api/auth/me 的结果确认会话。
// 本地回调不可用时，以 Web 落地页继续检测会话 Cookie。

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show ContentType, HttpServer, InternetAddress;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/radio_api.dart';
import '../../core/api/thmr_api.dart';
import '../../core/config.dart';
import '../../core/theme/thmr_motion.dart';
import 'android_login_keyboard.dart';

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
  double _keyboardInsetPixels = 0;
  bool _checking = false;
  Timer? _retry;
  int _attempts = 0;
  // 记录已尝试的 Cookie 值，后续轮询只验证新出现的值，减少重复请求。
  final Set<String> _triedTokens = {};

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.linux) return;
    _initEnv();
    _startLoopback();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final inset = MediaQuery.viewInsetsOf(context).bottom *
        View.of(context).devicePixelRatio;
    if (inset == _keyboardInsetPixels) return;
    _keyboardInsetPixels = inset;
    final controller = _controller;
    if (controller != null) {
      unawaited(updateAndroidLoginKeyboard(controller, inset));
    }
  }

  Future<void> _initEnv() async {
    // WebViewEnvironment 属于 WebView2。其他平台直接创建原生 WebView，并使用默认 CookieManager。
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        _env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: 'thmr_webview'),
        );
      } catch (_) {
        // 自定义环境不可用时使用默认环境。
      }
    }
    if (mounted) setState(() => _envReady = true);
  }

  Future<void> _startLoopback() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _port = server.port;
      _loopback = server;
      server.listen((request) async {
        // 本地回调仅触发会话检查，是否登录以 /api/auth/me 的验证结果为准。
        try {
          request.response.headers.contentType = ContentType.html;
          request.response.add(utf8.encode(_successPage));
          await request.response.close();
        } catch (_) {
          // 关闭 WebView 时，正在处理的本地请求可能被取消。
        }
        await _checkSession(onLanding: true);
      });
    } catch (_) {
      // 本地回调不可用时，改在网页落地后验证会话。
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
    // 部分 Windows 插件版本释放 WebViewEnvironment 时会抛出 MissingPluginException，
    // 进程结束后由系统回收相关资源。
    _env?.dispose().catchError((_) {});
    super.dispose();
  }

  Future<void> _checkSession({required bool onLanding}) async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      // CookieManager 读取的是该 WebViewEnvironment 中的 Cookie。
      final cm = CookieManager.instance(webViewEnvironment: _env);
      final cookies = await cm.getCookies(url: WebUri(appConfig.thmrBaseUrl));
      // Cookie 名称因部署而异，使用 /api/auth/me 验证非空候选值。
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
          if (e.statusCode == 429 || e.statusCode >= 500) rethrow;
          // HTTP 429 和 5xx 交给外层处理，其余 API 错误允许继续检查下一个候选值。
        }
      }
      // 到达回调或落地页时，Cookie 可能尚未可读，按间隔继续尝试。
      if (onLanding && _attempts < 12) {
        _attempts++;
        _retry?.cancel();
        _retry = Timer(const Duration(milliseconds: 800), () {
          _checking = false;
          _checkSession(onLanding: true);
        });
      }
    } catch (_) {
      // 保留登录页供用户重新加载，会话验证通过后才退出。
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('登录')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Linux 暂不支持内置登录'),
                const SizedBox(height: 8),
                const Text('你可以继续收听电台，或在网页版登录并管理收藏。',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () async {
                    var opened = false;
                    try {
                      opened = await launchUrl(Uri.parse(shareWebOrigin),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showThmrSnackBar(
                        context,
                        const SnackBar(content: Text('无法打开系统浏览器')),
                      );
                    }
                  },
                  child: const Text('打开网页版'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final ready = _envReady && _loopbackDecided;
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 键盘弹出时保留 Android 网页的布局高度。
      resizeToAvoidBottomInset: defaultTargetPlatform != TargetPlatform.android,
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
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              webViewEnvironment: _env,
              initialUrlRequest: URLRequest(url: WebUri(_loginUri.toString())),
              initialSettings: InAppWebViewSettings(
                  // 保持 WebView2 默认 Edge UA:畸形的自定义 UA
                  // 会被站点防火墙按可疑请求拦截
                  ),
              onWebViewCreated: (c) => _controller = c,
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
              onLoadStop: (controller, url) {
                if (_keyboardInsetPixels > 0) {
                  unawaited(updateAndroidLoginKeyboard(
                      controller, _keyboardInsetPixels));
                }
                // 本地回调完成页与 Web 落地页都可触发会话检查。
                final webLanding = url != null && _isWebLanding(url);
                if (webLanding) controller.stopLoading();
                _checkSession(
                    onLanding: webLanding ||
                        url?.host == '127.0.0.1' ||
                        url?.host == 'localhost');
              },
            ),
    );
  }
}

/// 本地 HTTP 服务返回的独立完成页，沿用应用的粉色纸面、宋体和绯红配色。
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
