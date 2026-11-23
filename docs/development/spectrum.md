# 音频频谱

[返回开发指南](README.md)

| 平台 | 取样方式 |
| --- | --- |
| Windows | [WASAPI](../../lib/core/player/spectrum_ffi.dart) 读取默认输出设备混音，原生 [`thmr_poll_fft`](../../native/thmr_capture.cpp) 返回归一化 FFT 幅值和采样率。启动、等待和 FFT 在后台执行。修改接口时同时构建 DLL 和 Dart 客户端。 |
| Android | [原生解码器](../../android/app/src/main/java/cn/yunmoan/thmr/thmr_app/StreamSpectrumDecoder.java) 解码放送音频，`magnitudes` 通道方法传回采样率与 `Float64List` 幅值。 |
| Linux | [解码 isolate](../../lib/core/player/spectrum_linux_worker.dart) 使用内置 minimp3 分析共享播放流，按解码音频时间更新估计。 [minimp3 版本与哈希](../../native/vendor/minimp3/source.json) |
| macOS、iOS | 复用 [流解码器](../../lib/core/player/spectrum_linux.dart)，通过 [`thmr_mp3` CocoaPods 包](../../native/thmr_mp3.podspec) 提供原生解码。 |

[`AdaptiveSpectrum`](../../lib/core/player/adaptive_spectrum.dart) 在增益和 UI 包络之前估计有效带宽。连续新音频帧推动估计，忽略低幅值及孤立噪点，静音或帧间隔过长会中断收缩。带宽下降时延迟收缩，检测到高频后较快扩张。频谱柱按对数频率划分，相关阈值以实现为准。

## 验证

```sh
flutter test test/adaptive_spectrum_test.dart test/android_spectrum_test.dart \
  test/linux_spectrum_test.dart test/audio_strip_layout_test.dart
```

Windows 的原生算法测试可在 MinGW 下运行：

```sh
g++ -std=c++17 -Wall -Wextra -Werror -DNOMINMAX \
  test/native/spectrum_capture_test.cc -o build/capture_test.exe -lole32 -luuid
build/capture_test.exe
```

Android FFT 可用 JDK 验证：

```sh
javac -d build/spectrum-java \
  android/app/src/main/java/cn/yunmoan/thmr/thmr_app/SpectrumMath.java \
  test/native/SpectrumMathTest.java
java -cp build/spectrum-java cn.yunmoan.thmr.thmr_app.SpectrumMathTest
```

完成 [Linux 构建](linux.md#构建) 后，可用合成 MP3 验证实际解码、FFT、带宽收缩和共享连接。在下面的命令中，空 PATH 用于验证解码过程没有外部命令依赖。

```sh
flutter_sdk=$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")
env PATH=/nonexistent "$flutter_sdk/bin/cache/dart-sdk/bin/dart" \
  --packages=.dart_tool/package_config.json tool/test_linux_spectrum.dart \
  "$PWD/build/linux/x64/release/bundle/lib/libthmr_mp3.so"
```

合成音来源见 [测试素材](../../test/fixtures/README.md)。改动音频取样或绘制后，在相应系统上播放实际音频，检查频谱响应、暂停和切换码率。
