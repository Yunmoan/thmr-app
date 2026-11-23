// 为内置 minimp3 提供精简的 C ABI，无需 FFmpeg 或音频设备。
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_ONLY_MP3
#define MINIMP3_FLOAT_OUTPUT
#include <minimp3.h>
#include <new>

extern "C" {
__attribute__((visibility("default"), used)) void* thmr_mp3_create() {
  auto* decoder = new (std::nothrow) mp3dec_t;
  if (decoder != nullptr) mp3dec_init(decoder);
  return decoder;
}

// pcm 至少容纳 MINIMP3_MAX_SAMPLES（2304）个 float。info 的三个整数依次是消耗字节数、采样率和声
// 道数。返回每声道样本数。
__attribute__((visibility("default"), used)) int thmr_mp3_decode(
    void* decoder, const unsigned char* input, int length, float* pcm, int* info) {
  mp3dec_frame_info_t frame = {};
  const int samples = mp3dec_decode_frame(static_cast<mp3dec_t*>(decoder), input,
                                          length, pcm, &frame);
  info[0] = frame.frame_bytes;
  info[1] = frame.hz;
  info[2] = frame.channels;
  return samples;
}

__attribute__((visibility("default"), used)) void thmr_mp3_destroy(void* decoder) {
  delete static_cast<mp3dec_t*>(decoder);
}
}
