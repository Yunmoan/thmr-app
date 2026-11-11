// Shared audio engine: one media_kit player for the whole app, plus the
// platform glue that keeps playback alive in the background:
//   - Android / iOS : audio_service foreground service + notification
//   - Windows       : SMTC (system media transport controls)
//   - macOS         : Now Playing info center + remote commands (media keys)
//   - Linux         : MPRIS over D-Bus

import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:smtc_windows/smtc_windows.dart';
import '../platform/desktop_window.dart';
import 'linux_media_controls.dart';
import 'macos_media_controls.dart';

/// The single player instance shared by the UI controller and the
/// background handler.
final Player enginePlayer = Player(
  configuration: const PlayerConfiguration(
    bufferSize: 8 * 1024 * 1024,
    logLevel: MPVLogLevel.warn,
  ),
);

Future<void> Function()? _mediaPlay;
Future<void> Function()? _mediaPause;
Future<void> Function()? _mediaStop;
Future<void> Function(double)? _mediaVolume;

void registerMediaControls({
  required Future<void> Function() play,
  required Future<void> Function() pause,
  required Future<void> Function() stop,
  Future<void> Function(double)? volume,
}) {
  _mediaPlay = play;
  _mediaPause = pause;
  _mediaStop = stop;
  _mediaVolume = volume;
}

void unregisterMediaControls() {
  _mediaPlay = null;
  _mediaPause = null;
  _mediaStop = null;
  _mediaVolume = null;
}

Future<void> _playFromSystem() => (_mediaPlay ?? enginePlayer.play)();
Future<void> _pauseFromSystem() => (_mediaPause ?? enginePlayer.pause)();
Future<void> _stopFromSystem() => (_mediaStop ?? enginePlayer.stop)();

enum SystemMediaCommand { play, pause, stop }

Future<void> dispatchSystemMediaCommand(SystemMediaCommand command) =>
    switch (command) {
      SystemMediaCommand.play => _playFromSystem(),
      SystemMediaCommand.pause => _pauseFromSystem(),
      SystemMediaCommand.stop => _stopFromSystem(),
    };

MediaItem mediaItemForTrack({
  required String trackId,
  required int startedAtMs,
  required String title,
  required String artist,
  String? artUri,
  int durationSec = 0,
}) =>
    MediaItem(
      id: 'thmr-$trackId-$startedAtMs',
      title: title,
      artist: artist,
      artUri: artUri != null && artUri.isNotEmpty ? Uri.tryParse(artUri) : null,
      duration: durationSec > 0 ? Duration(seconds: durationSec) : null,
    );

Future<void> _handleMediaButton(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    debugPrint('System media command failed: $error');
  }
}

/// audio_service handler (mobile): exposes play/pause to the notification
/// and keeps the foreground service alive while playback runs.
class ThmrAudioHandler extends BaseAudioHandler {
  ThmrAudioHandler() {
    enginePlayer.stream.playing.listen((playing) {
      playbackState.add(playbackState.value.copyWith(
        playing: playing,
        processingState: mediaItem.value == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        controls: [playing ? MediaControl.pause : MediaControl.play],
        androidCompactActionIndices: const [0],
      ));
    });
    enginePlayer.stream.buffering.listen((buffering) {
      if (mediaItem.value == null) return;
      playbackState.add(playbackState.value.copyWith(
        processingState: buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
      ));
    });
    enginePlayer.stream.completed.listen((done) {
      if (done) {
        playbackState.add(playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
        ));
      }
    });
  }

  @override
  Future<void> play() async {
    await dispatchSystemMediaCommand(SystemMediaCommand.play);
  }

  @override
  Future<void> pause() async {
    await dispatchSystemMediaCommand(SystemMediaCommand.pause);
  }

  @override
  Future<void> stop() async {
    await dispatchSystemMediaCommand(SystemMediaCommand.stop);
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: const [],
    ));
  }

  /// Push the current station track to the notification / lock screen.
  void updateNowPlaying({
    required String trackId,
    required int startedAtMs,
    required String title,
    required String artist,
    String? artUri,
    int durationSec = 0,
  }) {
    mediaItem.add(mediaItemForTrack(
      trackId: trackId,
      startedAtMs: startedAtMs,
      title: title,
      artist: artist,
      artUri: artUri,
      durationSec: durationSec,
    ));
    final playing = enginePlayer.state.playing;
    playbackState.add(playbackState.value.copyWith(
      playing: playing,
      processingState: AudioProcessingState.ready,
      controls: [playing ? MediaControl.pause : MediaControl.play],
      androidCompactActionIndices: const [0],
    ));
  }

  void updatePosition(int positionSec) {
    playbackState.add(playbackState.value.copyWith(
      updatePosition: Duration(seconds: positionSec.clamp(0, 86400)),
    ));
  }

  void clearNowPlaying() {
    mediaItem.add(null);
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: const [],
      updatePosition: Duration.zero,
    ));
  }
}

