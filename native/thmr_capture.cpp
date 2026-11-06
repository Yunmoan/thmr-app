// thmr_capture.cpp — real-time audio spectrum for the THMR Flutter client.
//
// Captures the system output mix via WASAPI loopback (default render device),
// keeps a mono ring buffer, and on poll() runs a 1024-point radix-2 FFT over
// the newest window, aggregating magnitudes into log-spaced bands normalized
// to [0, 1] on a dB scale.
//
// Threading: ALL COM / WASAPI objects are created, used and released on the
// dedicated capture thread (MTA). thmr_start only signals and waits for the
// init result; thmr_stop flips a flag and joins. Cross-apartment interface
// pointers would crash — do not touch WASAPI from other threads.
//
// Exported ABI (x64, cdecl):
//   int  thmr_start(void)                  0 ok / -1 fail
//   void thmr_stop(void)
//   int  thmr_poll(float* out, int bands)  1 ok / 0 silence / -1 not running

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>

#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

namespace {

constexpr size_t kRing = 16384;  // mono samples (~0.34 s @ 48 kHz)
constexpr size_t kFft = 1024;
constexpr float kPi = 3.14159265358979f;

std::atomic<bool> g_run{false};
std::atomic<int> g_init{-2};  // -2 initializing, 0 ok, -1 failed
std::atomic<UINT32> g_sr{48000};
std::thread g_thread;

std::mutex g_mu;
std::vector<float> g_ring(kRing, 0.0f);
size_t g_wpos = 0;  // next write slot

void push_samples(const float* src, size_t n) {
  std::lock_guard<std::mutex> lk(g_mu);
  for (size_t i = 0; i < n; ++i) {
    g_ring[g_wpos] = src[i];
    g_wpos = (g_wpos + 1) % kRing;
  }
}

// Full capture session lives on this thread.
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

    // Shared-mode mix format is IEEE float 32; refuse anything else.
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
    // init failed — release what we hold and bail out
    if (wf) CoTaskMemFree(wf);
    if (cap) cap->Release();
    if (client) client->Release();
    if (dev) dev->Release();
    if (en) en->Release();
    CoUninitialize();
    g_run.store(false);
    return;
  }

  // ---- capture loop ----
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

  // ---- cleanup on the same thread ----
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

// Per-band sliding peak (auto gain control); reset on each capture start.
float g_peak[128];

}  // namespace

extern "C" {

__declspec(dllexport) int thmr_start(void) {
  bool expected = false;
  if (!g_run.compare_exchange_strong(expected, true)) return 0;  // already on
  g_init.store(-2);
  std::fill(g_peak, g_peak + 128, 0.0f);

  std::thread t(capture_main);
  g_thread = std::move(t);

  // Wait up to 2 s for thread-side init.
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

__declspec(dllexport) int thmr_poll(float* out, int bands) {
  if (!g_run.load() || g_init.load() != 0 || !out || bands <= 0 ||
      bands > 128) return -1;
  // Per-band sliding peak (auto gain control) so bass-heavy bands stop
  // pinning at full scale; values breathe within each band's own range.

  static float re[kFft];
  static float im[kFft];
  {
    std::lock_guard<std::mutex> lk(g_mu);
    for (size_t i = 0; i < kFft; ++i) {
      const size_t idx = (g_wpos + kRing - kFft + i) % kRing;
      re[i] = g_ring[idx];
      im[i] = 0.0f;
    }
  }

  float energy = 0.0f;
  for (size_t i = 0; i < kFft; ++i) energy += re[i] * re[i];
  if (energy < 1e-10f) return 0;  // digital silence

  // Hamming window
  for (size_t i = 0; i < kFft; ++i) {
    re[i] *=
        0.54f - 0.46f * std::cos(2.0f * kPi * static_cast<float>(i) / (kFft - 1));
  }
  fft_inplace(re, im, static_cast<int>(kFft));

  // Aggregate into log-spaced bands between 40 Hz and Nyquist.
  const double fmin = 40.0;
  const double fmax = static_cast<double>(g_sr.load()) * 0.5;
  const double ratio = fmax / fmin;
  const int half = static_cast<int>(kFft / 2);
  int prevBin = 1;
  for (int b = 0; b < bands; ++b) {
    const int binHi = std::min(
        half,
        std::max(prevBin + 1,
                 static_cast<int>(1.0 * prevBin * std::pow(ratio, 1.0 / bands) +
                                  0.5)));
    float mag = 0.0f;
    int count = 0;
    for (int k = prevBin; k < binHi && k < half; ++k) {
      const float m = std::sqrt(re[k] * re[k] + im[k] * im[k]);
      if (m > mag) mag = m;  // peak within band keeps the spectrum lively
      ++count;
    }
    prevBin = binHi;
    float v = 0.0f;
    if (count > 0) {
      const float db = 20.0f * std::log10(mag + 1e-7f);
      // AGC: track each band's decaying peak, map a 34 dB window below it.
      float& peak = g_peak[b];
      if (peak < -90.0f) peak = db;           // first frame
      peak = std::max(db, peak - 1.1f);       // glide down ~1.1 s
      v = (db - (peak - 30.0f)) / 30.0f;
    }
    // gentle tilt so the low end reads calmer than the high end
    v *= 1.0f - 0.22f * (static_cast<float>(b) /
                         static_cast<float>(std::max(1, bands - 1)));
    out[b] = std::min(1.0f, std::max(0.0f, v));
  }
  return 1;
}

}  // extern "C"
