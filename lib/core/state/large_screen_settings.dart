import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LargeScreenLayout { adaptive, coverLeft, coverRight, centered }

enum LargeScreenQueue { hidden, next, strip, list }

enum LargeScreenFraming { fill, fit }

enum LargeScreenCoverFit { cover, contain }

enum LargeScreenIllustrationPosition { left, right }

class LargeScreenSettings {
  const LargeScreenSettings({
    this.layout = LargeScreenLayout.adaptive,
    this.queue = LargeScreenQueue.strip,
    this.framing = LargeScreenFraming.fill,
    this.coverFit = LargeScreenCoverFit.contain,
    this.cardLayout = false,
    this.illustrationPosition = LargeScreenIllustrationPosition.right,
    this.themeMode = ThemeMode.system,
    this.queueCount = 3,
    this.textScale = 1,
    this.showIllustration = true,
    this.showProgress = true,
    this.showQueueCovers = true,
    this.showControls = true,
    this.autoHideControls = true,
    this.startFullScreen = true,
  });

  final LargeScreenLayout layout;
  final LargeScreenQueue queue;
  final LargeScreenFraming framing;
  final LargeScreenCoverFit coverFit;
  final bool cardLayout;
  final LargeScreenIllustrationPosition illustrationPosition;

  /// system means inherit the app theme, including its explicit light/dark mode.
  final ThemeMode themeMode;
  final int queueCount;
  final double textScale;
  final bool showIllustration;
  final bool showProgress;
  final bool showQueueCovers;
  final bool showControls;
  final bool autoHideControls;
  final bool startFullScreen;

  LargeScreenSettings copyWith({
    LargeScreenLayout? layout,
    LargeScreenQueue? queue,
    LargeScreenFraming? framing,
    LargeScreenCoverFit? coverFit,
    bool? cardLayout,
    LargeScreenIllustrationPosition? illustrationPosition,
    ThemeMode? themeMode,
    int? queueCount,
    double? textScale,
    bool? showIllustration,
    bool? showProgress,
    bool? showQueueCovers,
    bool? showControls,
    bool? autoHideControls,
    bool? startFullScreen,
  }) =>
      LargeScreenSettings(
        layout: layout ?? this.layout,
        queue: queue ?? this.queue,
        framing: framing ?? this.framing,
        coverFit: coverFit ?? this.coverFit,
        cardLayout: cardLayout ?? this.cardLayout,
        illustrationPosition: illustrationPosition ?? this.illustrationPosition,
        themeMode: themeMode ?? this.themeMode,
        queueCount: (queueCount ?? this.queueCount).clamp(1, 8),
        textScale: (textScale ?? this.textScale).clamp(.8, 1.4),
        showIllustration: showIllustration ?? this.showIllustration,
        showProgress: showProgress ?? this.showProgress,
        showQueueCovers: showQueueCovers ?? this.showQueueCovers,
        showControls: showControls ?? this.showControls,
        autoHideControls: autoHideControls ?? this.autoHideControls,
        startFullScreen: startFullScreen ?? this.startFullScreen,
      );

  factory LargeScreenSettings.fromJson(Map<String, dynamic> json) {
    T choice<T extends Enum>(String key, List<T> values, T fallback) =>
        values.firstWhere((v) => v.name == json[key], orElse: () => fallback);
    bool flag(String key) => json[key] is bool ? json[key] as bool : true;
    final scale = json['textScale'];
    return LargeScreenSettings(
      layout: choice(
          'layout', LargeScreenLayout.values, LargeScreenLayout.adaptive),
      queue: choice('queue', LargeScreenQueue.values, LargeScreenQueue.strip),
      framing:
          choice('framing', LargeScreenFraming.values, LargeScreenFraming.fill),
      coverFit: choice(
          'coverFit', LargeScreenCoverFit.values, LargeScreenCoverFit.contain),
      themeMode: choice('themeMode', ThemeMode.values, ThemeMode.system),
      cardLayout: json['cardLayout'] == true,
      illustrationPosition: choice(
          'illustrationPosition',
          LargeScreenIllustrationPosition.values,
          LargeScreenIllustrationPosition.right),
      queueCount: json['queueCount'] is int
          ? (json['queueCount'] as int).clamp(1, 8)
          : 3,
      textScale:
          scale is num && scale.isFinite ? scale.toDouble().clamp(.8, 1.4) : 1,
      showIllustration: flag('showIllustration'),
      showProgress: flag('showProgress'),
      showQueueCovers: flag('showQueueCovers'),
      showControls: flag('showControls'),
      autoHideControls: flag('autoHideControls'),
      startFullScreen: flag('startFullScreen'),
    );
  }

  Map<String, dynamic> toJson() => {
        'layout': layout.name,
        'queue': queue.name,
        'framing': framing.name,
        'coverFit': coverFit.name,
        'cardLayout': cardLayout,
        'illustrationPosition': illustrationPosition.name,
        'themeMode': themeMode.name,
        'queueCount': queueCount,
        'textScale': textScale,
        'showIllustration': showIllustration,
        'showProgress': showProgress,
        'showQueueCovers': showQueueCovers,
        'showControls': showControls,
        'autoHideControls': autoHideControls,
        'startFullScreen': startFullScreen,
      };
}

class LargeScreenSettingsController extends StateNotifier<LargeScreenSettings> {
  LargeScreenSettingsController() : super(const LargeScreenSettings()) {
    ready = _load();
  }

  late final Future<void> ready;
  int _revision = 0;
  Future<void> _pendingSave = Future.value();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_revision != 0 || !mounted) return;
    final saved = prefs.get('largeScreen');
    if (saved is! String) return;
    try {
      final json = jsonDecode(saved);
      if (json is Map<String, dynamic>) {
        state = LargeScreenSettings.fromJson(json);
      }
    } on FormatException {
      // An invalid saved document falls back to the normal app presentation.
    }
  }

  Future<void> update(LargeScreenSettings next) {
    _revision++;
    state = next;
    final saved = jsonEncode(next.toJson());
    // Preserve the last selection even when the user changes several choices
    // before the platform preference store has finished writing the first one.
    return _pendingSave = _pendingSave.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('largeScreen', saved);
    });
  }
}

final largeScreenSettingsProvider =
    StateNotifierProvider<LargeScreenSettingsController, LargeScreenSettings>(
  (ref) => LargeScreenSettingsController(),
);
