# 自适应频谱

Windows、Android、Linux 均将 PCM 归一化的 FFT 幅值交给 Dart 的
`AdaptiveSpectrum`，在增益和 UI 包络之前估计有效带宽。显示起点固定为
40 Hz，上限从采样率的一半开始，根据有效内容自动调整。

- 忽略低于约 −72 dBFS 或低于当前峰值 50 dB 的频点，要求相邻频点有效，
  过滤孤立噪点；接近静音时冻结估计。
- 检测到的最高频率保留 15% 余量，上限最低为 4 kHz（低采样率时受奈奎斯特频率限制）。
- 连续 3 秒缺少高频才缩小目标范围，按 1.2 秒时间常数平滑收缩；高频恢复时
  按 0.25 秒时间常数展开。目标采用扩展 5%、收缩 10% 的迟滞。
- 只有新音频帧更新估计。重复 UI 轮询不累计证据；超过 250 ms 的帧间隔会
  中断收缩证据。静音也中断证据。新解码会话、采样率或 FFT 长度变化重新学习。
- 频谱柱仍按对数频率分配。每根柱子的边界直接从 Hz 计算，低频可共享 FFT
  频点，不再用递推取整强制消耗频点，避免宽布局下尾部出现空频段。

Windows 的 `thmr_poll_fft` 输出 1024 点 FFT 的 513 个幅值，返回采样率、
0（没有新样本）或 −1（不可用）。自动增益历史按 FFT 频点记录，范围调整和
窗口宽度变化不会混用不同频率的增益。原生 DLL 和 Dart 代码必须一起重新构建。
WASAPI 仍然分析默认输出设备的混音。

Android 的 `magnitudes` MethodChannel 方法返回 `sampleRate` 和
`Float64List` 幅值。Linux 在解码 isolate 中按解码音频时间更新估计，并将幅值、
采样率和显示上限一起交给 UI，避免网络成批交付影响学习速度。

## 验证

```sh
flutter test test/adaptive_spectrum_test.dart test/android_spectrum_test.dart \
  test/linux_spectrum_test.dart test/audio_strip_layout_test.dart
```

`tool/test_linux_spectrum.dart` 使用 MP3 合成音验证实际解码、FFT、自适应收缩和
单上游连接，运行方法见 [Linux 使用说明](LINUX.md)。

原生算法可独立验证，不需要音频设备：

```sh
# Windows / MinGW
g++ -std=c++17 -Wall -Wextra -Werror -DNOMINMAX \
  test/native/spectrum_capture_test.cc -o build/capture_test.exe -lole32 -luuid
build/capture_test.exe

# JDK
javac -d build/spectrum-java \
  android/app/src/main/java/cn/yunmoan/thmr/thmr_app/SpectrumMath.java \
  test/native/SpectrumMathTest.java
java -cp build/spectrum-java cn.yunmoan.thmr.thmr_app.SpectrumMathTest
```

自动化验证不替代各平台真实播放时的视觉验收。
