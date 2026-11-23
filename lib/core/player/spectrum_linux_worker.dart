import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'mp3_decoder.dart';
import 'adaptive_spectrum.dart';
import 'spectrum_fft.dart';

/// 此入口只使用 Dart 标准库和 FFI，可脱离 Flutter UI isolate 运行，无需 media_kit 或音频设备。
Future<void> runLinuxSpectrumWorker(List<Object> arguments) async {
  final events = arguments[0] as SendPort;
  final uri = Uri.parse(arguments[1] as String);
  final library = arguments[2] as String;
  final commands = ReceivePort();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  var stopped = false;
  commands.listen((_) {
    stopped = true;
    client.close(force: true);
  });
  events.send(commands.sendPort);
  Mp3Decoder? decoder;
  try {
    decoder = Mp3Decoder(library);
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('Radio relay unavailable');
    }
    final fft = PcmSpectrumDecoder();
    final spectrum = AdaptiveSpectrum();
    var decodedMicroseconds = 0.0;
    var pending = Uint8List(0);
    var synced = false;
    await for (final chunk in response) {
      if (stopped) break;
      Float32List? latest;
      var rate = 0;
      for (var offset = 0; offset < chunk.length;) {
        final take = math.min(
            chunk.length - offset, Mp3Decoder.inputCapacity - pending.length);
        final input = Uint8List(pending.length + take)
          ..setAll(0, pending)
          ..setRange(pending.length, pending.length + take, chunk, offset);
        offset += take;
        var consumed = 0;
        // 初次同步需要多个 MP3 帧。之后保留少量尾部字节，避免丢弃恰好跨网络分块的帧。
        while (input.length - consumed >= (synced ? 4096 : 8192)) {
          final bytes = Uint8List.sublistView(input, consumed);
          final pcm = decoder.decode(bytes);
          var advance = decoder.consumed;
          if (advance <= 0) break;
          if (pcm.isEmpty) {
            advance = math.min(advance, bytes.length - 4096);
            if (advance <= 0) break;
          } else {
            synced = true;
            rate = decoder.sampleRate;
            decodedMicroseconds += pcm.length / decoder.channels / rate * 1e6;
            final frame = fft.add(pcm, decoder.channels, rate);
            if (frame != null) {
              // 按解码后的音频时长推进频谱估计，避免网络突发数据加速估计或跳过中间 FFT 帧。
              spectrum.add(frame, rate,
                  Duration(microseconds: decodedMicroseconds.round()));
              latest = frame;
            }
          }
          consumed += advance;
        }
        pending = Uint8List.fromList(input.sublist(consumed));
        if (pending.length == Mp3Decoder.inputCapacity) {
          // 限制缓冲区大小，防止畸形流或过大的 ID3 前缀耗尽内存。
          pending = Uint8List.fromList(pending.sublist(8192));
        }
      }
      if (latest != null) {
        events.send(['frame', latest, rate, spectrum.upperHz]);
      }
    }
    if (!stopped) events.send(['error', '电台连接已中断，请重试实时频谱。']);
  } catch (_) {
    if (!stopped) events.send(['error', '实时频谱暂不可用，请检查安装包和电台连接。']);
  } finally {
    decoder?.close();
    client.close(force: true);
    commands.close();
  }
}
