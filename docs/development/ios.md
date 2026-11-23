# iOS 本地开发

[返回开发指南](README.md) · [TestFlight 签名与分发](../release/testflight.md)

## 开发环境

安装完整的 Xcode，首次启动后安装 iOS 模拟器和命令行工具。通过 CocoaPods 提供 libmpv 和其他原生插件。已有 Homebrew 时可用 `brew install cocoapods`。 [Xcode 系统要求](https://developer.apple.com/xcode/system-requirements/) · [CocoaPods 安装说明](https://guides.cocoapods.org/using/getting-started.html)

在仓库根目录运行：

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

export FLUTTER_SWIFT_PACKAGE_MANAGER=false
flutter doctor -v
flutter pub get --enforce-lockfile
open -a Simulator
flutter devices
flutter run -d DEVICE_ID
```

将 `DEVICE_ID` 替换为设备列表中的 ID。使用真机调试时可先运行 `flutter build ios --config-only --no-codesign`，再打开 [`ios/Runner.xcworkspace`](../../ios/Runner.xcworkspace/) 并在 **Runner → Signing & Capabilities** 选择签名团队。

`flutter build ios --release --no-codesign` 用于检查真机架构的编译结果。PR、默认分支推送和手动运行会由 [Build iOS](../../.github/workflows/ios.yml) 执行无签名构建。另见 [通用验证](verification.md)。

## 界面素材

用 Xcode 打开 Runner 的资产目录。启动屏幕使用 [`LaunchScreen.storyboard`](../../ios/Runner/Base.lproj/LaunchScreen.storyboard) 与 [`LaunchImage.imageset`](../../ios/Runner/Assets.xcassets/LaunchImage.imageset/) 中的三个比例资源，应用图标位于 [`AppIcon.appiconset`](../../ios/Runner/Assets.xcassets/AppIcon.appiconset/)。

## 真机验证

在 iPhone 上检查冷启动、频道加载、直播播放、锁屏后播放、控制中心暂停与恢复、登录和诊断导出。在 iPad 上检查分屏布局、选项菜单以及大屏幕模式。发布签名与安装通过 TestFlight 核验。
