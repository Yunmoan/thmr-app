import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'mp3_decoder.dart';
import 'spectrum_fft.dart';

/// Only standard Dart/FFI imports: this entry point runs outside Flutter's UI
/// isolate and never loads media_kit or requests access to an audio device.
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
        // Initial synchronization wants several frames. Retain a small tail
        // afterward so split frames are never discarded at a network boundary.
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
            latest = fft.add(pcm, decoder.channels, rate) ?? latest;
          }
          consumed += advance;
        }
        pending = Uint8List.fromList(input.sublist(consumed));
        if (pending.length == Mp3Decoder.inputCapacity) {
          // Bound memory even for malformed streams or a large ID3 prefix.
          pending = Uint8List.fromList(pending.sublist(8192));
        }
      }
      if (latest != null) events.send(['frame', latest, rate]);
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
