# 开发指南

[返回文档目录](../README.md)

## 本地启动

使用 [`.fvmrc`](../../.fvmrc) 锁定的 Flutter 版本。安装对应 SDK 并将 `flutter/bin` 加入 PATH。使用 FVM 时，在仓库根目录执行 `fvm install`，之后可用 `fvm flutter` 运行以下命令。 [Flutter SDK 归档](https://docs.flutter.dev/install/archive)

```sh
flutter pub get --enforce-lockfile
flutter devices
flutter run -d DEVICE_ID
```

桌面设备 ID 为 `windows`、`macos` 或 `linux`。在对应操作系统上构建。Windows 平台需要 Visual Studio 的「使用 C++ 的桌面开发」工作负载和 C++ ATL 组件，macOS 需要 Xcode。Android 与 iOS 使用 `flutter devices` 列出的设备 ID。 [Linux 开发环境](linux.md) · [iOS 开发环境](ios.md)

## 代码入口

| 路径 | 职责 |
| --- | --- |
| [`lib/main.dart`](../../lib/main.dart)、[`lib/app.dart`](../../lib/app.dart) | 初始化播放器和平台环境，挂载应用主题和全局输入 |
| [`lib/core/`](../../lib/core/) | API、数据模型、Riverpod 状态、播放、更新和平台桥接 |
| [`lib/features/`](../../lib/features/) | 收听、曲库、收藏、账号、诊断和播放器界面 |
| [`lib/shared/widgets/`](../../lib/shared/widgets/) | 各功能共用的界面组件 |
| [`native/`](../../native/)、各平台目录 | 原生播放辅助代码、应用运行器和系统集成 |
| [`assets/`](../../assets/)、[`shaders/`](../../shaders/) | 品牌素材、图标、安装辅助脚本和大屏着色器 |
| [`test/`](../../test/)、[`tool/`](../../tool/) | 自动化测试、CI 工具和手动检查脚本 |

主题令牌与角色图选择以 [`thmr_colors.dart`](../../lib/core/theme/thmr_colors.dart) 为准。[`assets/brand/source/`](../../assets/brand/source/) 存放可用于重新制作界面素材的原图，包内使用 [`assets/brand/`](../../assets/brand/) 顶层的运行素材。需要更新启动图时，通过 [iOS 开发指南](ios.md#界面素材) 找到 Xcode 资源目录。

## 专题

- [后端接入](services.md)
- [音频频谱](spectrum.md)
- [验证与手动检查](verification.md)
- [Linux 构建与验证](linux.md)
- [iOS 本地开发](ios.md)
