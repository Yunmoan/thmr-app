import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'shared_radio_stream.dart';
import 'spectrum_fft.dart';
import 'spectrum.dart';
import 'spectrum_linux_worker.dart';

/// Bundled minimp3 decodes only the app's tokenized loopback radio stream.
class LinuxSpectrum implements RetryableSpectrumSource {
  LinuxSpectrum._(this._streamUri, this._library);
  LinuxSpectrum.forTesting(Uri? Function() streamUri, {required String library})
      : this._(streamUri, library);

  static final instance = LinuxSpectrum._(() => sharedRadioStream.spectrumUri,
      '${File(Platform.resolvedExecutable).parent.path}/lib/libthmr_mp3.so');
  final Uri? Function() _streamUri;
  final String _library;
  _SpectrumWorker? _worker;
  final Set<Future<void>> _stopping = {};
  Timer? _watch, _startup;
  int _refs = 0, _generation = 0, _sampleRate = 44100;
  double? _upperHz;
  Uri? _uri;
  Float32List? _magnitudes;
  DateTime? _lastFrame;
  Completer<bool>? _ready;
  String? _reason;

  @override
  bool get isUnavailable => _reason != null;
  @override
  String? get unavailableReason => _reason;

  @override
  void start() {
    if (++_refs != 1) return;
    _restart();
    _watch = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_streamUri() != _uri) _restart();
    });
  }

  void _stopWorker() {
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    final future = worker.stop();
    _stopping.add(future);
    unawaited(future.whenComplete(() => _stopping.remove(future)));
  }

  void _restart() {
    final generation = ++_generation;
    if (!(_ready?.isCompleted ?? true)) _ready!.complete(false);
    final ready = _ready = Completer<bool>();
    _reason = null;
    _magnitudes = null;
    _upperHz = null;
    _lastFrame = null;
    _uri = _streamUri();
    _startup?.cancel();
    _stopWorker();
    final uri = _uri;
    if (uri == null || uri.scheme != 'http' || uri.host != '127.0.0.1') {
      _reason = '实时频谱暂不可用，请重试电台连接。';
      ready.complete(false);
      return;
    }
    void fail(String reason) {
      if (generation != _generation || _refs == 0) return;
      _startup?.cancel();
      _reason = reason;
      _magnitudes = null;
      if (!ready.isCompleted) ready.complete(false);
    }

    _worker = _SpectrumWorker(uri, _library, (frame, rate, upperHz) {
      if (generation != _generation || _refs == 0) return;
      _magnitudes = frame;
      _sampleRate = rate;
      _upperHz = upperHz;
      _lastFrame = DateTime.now();
      _reason = null;
      _startup?.cancel();
      if (!ready.isCompleted) ready.complete(true);
    }, fail);
    _startup = Timer(const Duration(seconds: 10), () {
      fail('实时频谱等待超时，请重试电台连接。');
      _stopWorker();
    });
  }

  @override
  Future<bool> retry() async {
    if (_refs == 0) return false;
    _restart();
    return _ready!.future;
  }

  @override
  Float32List? poll(int bands) {
    final frame = _magnitudes, last = _lastFrame;
    if (_refs == 0 ||
        bands <= 0 ||
        frame == null ||
        last == null ||
        DateTime.now().difference(last) > const Duration(seconds: 1)) {
      return null;
    }
    return logarithmicSpectrumBands(frame, bands, _sampleRate, maxHz: _upperHz);
  }

  @override
  void stop() {
    if (_refs == 0 || --_refs != 0) return;
    _generation++;
    _watch?.cancel();
    _startup?.cancel();
    if (!(_ready?.isCompleted ?? true)) _ready!.complete(false);
    _magnitudes = null;
    _stopWorker();
  }

  Future<void> dispose() async {
    _refs = 1;
    stop();
    await Future.wait(_stopping.toList());
  }
}

/// Keep the command handshake alive when stop races isolate startup. Closing
/// the event port immediately could otherwise leave a decoder isolate running.
class _SpectrumWorker {
  _SpectrumWorker(
      Uri uri,
      String library,
      void Function(Float32List, int, double) frame,
      void Function(String) failure) {
    _events.listen((message) {
      if (message is SendPort) {
        _commands = message;
        if (_stopped) message.send('stop');
      } else if (message == null) {
        if (!_stopped) failure('实时频谱已停止，请重试。');
        _finish();
      } else if (!_stopped && message is List && message.isNotEmpty) {
        if (message[0] == 'frame') {
          frame(message[1] as Float32List, message[2] as int,
              message[3] as double);
        } else {
          failure(
              message[0] == 'error' ? message[1] as String : '实时频谱暂不可用，请重试。');
        }
      }
    });
    unawaited(Isolate.spawn(runLinuxSpectrumWorker,
            <Object>[_events.sendPort, uri.toString(), library],
            onExit: _events.sendPort, onError: _events.sendPort)
        .then((isolate) {
      _isolate = isolate;
      if (_done.isCompleted) isolate.kill(priority: Isolate.immediate);
    }).catchError((Object _) {
      if (!_stopped) failure('无法启动实时频谱，请重试。');
      _finish();
    }));
  }

  final _events = ReceivePort();
  final _done = Completer<void>();
  SendPort? _commands;
  Isolate? _isolate;
  Timer? _stopTimeout;
  bool _stopped = false;

  Future<void> stop() {
    if (!_stopped && !_done.isCompleted) {
      _stopped = true;
      _commands?.send('stop');
      _stopTimeout = Timer(const Duration(seconds: 2), () {
        _isolate?.kill(priority: Isolate.immediate);
        _finish();
      });
    }
    return _done.future;
  }

  void _finish() {
    _stopTimeout?.cancel();
    _events.close();
    if (!_done.isCompleted) _done.complete();
  }
}
