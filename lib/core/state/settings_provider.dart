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

/// Behavior after the mini player reaches a display edge.
enum MiniEdgeHideMode { compact, tab, hidden }

enum MiniPlayerSizePreset { small, medium, large }

/// Kept separate from AppSettings so adding a size choice does not alter its
/// const object layout during development hot reload.
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

/// 用户偏好:主题模式 + 按 station 隔离的码率选择(Web 端对齐行为)。
class AppSettings {
  final ThemeMode themeMode;
  final Map<String, String> bitrateByStation;
  final bool autoPlay;
  final AccentTheme accentTheme;
  final MiniEdgeHideMode miniEdgeHideMode;
  final bool miniShowIllustration;
  final RadioSourcePreference radioSource;

  /// 关闭按钮行为(仅桌面端生效)。
  final CloseAction closeAction;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.bitrateByStation = const {},
    this.autoPlay = false,
    this.accentTheme = AccentTheme.reimu,
    this.miniEdgeHideMode = MiniEdgeHideMode.compact,
    this.miniShowIllustration = true,
    this.closeAction = CloseAction.ask,
    this.radioSource = RadioSourcePreference.automatic,
  });

  String bitrateFor(String stationId) => bitrateByStation[stationId] ?? '';

  AppSettings copyWith({
    ThemeMode? themeMode,
    Map<String, String>? bitrateByStation,
    bool? autoPlay,
    AccentTheme? accentTheme,
    MiniEdgeHideMode? miniEdgeHideMode,
    bool? miniShowIllustration,
    CloseAction? closeAction,
    RadioSourcePreference? radioSource,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        bitrateByStation: bitrateByStation ?? this.bitrateByStation,
        autoPlay: autoPlay ?? this.autoPlay,
        accentTheme: accentTheme ?? this.accentTheme,
        miniEdgeHideMode: miniEdgeHideMode ?? this.miniEdgeHideMode,
        miniShowIllustration: miniShowIllustration ?? this.miniShowIllustration,
        closeAction: closeAction ?? this.closeAction,
        radioSource: radioSource ?? this.radioSource,
      );
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(const AppSettings()) {
    ready = _load();
  }

  /// Startup waits for persisted preferences before building the first UI.
  late final Future<void> ready;

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

  /// 记住关闭按钮行为(「不再提醒」时写入)。
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

  /// 记录码率选择(按 station 隔离持久化)。
  Future<void> setBitrate(String stationId, String profileId) async {
    final next = {...state.bitrateByStation, stationId: profileId};
    _revision++;
    state = state.copyWith(bitrateByStation: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bitrateByStation',
        next.entries.map((e) => '${e.key}=${e.value}').toList());
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController();
});
