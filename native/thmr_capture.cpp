// THMR Flutter 客户端的 Windows 实时频谱。
//
// WASAPI loopback 从默认输出设备采集系统混音，混成单声道后存入环形缓冲区。
// thmr_poll_fft 对最近的 1024 个样本执行基 2 FFT，Dart 再将归一化振幅映射为自适应频带。
//
// COM / WASAPI 对象在专用 MTA 采集线程上创建、使用和释放。thmr_start 启动线程并等待初始化结果，
// thmr_stop 清除运行标志后等待线程退出。
//
// 导出的 C ABI
//   int thmr_start(void)                     返回 0 表示成功，-1 表示失败。
//   void thmr_stop(void)
//   int thmr_poll_fft(float* out, int bins)
// 新 FFT 可用时返回采样率，0 表示尚无新数据，-1 表示未就绪或参数无效。

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>

#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

namespace {

constexpr size_t kRing = 16384;  // 单声道样本数，48 kHz 时约 0.34 秒
constexpr size_t kFft = 1024;
constexpr float kPi = 3.14159265358979f;

std::atomic<bool> g_run{false};
std::atomic<int> g_init{-2};  // -2 初始化中，0 成功，-1 失败
std::atomic<UINT32> g_sr{48000};
std::thread g_thread;

std::mutex g_mu;
std::vector<float> g_ring(kRing, 0.0f);
size_t g_wpos = 0;  // 下一写入位置
uint64_t g_written = 0, g_polled = 0;  // 由 g_mu 保护

void push_samples(const float* src, size_t n) {
  std::lock_guard<std::mutex> lk(g_mu);
  for (size_t i = 0; i < n; ++i) {
    g_ring[g_wpos] = src[i];
    g_wpos = (g_wpos + 1) % kRing;
  }
  g_written += n;
}

// 完整的采集会话始终在此线程运行。
void capture_main() {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(hr)) {
    g_init.store(-1);
    g_run.store(false);
    return;
  }

  IMMDeviceEnumerator* en = nullptr;
  IMMDevice* dev = nullptr;
  IAudioClient* client = nullptr;
  IAudioCaptureClient* cap = nullptr;
  WAVEFORMATEX* wf = nullptr;
  UINT32 sr = 48000;
  int channels = 2;

  do {
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          __uuidof(IMMDeviceEnumerator),
                          reinterpret_cast<void**>(&en));
    if (FAILED(hr)) break;
    hr = en->GetDefaultAudioEndpoint(eRender, eConsole, &dev);
    if (FAILED(hr)) break;
    hr = dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                       reinterpret_cast<void**>(&client));
    if (FAILED(hr)) break;
    hr = client->GetMixFormat(&wf);
    if (FAILED(hr)) break;

    // 仅处理标记为 IEEE float 的混音格式，下游按 32 位浮点读取。
    const bool isFloat =
        wf->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
        (wf->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
         reinterpret_cast<WAVEFORMATEXTENSIBLE*>(wf)->SubFormat.Data1 == 3);
    if (!isFloat || wf->nChannels < 1) break;

    channels = wf->nChannels;
    sr = wf->nSamplesPerSec;
    g_sr.store(sr);
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                            AUDCLNT_STREAMFLAGS_LOOPBACK,
                            2000000 /* 200 ms */, 0, wf, nullptr);
    if (FAILED(hr)) break;
    hr = client->GetService(__uuidof(IAudioCaptureClient),
                            reinterpret_cast<void**>(&cap));
    if (FAILED(hr)) break;
    hr = client->Start();
    if (FAILED(hr)) break;

    g_init.store(0);
  } while (false);

  if (g_init.load() != 0) {
    // 初始化失败，释放已取得的资源。
    if (wf) CoTaskMemFree(wf);
    if (cap) cap->Release();
    if (client) client->Release();
    if (dev) dev->Release();
    if (en) en->Release();
    CoUninitialize();
    g_run.store(false);
    return;
  }

  // 采集循环
  std::vector<float> mono;
  while (g_run.load(std::memory_order_relaxed)) {
    Sleep(6);
    UINT32 packet = 0;
    while (SUCCEEDED(cap->GetNextPacketSize(&packet)) && packet > 0) {
      BYTE* data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      UINT64 pos = 0, qpc = 0;
      if (FAILED(cap->GetBuffer(&data, &frames, &flags, &pos, &qpc))) break;
      mono.resize(frames);
      if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
        std::memset(mono.data(), 0, frames * sizeof(float));
      } else {
        const float* f = reinterpret_cast<const float*>(data);
        for (UINT32 i = 0; i < frames; ++i) {
          float acc = 0.0f;
          for (int c = 0; c < channels; ++c) acc += f[i * channels + c];
          mono[i] = acc / static_cast<float>(channels);
        }
      }
      push_samples(mono.data(), frames);
      cap->ReleaseBuffer(frames);
    }
  }

  // 在采集线程上释放资源。
  client->Stop();
  if (cap) cap->Release();
  if (client) client->Release();
  if (wf) CoTaskMemFree(wf);
  if (dev) dev->Release();
  if (en) en->Release();
  CoUninitialize();
}

