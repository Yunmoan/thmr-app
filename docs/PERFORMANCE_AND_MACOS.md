# 性能优化与 macOS issue #18

## 保持界面效果的优化

- 频谱仍按原先约 20 fps 采样，柱形、颜色、透明度和攻击/衰减参数保持不变。
  音频帧直接通知 `CustomPainter` 重绘，不再逐帧重建频谱的布局和按钮。
- 播放计时由独立组件订阅，每秒只更新计时文字。
- Material 主题按角色配色缓存。切换音质、自动播放或关闭方式不会重新生成
  整套主题和字体；深浅色模式切换复用已生成的两套主题。
- 标签页首次访问时初始化，此后隐藏时保留输入、滚动和页面状态。
  原先的 240 ms 淡入/滑入动画保持不变，隐藏页面的 ticker 仍然停用。

在约 1 秒、21 个音频帧的组件测试中，频谱绘制器创建数由 21 降到 1，
音频采样仍为 21 次。此数字只衡量该组件的重建分配，不代表整个应用的 CPU
占用降低同样比例。修改前生成的六张深浅色频谱基准图，覆盖初始、播放和暂停
衰减状态，修改后逐像素一致。

## issue 的证据与判断

[issue #18](https://github.com/Yunmoan/thmr-app/issues/18) 的标题写的是 macOS 15.3，
但附件诊断与崩溃报告实际为 **macOS 15.8.1、Intel x64、0.1.8+6801**。

| 现象 | 判断与处理 |
| --- | --- |
| 文字和图标破碎、卡顿 | 截图中图片和面板仍可辨认，文字与 Material 图标同时破碎，优先怀疑 GPU 字形渲染路径。Flutter 3.47 默认启用 Impeller，项目此前没有显式选择渲染器。已用官方 `FLTEnableImpeller=false` 配置切回仍使用 Metal 加速的 Skia，作为兼容性处理。尚未在受影响 Mac 上做 A/B 验证，不能认定是已证实的引擎或驱动缺陷。 |
| 关闭时报告崩溃 | 崩溃线程是 `*/mpv core`，栈中有 `mp_client_send_property_changes` 和 FlutterMacOS；主线程同时在 `NSApplication terminate:` 中销毁引擎。与音频原生回调和 Dart VM 生命周期竞争高度吻合。此前 macOS 直接退出，共享播放器未释放。现通过 `AppLifecycleListener.onExitRequested` 等待轮询/订阅、系统媒体控制和播放器清理，再允许 AppKit 退出；并发退出共用一次清理，超时或失败时直接终止进程，避免继续卸载仍有回调的 VM。仍需真机验证原生退出行为。 |
| 频谱一直静止 | `getPlatformSpectrum()` 目前只实现 Windows、Android、Linux，macOS 返回 `null`，界面按设计保持静止。本次没有新增 macOS 音频分析实现。 |
| 没有托盘 | 此前平台判断只覆盖 Windows、Linux。现已接入 macOS 菜单栏图标、显示主窗口和退出菜单，关闭设置支持每次询问、退出、隐藏到菜单栏；图标不可用时回退到 Dock。Cmd+Q 与菜单退出共用资源清理流程，Dock 和重复启动仍可恢复窗口。 |

诊断报告未显示内存耗尽，服务连接也能建立；这些信息不足以解释截图中的字形破碎。
客户端性能优化、macOS 托盘支持和频谱功能边界分别处理，后端无需改动。

## 验证方法与边界

```sh
flutter analyze
flutter test
python -m unittest discover -s tool -p test_macos_app.py
```

`test/audio_strip_rendering_test.dart` 同时检查修改前的 PNG 基准、绘制器分配数、
采样节奏以及隐藏/后台停止采样。`application_exit_test.dart` 覆盖退出等待、
并发请求、清理失败和超时；媒体控制测试覆盖启动尚未完成时退出的竞争。
`desktop_tray_test.dart` 覆盖资源图标、菜单事件、启动期间退出和 Windows 兼容；
`macos_tray_window_test.dart` 使用模拟原生通道验证关窗后继续播放、菜单恢复窗口、
图标失败回退到 Dock，以及关闭询问的取消行为。

macOS 保留 AppKit 原生标题栏和窗口尺寸。点击菜单栏图标打开菜单，选择“显示主窗口”
恢复窗口；在“我的 → 关闭按钮”可选择“隐藏到菜单栏”或“退出程序”，默认仍为“每次询问”。
红色关闭按钮和 Cmd+W 按此设置执行，Cmd+Q 或托盘“退出”始终请求退出程序。

受影响 Intel Mac 需使用新构建实际检查：昨日歌单长列表滚动、缩放窗口、切换标签页，
以及播放、暂停和连接中分别点击红色关闭按钮、Cmd+W、Cmd+Q，确认没有新的系统
崩溃报告；隐藏后分别通过菜单“显示主窗口”、Dock、重复启动恢复，并确认声音不中断。
可在同一机器用 profile 构建比较默认的 Skia 与
`flutter run -d macos --profile --enable-impeller`，记录终端中的实际渲染后端。
Windows 上的组件基准图与回归测试不构成 macOS GPU 或原生退出验收。

参考：[Flutter 官方渲染器配置](https://github.com/flutter/flutter/blob/master/engine/src/flutter/impeller/README.md#macos)、
[Flutter 官方退出回调](https://api.flutter.dev/flutter/widgets/AppLifecycleListener-class.html)。
