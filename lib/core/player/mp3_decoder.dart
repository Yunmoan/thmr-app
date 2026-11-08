import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _CreateNative = Pointer<Void> Function();
typedef _Create = Pointer<Void> Function();
typedef _DecodeNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Float>, Pointer<Int32>);
typedef _Decode = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Float>, Pointer<Int32>);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _Destroy = void Function(Pointer<Void>);

/// One MP3 stream's decoder, exclusively owned by the spectrum worker isolate.
class Mp3Decoder {
  Mp3Decoder(String library) {
    final native = DynamicLibrary.open(library);
    _decode = native.lookupFunction<_DecodeNative, _Decode>('thmr_mp3_decode');
    _destroy =
        native.lookupFunction<_DestroyNative, _Destroy>('thmr_mp3_destroy');
    _handle =
        native.lookupFunction<_CreateNative, _Create>('thmr_mp3_create')();
    if (_handle == nullptr) throw StateError('MP3 decoder allocation failed');
    _input = calloc<Uint8>(inputCapacity);
    _pcm = calloc<Float>(2304);
    _info = calloc<Int32>(3);
  }

  static const inputCapacity = 16384;
  late final _Decode _decode;
  late final _Destroy _destroy;
  late final Pointer<Void> _handle;
  late final Pointer<Uint8> _input;
  late final Pointer<Float> _pcm;
  late final Pointer<Int32> _info;
  int consumed = 0, sampleRate = 0, channels = 0;
  bool _closed = false;

  Float32List decode(Uint8List bytes) {
    if (_closed || bytes.length > inputCapacity) {
      throw StateError('Invalid MP3 decoder input');
    }
    _input.asTypedList(bytes.length).setAll(0, bytes);
    final samples = _decode(_handle, _input, bytes.length, _pcm, _info);
    consumed = _info[0];
    sampleRate = _info[1];
    channels = _info[2];
    if (samples <= 0 || channels < 1 || channels > 2) return Float32List(0);
    return Float32List.fromList(_pcm.asTypedList(samples * channels));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _destroy(_handle);
    calloc.free(_input);
    calloc.free(_pcm);
    calloc.free(_info);
  }
}