void fft_inplace(float* re, float* im, int n) {
  for (int i = 1, j = 0; i < n; ++i) {
    int bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      float t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
  }
  for (int len = 2; len <= n; len <<= 1) {
    const float ang = -2.0f * kPi / static_cast<float>(len);
    const float wr = std::cos(ang), wi = std::sin(ang);
    for (int i = 0; i < n; i += len) {
      float cr = 1.0f, ci = 0.0f;
      for (int k = 0; k < len / 2; ++k) {
        const int a = i + k, b = i + k + len / 2;
        const float vr = re[b] * cr - im[b] * ci;
        const float vi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - vr; im[b] = im[a] - vi;
        re[a] += vr;        im[a] += vi;
        const float ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}

}  // namespace

extern "C" {

__declspec(dllexport) int thmr_start(void) {
  bool expected = false;
  if (!g_run.compare_exchange_strong(expected, true)) return 0;  // 采集已启动
  g_init.store(-2);
  {
    std::lock_guard<std::mutex> lk(g_mu);
    std::fill(g_ring.begin(), g_ring.end(), 0.0f);
    g_wpos = 0;
    g_written = g_polled = 0;
  }

  std::thread t(capture_main);
  g_thread = std::move(t);

  // 最多轮询 2 秒等待初始化结果。失败清理仍需等待线程退出。
  for (int i = 0; i < 200 && g_init.load() == -2; ++i) Sleep(10);
  if (g_init.load() != 0) {
    g_run.store(false);
    if (g_thread.joinable()) g_thread.join();
    return -1;
  }
  return 0;
}

__declspec(dllexport) void thmr_stop(void) {
  if (!g_run.exchange(false)) return;
  if (g_thread.joinable()) g_thread.join();
  std::lock_guard<std::mutex> lk(g_mu);
  std::fill(g_ring.begin(), g_ring.end(), 0.0f);
}

__declspec(dllexport) int thmr_poll_fft(float* out, int bins) {
  if (!g_run.load() || g_init.load() != 0 || !out ||
      bins != static_cast<int>(kFft / 2 + 1)) return -1;

  // FFT 工作区由频谱 isolate 串行调用复用。g_mu 只保护采集缓冲区。
  static float re[kFft];
  static float im[kFft];
  {
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_written < kFft || g_written == g_polled) return 0;
    g_polled = g_written;
    for (size_t i = 0; i < kFft; ++i) {
      const size_t idx = (g_wpos + kRing - kFft + i) % kRing;
      re[i] = std::isfinite(g_ring[idx]) ? g_ring[idx] : 0.0f;
      im[i] = 0.0f;
    }
  }

  // 各平台均使用 Hann 窗，并对 FFT 振幅按 PCM 幅值归一化。
  for (size_t i = 0; i < kFft; ++i) {
    re[i] *=
        0.5f - 0.5f * std::cos(2.0f * kPi * static_cast<float>(i) / (kFft - 1));
  }
  fft_inplace(re, im, static_cast<int>(kFft));

  for (int bin = 0; bin < bins; ++bin) {
    out[bin] = std::sqrt(re[bin] * re[bin] + im[bin] * im[bin]) *
        4.0f / static_cast<float>(kFft);
  }
  return static_cast<int>(g_sr.load());
}

}  // extern "C"
