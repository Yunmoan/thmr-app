import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import '../network/network_probe.dart';
import 'system_memory.dart';

class DiagnosticTarget {
  const DiagnosticTarget(this.id, this.name, this.url);
  final String id;
  final String name;
  final String url;
}

const diagnosticTargets = [
  DiagnosticTarget('openapi', 'ZGIT Network OPENAPI', 'https://api.zyghit.cn'),
  DiagnosticTarget(
      'updater', 'THMR 更新检查服务', 'https://api.zyghit.cn/updater/thmr'),
  DiagnosticTarget('source2', 'THMR 流媒体服务 · 源 2', 'https://radio.zyghit.cn'),
  DiagnosticTarget('source1', 'THMR 流媒体服务 · 源 1', 'https://radio.yunmoan.cn'),
  DiagnosticTarget('website', 'THMR 网站在线服务', 'https://thmr.yunmoan.cn'),
  DiagnosticTarget('account', 'Natayark ID 账户服务', 'https://account.naids.com'),
  DiagnosticTarget(
      'staticassets', 'Natayark 静态资源服务', 'https://staticassets.naids.com'),
];

class IpLocation {
  const IpLocation(this.ip, this.location);
  final String ip;
  final List<String> location;
  String get description =>
      location.where((part) => part.trim().isNotEmpty).join(' · ');

  factory IpLocation.fromJson(Object? json) {
    if (json is! Map ||
        (json['ret'] != 0 && json['ret'] != 'ok') ||
        json['data'] is! Map) {
      throw const FormatException('IP 服务返回无效数据');
    }
    final data = json['data'] as Map;
    final ip = data['ip'];
    final location = data['location'];
    if (ip is! String ||
        InternetAddress.tryParse(ip) == null ||
        location is! List ||
        location.any((part) => part is! String)) {
      throw const FormatException('IP 服务返回无效数据');
    }
    return IpLocation(ip, location.cast<String>());
  }
}

String formatBytes(int? bytes) {
  if (bytes == null) return '系统未提供';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class DiagnosticsService {
  DiagnosticsService({NetworkProbe? probe}) : probe = probe ?? NetworkProbe();
  final NetworkProbe probe;

  Future<NetworkProbeResult> check(DiagnosticTarget target) => probe.get(
        Uri.parse(target.url),
        maxBytes: 0,
      );

  Future<IpLocation> publicIp() async {
    final result = await probe.get(Uri.parse('https://myip.ipip.net/json'),
        maxBytes: 16384, captureBody: true);
    if (!result.successful || result.body == null) {
      throw const FormatException('公网 IP 查询失败，可重新诊断');
    }
    return IpLocation.fromJson(jsonDecode(utf8.decode(result.body!)));
  }

  Future<Map<String, String>> environment(String clientVersion) async {
    final values = <String, String>{
      '客户端版本': clientVersion,
      '操作系统': Platform.operatingSystem,
      '系统版本': Platform.operatingSystemVersion,
      '系统架构': Abi.current().toString(),
      '处理器逻辑核心': '${Platform.numberOfProcessors}',
      'Dart 运行环境': Platform.version,
      '系统语言': Platform.localeName,
      '运行进程 PID': '$pid',
    };
    try {
      values['应用当前内存（RSS）'] = formatBytes(ProcessInfo.currentRss);
      values['应用峰值内存（RSS）'] = formatBytes(ProcessInfo.maxRss);
    } catch (_) {
      values['应用内存'] = '当前系统不支持读取';
    }
    final memory = await readSystemMemory();
    values['系统总内存'] = formatBytes(memory.total);
    values['系统可用内存'] = formatBytes(memory.available);
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      values['本机 IP / 网络接口'] = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            '${interface.name} · ${address.address}',
      ].join('\n');
      if (values['本机 IP / 网络接口']!.isEmpty) {
        values['本机 IP / 网络接口'] = '未发现可用的网络接口';
      }
    } catch (_) {
      values['本机 IP / 网络接口'] = '系统未允许读取网络接口';
    }
    return values;
  }

  void close() => probe.close();
}

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    this.startedAt,
    this.running = false,
    this.environment = const {},
    this.ipLocation,
    this.ipError,
    this.services = const {},
  });

  final DateTime? startedAt;
  final bool running;
  final Map<String, String> environment;
  final IpLocation? ipLocation;
  final String? ipError;
  final Map<String, NetworkProbeResult> services;

  DiagnosticsSnapshot copyWith({
    bool? running,
    Map<String, String>? environment,
    IpLocation? ipLocation,
    String? ipError,
    Map<String, NetworkProbeResult>? services,
  }) =>
      DiagnosticsSnapshot(
        startedAt: startedAt,
        running: running ?? this.running,
        environment: environment ?? this.environment,
        ipLocation: ipLocation ?? this.ipLocation,
        ipError: ipError ?? this.ipError,
        services: services ?? this.services,
      );

  String toText(
      {Map<String, String> playback = const {},
      Map<String, String> display = const {}}) {
    final out = StringBuffer('东方音乐电台 THMR · 网络诊断报告\n');
    out.writeln('检测时间：${startedAt?.toLocal().toIso8601String() ?? '未检测'}');
    out.writeln('检测状态：${running ? '进行中' : '已完成'}');
    out.writeln('\n[公网 IP 与属地]');
    out.writeln('查询服务：https://myip.ipip.net/json');
    out.writeln('公网 IP：${ipLocation?.ip ?? ipError ?? '未获取'}');
    out.writeln('IP 属地：${ipLocation?.description ?? '未获取'}');
    out.writeln('\n[本机环境]');
    for (final entry in {...environment, ...display}.entries) {
      out.writeln('${entry.key}：${entry.value}');
    }
    out.writeln('\n[播放来源]');
    for (final entry in playback.entries) {
      out.writeln('${entry.key}：${entry.value}');
    }
    out.writeln('\n[服务可访问性与 CDN 连接]');
    for (final target in diagnosticTargets) {
      out.writeln('\n${target.name}');
      out.writeln('地址：${target.url}');
      final result = services[target.id];
      if (result == null) {
        out.writeln('结果：未完成');
        continue;
      }
      out.writeln('结果：${result.statusLabel}');
      out.writeln('检测地址：${publicUrl(result.uri)}');
      out.writeln('响应耗时：${result.elapsed.inMilliseconds} ms');
      out.writeln('HTTP 状态：${result.statusCode ?? '未收到响应'}');
      out.writeln('实际连接 IP：${result.remoteAddress ?? '未获取'}');
      out.writeln('端口：${result.remotePort ?? '未获取'}');
      out.writeln('DNS 地址：${result.dnsAddresses.join(', ')}');
      for (final entry in result.headers.entries) {
        out.writeln('${entry.key}：${entry.value}');
      }
    }
    out.writeln('\n说明：连接 IP 为本次请求的实际对端；CDN 未公开节点名称时仅记录连接 IP 和响应标识。');
    out.writeln('HTTP 401/403 表示已连接到服务但访问受限，并不等于网络不可达。');
    out.writeln('本报告不包含登录凭据、Cookie 或流媒体访问密钥。');
    return out.toString();
  }
}
