// Small C ABI around the vendored decoder. No FFmpeg or audio-device dependency.
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_ONLY_MP3
#define MINIMP3_FLOAT_OUTPUT
#include <minimp3.h>
#include <new>

extern "C" {
__attribute__((visibility("default"))) void* thmr_mp3_create() {
  auto* decoder = new (std::nothrow) mp3dec_t;
  if (decoder != nullptr) mp3dec_init(decoder);
  return decoder;
}

// pcm has room for MINIMP3_MAX_SAMPLES (2304) floats; info has 3 ints:
// bytes consumed, sample rate, channel count. Return samples per channel.
__attribute__((visibility("default"))) int thmr_mp3_decode(
    void* decoder, const unsigned char* input, int length, float* pcm, int* info) {
  mp3dec_frame_info_t frame = {};
  const int samples = mp3dec_decode_frame(static_cast<mp3dec_t*>(decoder), input,
                                          length, pcm, &frame);
  info[0] = frame.frame_bytes;
  info[1] = frame.hz;
  info[2] = frame.channels;
  return samples;
}

__attribute__((visibility("default"))) void thmr_mp3_destroy(void* decoder) {
  delete static_cast<mp3dec_t*>(decoder);
}
}
