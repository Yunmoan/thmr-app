// Standalone Windows check: exercises the production capture FFT without an
// audio device. Compile with NOMINMAX and link ole32 (and uuid on MinGW).
#include <iostream>
#include <stdexcept>

#include "../../native/thmr_capture.cpp"

void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  g_run.store(true);
  g_init.store(0);
  g_sr.store(48000);
  float magnitudes[kFft / 2 + 1]{};
  require(thmr_poll_fft(magnitudes, 513) == 0, "Uninitialized PCM was fresh");
  std::vector<float> pcm(kFft);
  for (size_t i = 0; i < kFft; ++i) {
    pcm[i] = 0.5f * std::sin(2.0f * kPi * 160.0f * static_cast<float>(i) /
                           static_cast<float>(kFft)); // 7500 Hz
  }
  push_samples(pcm.data(), pcm.size());
  require(thmr_poll_fft(magnitudes, 513) == 48000, "Missing fresh FFT/rate");
  require(std::abs(magnitudes[160] - 0.5f) < 0.002f, "FFT normalization changed");
  require(magnitudes[159] > 0.24f, "Windowed tone lost its adjacent bin");
  require(magnitudes[300] < 0.0001f, "Unexpected high-frequency energy");
  require(thmr_poll_fft(magnitudes, 513) == 0, "Stale PCM was reported fresh");
  require(thmr_poll_fft(magnitudes, 110) == -1, "Invalid ABI size accepted");
  std::fill(pcm.begin(), pcm.end(), 0.0f);
  push_samples(pcm.data(), pcm.size());
  require(thmr_poll_fft(magnitudes, 513) == 48000, "Silence was not fresh");
  for (float value : magnitudes) require(value == 0, "Silence produced motion");
  g_run.store(false);
  require(thmr_poll_fft(magnitudes, 513) == -1, "Stopped capture returned data");
  std::cout << "Windows capture FFT, normalization, freshness and silence passed\n";
}
