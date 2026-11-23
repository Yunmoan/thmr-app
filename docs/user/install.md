# 安装与更新

[返回使用指南](README.md)

从正式发布页选择平台对应的安装包。iOS 测试版通过 TestFlight 邀请分发。 [GitHub Releases](https://github.com/Yunmoan/thmr-app/releases) · [TestFlight 分发](../release/testflight.md#上传与分发)

| 平台 | 获取与安装 |
| --- | --- |
| Windows x64 | 解压 `thmr-app-windows-x64.zip`，保留整个目录，运行 `thmr_app.exe`。内嵌登录需要 Microsoft Edge WebView2 运行时。 |
| macOS 12+ | 打开 `thmr-app-macos-universal.dmg`，将 THMR 拖到 Applications，再从该目录启动。支持 Intel 和 Apple Silicon。公开分发包的签名与公证取决于发布配置。 |
| Linux x64 | 解压 `thmr-app-linux-x64.tar.gz`。安装运行库后，通过 `bundle/thmr` 启动。 [Linux 使用说明](linux.md) |
| Android | 下载 `thmr-app-android.apk`，按系统提示安装。 |
| iOS 15+ | 通过 TestFlight 安装和更新。 |

桌面端每个登录会话只运行一个实例。重复启动会唤起原窗口。Windows 支持迷你播放器，可从托盘恢复。macOS 在「我的 → 关闭按钮」可选择每次询问、退出或隐藏到菜单栏。隐藏后可从菜单栏、Dock 或再次启动恢复窗口。菜单栏图标不可用时回退到 Dock 最小化。

## 应用内更新

Windows、macOS、Linux 和 Android 在「我的」中提供更新检查。可以关闭自动检查或自动下载、取消下载，或忽略一个版本。应用验证清单签名和安装包哈希，并按平台和架构选包。

- Windows、macOS 和 Linux 在点击「安装并重启」后替换程序，启动失败时自动恢复原版。使用应用内更新时保留完整的安装目录。Windows 受保护的目录可能要求管理员授权，macOS 和 Linux 需要对安装位置具备写权限。
- Android 打开系统安装器，由用户确认。覆盖安装要求 APK 与已安装版本使用相同签名。
- iOS 的新版通过 TestFlight 分发。

分发和签名要求见 [客户端发布](../release/client-builds.md)。