final ThmrAudioHandler audioHandler = ThmrAudioHandler();

final _linuxMedia = LinuxMediaControls(
  play: _playFromSystem,
  pause: _pauseFromSystem,
  stop: _stopFromSystem,
  setVolume: (value) => (_mediaVolume ?? enginePlayer.setVolume)(value),
  raise: restoreDesktopWindow,
);
StreamSubscription<double>? _linuxVolumeSubscription;

final _macosMedia = MacosMediaControls(
  play: _playFromSystem,
  pause: _pauseFromSystem,
  stop: _stopFromSystem,
);

Future<void> disposeSystemMediaControls() async {
  if (!kIsWeb && Platform.isLinux) {
    await _linuxVolumeSubscription?.cancel();
    _linuxVolumeSubscription = null;
    await _linuxMedia.dispose();
  }
  if (!kIsWeb && Platform.isMacOS) {
    await _macosMedia.dispose();
  }
}

// ---------------- Windows SMTC ----------------

SMTCWindows? _smtc;
bool _smtcReady = false;
Future<void>? _smtcInitFuture;

Future<void> _smtcInit() => _smtcInitFuture ??= _initializeSmtc();

Future<void> _initializeSmtc() async {
  if (_smtcReady) return;
  try {
    await SMTCWindows.initialize();
    _smtc = SMTCWindows(
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: false,
        prevEnabled: false,
        stopEnabled: false,
        fastForwardEnabled: false,
        rewindEnabled: false,
      ),
    );
    // System flyout buttons use the same live-stream state machine as the UI.
    _smtc!.buttonPressStream.listen((button) {
      switch (button) {
        case PressedButton.play:
          unawaited(_handleMediaButton(
              () => dispatchSystemMediaCommand(SystemMediaCommand.play)));
        case PressedButton.pause:
          unawaited(_handleMediaButton(
              () => dispatchSystemMediaCommand(SystemMediaCommand.pause)));
        default:
          break;
      }
    });
    _smtcReady = true;
  } catch (error) {
    _smtcReady = false;
    debugPrint('Windows media controls initialization failed: $error');
  }
}

