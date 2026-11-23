import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/thmr_colors.dart';
import '../network/radio_sources.dart';

/// 点窗口关闭按钮时的行为(桌面端)。
enum CloseAction {
  /// 每次弹窗询问。
  ask,

  /// 直接退出程序。
  exit,

  /// 隐藏到托盘,后台继续放送。
  tray,
}

/// 迷你播放器靠近屏幕边缘后的隐藏方式。
enum MiniEdgeHideMode { compact, tab, hidden }

enum MiniPlayerSizePreset { small, medium, large }

/// 单独管理和持久化迷你播放器的尺寸预设。
class MiniPlayerSizeController extends StateNotifier<MiniPlayerSizePreset> {
  MiniPlayerSizeController() : super(MiniPlayerSizePreset.medium) {
    _load();
  }

  int _revision = 0;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_revision != 0) return;
    state = MiniPlayerSizePreset.values.firstWhere(
      (size) => size.name == prefs.getString('miniPlayerSize'),
      orElse: () => MiniPlayerSizePreset.medium,
    );
  }

  Future<void> setSize(MiniPlayerSizePreset size) async {
    _revision++;
    state = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('miniPlayerSize', size.name);
  }
}

final miniPlayerSizeProvider =
    StateNotifierProvider<MiniPlayerSizeController, MiniPlayerSizePreset>(
        (ref) => MiniPlayerSizeController());

/// 应用偏好，包括外观、播放、启动行为、桌面窗口设置和开发者模式。
class AppSettings {
  final ThemeMode themeMode;
  final Map<String, String> bitrateByStation;
  final String? selectedStationId;
  final bool autoPlay;
  final AccentTheme accentTheme;
  final MiniEdgeHideMode miniEdgeHideMode;
  final bool miniShowIllustration;
  final RadioSourcePreference radioSource;
  final bool developerMode;

  /// 关闭按钮行为(仅桌面端生效)。
  final CloseAction closeAction;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.bitrateByStation = const {},
    this.selectedStationId,
    this.autoPlay = false,
    this.accentTheme = AccentTheme.reimu,
    this.miniEdgeHideMode = MiniEdgeHideMode.compact,
    this.miniShowIllustration = true,
    this.closeAction = CloseAction.ask,
    this.radioSource = RadioSourcePreference.automatic,
    this.developerMode = kDebugMode,
  });

  String bitrateFor(String stationId) => bitrateByStation[stationId] ?? '';

  AppSettings copyWith({
    ThemeMode? themeMode,
    Map<String, String>? bitrateByStation,
    String? selectedStationId,
    bool? autoPlay,
    AccentTheme? accentTheme,
    MiniEdgeHideMode? miniEdgeHideMode,
    bool? miniShowIllustration,
    CloseAction? closeAction,
    RadioSourcePreference? radioSource,
    bool? developerMode,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        bitrateByStation: bitrateByStation ?? this.bitrateByStation,
        selectedStationId: selectedStationId ?? this.selectedStationId,
        autoPlay: autoPlay ?? this.autoPlay,
        accentTheme: accentTheme ?? this.accentTheme,
        miniEdgeHideMode: miniEdgeHideMode ?? this.miniEdgeHideMode,
        miniShowIllustration: miniShowIllustration ?? this.miniShowIllustration,
        closeAction: closeAction ?? this.closeAction,
        radioSource: radioSource ?? this.radioSource,
        developerMode: developerMode ?? this.developerMode,
      );
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController({this.debugBuild = kDebugMode})
      : super(AppSettings(developerMode: debugBuild)) {
    ready = _load();
  }

  /// 启动时读取已保存的应用偏好。
  late final Future<void> ready;
  final bool debugBuild;

  // 分开保存调试构建和正式构建的开关，避免覆盖安装时意外开启正式版的开发者模式。
  String get _developerModeKey =>
      debugBuild ? 'developerMode.debug' : 'developerMode';

  int _revision = 0;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_revision != 0) return;
    final modeIdx = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    final autoPlay = prefs.getBool('autoPlay') ?? false;
    final accentIdx = prefs.getInt('accentTheme') ?? 0;
    final closeAction = CloseAction.values.firstWhere(
      (a) => a.name == prefs.getString('closeAction'),
      orElse: () => CloseAction.ask,
    );
    final miniEdgeHideMode = MiniEdgeHideMode.values.firstWhere(
      (mode) => mode.name == prefs.getString('miniEdgeHideMode'),
      orElse: () => MiniEdgeHideMode.compact,
    );
    state = AppSettings(
      autoPlay: autoPlay,
      selectedStationId: prefs.getString('selectedStationId'),
      radioSource: RadioSourcePreference.values.firstWhere(
        (source) => source.name == prefs.getString('radioSource'),
        orElse: () => RadioSourcePreference.automatic,
      ),
      accentTheme:
          AccentTheme.values[accentIdx.clamp(0, AccentTheme.values.length - 1)],
      closeAction: closeAction,
      miniEdgeHideMode: miniEdgeHideMode,
      miniShowIllustration: prefs.getBool('miniShowIllustration') ?? true,
      themeMode: ThemeMode.values[modeIdx.clamp(0, 2)],
      developerMode: prefs.getBool(_developerModeKey) ?? debugBuild,
      bitrateByStation:
          (prefs.getStringList('bitrateByStation') ?? const <String>[])
              .fold<Map<String, String>>({}, (m, entry) {
        final i = entry.indexOf('=');
        if (i > 0) m[entry.substring(0, i)] = entry.substring(i + 1);
        return m;
      }),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _revision++;
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setAppearance(ThemeMode mode, AccentTheme accent) async {
    _revision++;
    state = state.copyWith(themeMode: mode, accentTheme: accent);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt('themeMode', mode.index),
      prefs.setInt('accentTheme', accent.index),
    ]);
  }

  Future<void> setAccentTheme(AccentTheme theme) async {
    _revision++;
    state = state.copyWith(accentTheme: theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentTheme', theme.index);
  }

  Future<void> setAutoPlay(bool value) async {
    _revision++;
    state = state.copyWith(autoPlay: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoPlay', value);
  }

  Future<void> setRadioSource(RadioSourcePreference source) async {
    _revision++;
    state = state.copyWith(radioSource: source);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('radioSource', source.name);
  }

  /// 记住用户在关闭确认框或设置页中选择的关闭行为。
  Future<void> setCloseAction(CloseAction action) async {
    _revision++;
    state = state.copyWith(closeAction: action);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('closeAction', action.name);
  }

  Future<void> setMiniEdgeHideMode(MiniEdgeHideMode mode) async {
    _revision++;
    state = state.copyWith(miniEdgeHideMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('miniEdgeHideMode', mode.name);
  }

  Future<void> setMiniShowIllustration(bool value) async {
    _revision++;
    state = state.copyWith(miniShowIllustration: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('miniShowIllustration', value);
  }

  Future<void> setDeveloperMode(bool enabled) async {
    await ready;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_developerModeKey, enabled)) {
      throw StateError('无法保存开发者模式设置');
    }
    if (mounted) state = state.copyWith(developerMode: enabled);
  }

  /// 记录码率选择(按 station 隔离持久化)。
  Future<void> setBitrate(String stationId, String profileId) async {
    final next = {...state.bitrateByStation, stationId: profileId};
    _revision++;
    state = state.copyWith(bitrateByStation: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bitrateByStation',
        next.entries.map((e) => '${e.key}=${e.value}').toList());
  }

  Future<void> selectStation(String stationId) async {
    if (state.selectedStationId == stationId) return;
    _revision++;
    state = state.copyWith(selectedStationId: stationId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedStationId', stationId);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController();
});