/// Update the Windows media flyout (title / artist / cover).
/// Extract a bundled asset to a temp file (SMTC needs a real file path).
Future<String?> extractAssetToFile(String asset, String name) async {
  try {
    final data = await rootBundle.load(asset);
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

int _metadataSerial = 0;
Future<String?>? _fallbackArtwork;

Future<void> updateSystemMediaMetadata({
  required String title,
  required String artist,
  String? artUri,
  int positionSec = 0,
  int durationSec = 0,
  String trackId = '',
}) async {
  if (!kIsWeb && Platform.isLinux) {
    await _linuxMedia.update({
      'track': trackId.isEmpty ? '$title/$artist' : trackId,
      'title': title,
      'artist': artist,
      'artwork': artUri ?? '',
      'duration': durationSec.clamp(0, 86400) * 1000000,
      'position': positionSec.clamp(0, 86400) * 1000000,
    });
    return;
  }
  if (!kIsWeb && Platform.isMacOS) {
    await _macosMedia.update({
      'status': enginePlayer.state.playing ? 'Playing' : 'Paused',
      'title': title,
      'artist': artist,
      'artwork': artUri ?? '',
      'duration': durationSec.clamp(0, 86400) * 1000000,
      'position': positionSec.clamp(0, 86400) * 1000000,
    });
    return;
  }
  if (kIsWeb || !Platform.isWindows) return;
  final serial = ++_metadataSerial;
  await _smtcInit();
  if (!_smtcReady || serial != _metadataSerial) return;
  try {
    final fallback = await (_fallbackArtwork ??= extractAssetToFile(
        'assets/icons/icon-maskable-512.png', 'thmr_media.png'));
    if (serial != _metadataSerial) return;
    final uri = artUri == null ? null : Uri.tryParse(artUri);
    // The plugin documents HTTPS artwork support. Keep a local fallback.
    final thumb = uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? artUri
        : fallback;
    try {
      await _smtc!.updateMetadata(MusicMetadata(
        title: title,
        artist: artist,
        album: '东方音乐电台 THMR',
        thumbnail: thumb,
      ));
    } catch (_) {
      if (serial != _metadataSerial) return;
      if (thumb == fallback) rethrow;
      await _smtc!.updateMetadata(MusicMetadata(
        title: title,
        artist: artist,
        album: '东方音乐电台 THMR',
        thumbnail: fallback,
      ));
    }
    if (serial != _metadataSerial) return;
    await _smtc!.setPlaybackStatus(enginePlayer.state.playing
        ? PlaybackStatus.playing
        : PlaybackStatus.paused);
    await updateSystemMediaTimeline(
        positionSec: positionSec, durationSec: durationSec);
  } catch (error) {
    debugPrint('Windows media metadata update failed: $error');
  }
}

Future<void> updateSystemMediaTimeline({
  required int positionSec,
  required int durationSec,
}) async {
  if (!kIsWeb && Platform.isLinux) {
    await _linuxMedia.update({
      'position': positionSec.clamp(0, 86400) * 1000000,
      'duration': durationSec.clamp(0, 86400) * 1000000,
    });
    return;
  }
  if (!kIsWeb && Platform.isMacOS) {
    await _macosMedia.update({
      'position': positionSec.clamp(0, 86400) * 1000000,
      'duration': durationSec.clamp(0, 86400) * 1000000,
    });
    return;
  }
  if (kIsWeb || !Platform.isWindows) return;
  await _smtcInit();
  if (!_smtcReady) return;
  try {
    final duration = durationSec.clamp(0, 86400);
    final position = positionSec.clamp(0, duration);
    await _smtc!.setTimeline(PlaybackTimeline(
      positionMs: position * 1000,
      startTimeMs: 0,
      endTimeMs: duration * 1000,
    ));
  } catch (error) {
    debugPrint('Windows media timeline update failed: $error');
  }
}

Future<void> clearSystemMediaMetadata() async {
  if (!kIsWeb && Platform.isLinux) {
    await _linuxMedia.update({
      'track': '',
      'title': '',
      'artist': '',
      'artwork': '',
      'position': 0,
      'duration': 0,
    });
    return;
  }
  if (!kIsWeb && Platform.isMacOS) {
    await _macosMedia.update({
      'status': 'Stopped',
      'title': '',
      'artist': '',
      'artwork': '',
      'position': 0,
      'duration': 0,
    });
    return;
  }
  if (kIsWeb || !Platform.isWindows) return;
  final serial = ++_metadataSerial;
  await _smtcInit();
  if (!_smtcReady || serial != _metadataSerial) return;
  try {
    await _smtc!.clearMetadata();
    if (serial != _metadataSerial) return;
    await _smtc!.setPlaybackStatus(PlaybackStatus.stopped);
  } catch (error) {
    debugPrint('Windows media clear failed: $error');
  }
}

Future<void> updateSystemMediaPlayback({
  required bool playing,
  bool stopped = false,
}) async {
  if (!kIsWeb && Platform.isLinux) {
    await _linuxMedia.update({
      'status': playing
          ? 'Playing'
          : stopped
              ? 'Stopped'
              : 'Paused',
    });
    return;
  }
  if (!kIsWeb && Platform.isMacOS) {
    await _macosMedia.update({
      'status': playing
          ? 'Playing'
          : stopped
              ? 'Stopped'
              : 'Paused',
    });
    return;
  }
  if (kIsWeb || !Platform.isWindows) return;
  await _smtcInit();
  if (!_smtcReady) return;
  try {
    await _smtc!.setPlaybackStatus(playing
        ? PlaybackStatus.playing
        : stopped
            ? PlaybackStatus.stopped
            : PlaybackStatus.paused);
  } catch (error) {
    debugPrint('Windows media playback update failed: $error');
  }
}

/// Call once before runApp. Wires up whichever background layer the
/// platform needs; keeps the process alive while audio plays.
Future<void> initBackgroundAudio() async {
  if (kIsWeb) return;
  if (Platform.isAndroid || Platform.isIOS) {
    await AudioService.init(
      builder: () => audioHandler,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'cn.yunmoan.thmr.audio',
        androidNotificationChannelName: '东方音乐电台 THMR 播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
      ),
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) {
      unawaited(_handleMediaButton(_pauseFromSystem));
    });
    session.interruptionEventStream.listen((event) {
      if (event.begin) unawaited(_handleMediaButton(_pauseFromSystem));
    });
  } else if (Platform.isWindows) {
    await _smtcInit();
  } else if (Platform.isMacOS) {
    await _macosMedia.start();
  } else if (Platform.isLinux) {
    await _linuxMedia.start();
    await _linuxMedia.update({'volume': enginePlayer.state.volume / 100});
    _linuxVolumeSubscription ??= enginePlayer.stream.volume.listen((value) {
      unawaited(_linuxMedia.update({'volume': value / 100}));
    });
  }
}
