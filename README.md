<p align="center">
  <img src="assets/icons/icon-512.png" width="112" alt="THMR 朱红色印记">
</p>

<h1 align="center">THMR · 东方音乐电台</h1>

<p align="center">
  <strong>跨过博丽大结界无需通行证——随时随地收听万千东方同人音乐。</strong><br>
  Touhou Music Radio 跨平台客户端，覆盖 Windows、macOS、Linux、Android 与 iOS。
</p>

<p align="center">
  <a href="https://github.com/Yunmoan/thmr-app/releases"><strong>下载客户端</strong></a>
  · <a href="#功能特性">功能特性</a>
  · <a href="#平台与快速开始">平台与快速开始</a>
  · <a href="#技术栈">技术栈</a>
  · <a href="#新贡献者留名">参与贡献</a>
  · <a href="docs/README.md">项目文档</a>
</p>

<p align="center">
  <a href="https://github.com/Yunmoan/thmr-app/actions/workflows/build.yml"><img src="https://github.com/Yunmoan/thmr-app/actions/workflows/build.yml/badge.svg" alt="桌面端与 Android 构建状态"></a>
  <a href="https://github.com/Yunmoan/thmr-app/actions/workflows/ios.yml"><img src="https://github.com/Yunmoan/thmr-app/actions/workflows/ios.yml/badge.svg" alt="iOS 构建状态"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter&logoColor=white" alt="Flutter 3.47.5"></a>
  <img src="https://img.shields.io/badge/version-0.2.1-e2455a" alt="版本 0.2.1">
</p>

## 关于 THMR

> 无论是神社午后的闲适独奏，还是弹幕交锋时的燃曲改编，幻想乡的电波 24 小时不间断放送。打开客户端，直接接通现世与幻想乡的音频频段。

**THMR（Touhou Music Radio）** 是面向东方同人音乐电台的跨平台原生客户端，将直播收听、曲库检索、个人收藏与切歌投票收拢进同一个轻量应用里。推门即听，无需注册。登录后可搜索曲库、收藏和投票。从 Windows 桌角的迷你悬浮条到五个平台的大屏幕音乐动效，随使用场景自由切换。

> **文々。新闻 · 号外**
>
> 本报记者现场发回报道：THMR 客户端已发布 Windows、macOS、Linux 和 Android 安装包，iOS 测试版经由 TestFlight 分发！大屏幕模式、五种音乐动效、Windows 桌角迷你播放器与多套角色主题均已实装。完整更新条目请参阅 [更新日志](CHANGELOG.md)。
>
> —— 射命丸文

---

## 功能特性

### 电台与线路：推门即听

*博丽神社的赛钱箱常年冷清，但电台的信号从不打烊。*

- **零门槛开听**：无需登录即可直接收听直播，自由切换频道、音质与播放源，所选线路会自动记忆至下次启动。
- **双线路自动测速**：内置「自动测速」「源 1」「源 2」。自动模式会像穿行隙间般探测两路直播流（各读取最多 32 KiB 音频）。两路均可用时，候选线路取得音频的耗时改善达到阈值才切换。当前线路不可用时，可直接切换到可用线路。也可随时在设置中手动重测。 [播放源与网络诊断](docs/user/network.md)
- **队列与昨日歌单**：播放队列预告当前频道的后续曲目。昨日歌单按接口返回的顺序显示前一日播出的曲目，保留重复播放记录。
- **封面与曲目详情**：封面加载平滑淡入，缺失时自动回退品牌占位图；队列与历史歌单中的曲目信息支持自由划选文本，也可一键复制。
- **曲目反馈**：收听时可提交曲目反馈（非东方曲目、版权、违规、信息错误或播放异常等）。若服务端返回自动跳过结果，客户端会给出提示。

### 曲库、收藏与投票：同好共鸣

*把散落各处的同人佳作收进红魔馆大图书馆，或为提前切歌投出一票。*

- **曲库检索**：登录后可按关键词检索想听的东方同人曲目。
- **歌单收藏与分享**：将心仪曲目收入收藏夹，快捷收藏默认使用列表首项，重复添加时会提示已收藏。整理后可生成链接分享给同好。
- **实时切歌投票**：在开放投票的频道中，登录后可为提前切歌投票，也可以撤回自己的票。客户端与部署端都需开启投票功能。

### 视觉、主题与大屏幕：从桌角摸鱼到舞台演出

*既能缩在屏幕角落安静陪跑，也能铺满整块屏幕开一场专属的音符演出。*

- **Windows 迷你播放器**：支持将播放器收束至屏幕角落，随时查看曲目并控制播放，也可通过系统托盘一键唤回主窗口。
- **全平台大屏幕模式**：全平台通用，桌面端按 `F11` 切换全屏，`Esc` 或手柄 `B / ○` 键无损返回原页面，完整保留当前焦点与播放状态。[大屏幕模式](docs/user/large-screen.md)
  - **灵活布局与队列**：提供「自适应、封面居左、封面居右、上下」4 种版式，队列支持隐藏、仅显示下一首、横排或可滚动列表。
  - **五种音乐动效**：内置极光流场、星云漫游、棱镜涟漪、镜像频谱与流体渐变，支持调节动效强度与省电模式。
  - **小组件与隐身控制栏**：可自由添加时钟、日期与自定义文本小组件并调整位置与外观。开启自动收起后，播控栏在闲置时隐去，动一动鼠标、键盘或手柄即可唤回。
- **和纸排版与角色主题**：视觉沿用 Web 端思源宋体（Noto Serif SC）通栏设计与 `1.62` 行高；默认灵梦主题采用绯红强调色与粉纸底色，内置**灵梦、魔理沙、⑨（baka9）、蕾米莉亚、觉、恋恋、幽香**等角色主题，支持明暗模式切换，切换时强调色、纸面渐变与背景立绘同步焕新。

### 操控、集成与维护：妖怪之山级工程力

*不靠信仰驱动，靠扎实的原生系统集成与容错机制。*

- **键盘与手柄操控**：桌面端支持键盘导航与播控（`Ctrl+1` 至 `Ctrl+4` 切换主页面，macOS 也支持用 `⌘`，`F1` 打开快捷键与手柄键位图鉴）。Xbox / PlayStation 手柄也可用于导航与播控。 [键盘、手柄与无障碍](docs/user/accessibility.md)
- **深度桌面集成**：Windows 通过 SMTC 提供系统播放控制与曲目信息。Linux 通过 MPRIS 提供播放、暂停、停止、音量、曲目信息与窗口唤起，并提供 GTK 原生标题栏与桌面菜单安装脚本。桌面端重复启动时会唤起已有窗口。macOS 可在「我的 → 关闭按钮」选择每次询问、退出或隐藏至菜单栏。
- **无障碍与减少动画**：播放及窗口控件提供读屏名称，导航项报告选中状态，音量控件支持步进操作。系统开启「减少动画」时，客户端会减少页面、背景与频谱动态。
- **可信应用内更新**：Windows、macOS、Linux 与 Android 可在「我的」内检查更新、开关自动检查或下载、取消下载或忽略特定版本。客户端验证更新清单的 Ed25519 签名和安装包哈希，桌面端替换后若启动失败会自动回滚至原版本。iOS 通过 TestFlight 分发与更新。 [安装与更新](docs/user/install.md)
- **一键网络诊断**：前往「我的 → 播放与网络 → 网络诊断」，即可排查公网 IP 与属地、本机 IPv4/IPv6 接口、系统与内存状态，以及各服务的 HTTP 状态码、响应耗时、DNS、实际连接 IP 与 CDN 标识。报告可导出为 TXT，登录凭据、Cookie 与媒体访问密钥不会写入。 [播放源与网络诊断](docs/user/network.md)

---

## 平台与快速开始

### 安装包与运行环境

前往 [GitHub Releases](https://github.com/Yunmoan/thmr-app/releases) 获取对应平台产物（运行库、首次启动与更新细节见 [安装与更新](docs/user/install.md)）：

| 平台 | 版本 / 架构 | 分发包 | 启动与环境说明 |
| --- | --- | --- | --- |
| **Windows** | x64 | `thmr-app-windows-x64.zip` | 解压后运行 `thmr_app.exe`，内嵌登录依赖 WebView2 Runtime（Windows 11 自带） |
| **macOS** | 12+，Universal | `thmr-app-macos-universal.dmg` | 兼容 Intel 与 Apple Silicon，拖入 `Applications` 后启动（签名与公证视发布配置而定） |
| **Linux** | x64 | `thmr-app-linux-x64.tar.gz` | 主要适配 Ubuntu 24.04，执行 `bundle/thmr` 启动，需具备 GTK、libmpv 等运行库 |
| **Android** | APK | `thmr-app-android.apk` | 下载后通过系统安装器直接安装 |
| **iOS** | 15+ | TestFlight | 通过 TestFlight 邀请链接安装与接收更新 |

### 上手指南

1. **直接开听**：打开客户端后点播放即可收听，无需账号。「收听 / 曲库 / 收藏 / 我的」在窄窗口显示于底栏，在宽窗口显示于侧栏。
2. **按需登录**：需要搜索曲库、管理收藏夹或参与切歌投票时，在「我的」中登录。Linux 上的登录入口会打开网页版，这些功能可在网页中使用。
3. **切换线路与诊断**：遇到网络波动或希望切换播放源，前往「我的 → 播放与网络」。
4. **定制大屏幕**：前往「我的 → 外观 → 大屏幕模式 Beta 配置」调整动效与小组件；桌面端按 `F1` 查看键位说明，按 `F11` 一键进入大屏幕。

### 从源码构建

项目使用 [`.fvmrc`](.fvmrc) 锁定 **Flutter 3.47.5**。安装 FVM 后执行：

```sh
fvm install
fvm flutter pub get --enforce-lockfile
fvm flutter devices
fvm flutter run -d windows
```

将 `windows` 替换为 `macos`、`linux` 或 `fvm flutter devices` 输出的目标设备 ID。桌面端需在对应操作系统环境下构建。

- **Windows**：Visual Studio「使用 C++ 的桌面开发」工作负载及 C++ ATL 组件；内嵌登录需 WebView2。
- **macOS / iOS**：Xcode 和 CocoaPods。 [iOS 开发指南](docs/development/ios.md)
- **Linux**：GTK 3、libmpv、libsecret、jsoncpp 与 AppIndicator 开发包，详见 [Linux 开发指南](docs/development/linux.md)。
- **Android**：Android SDK 及可用的真机或模拟器。

### 本地验证与 CI

本地可按与 GitHub Actions CI 一致的顺序执行静态检查与测试（Windows 环境通常使用 `python` 替代 `python3`）：

```sh
python3 -m unittest discover -s tool -p 'test_*.py' -v
node --test tool/test_update_release.cjs
fvm flutter analyze --no-pub
fvm flutter test --no-pub
```

桌面端和 Android 的 PR 构建产物会上传至 Actions Artifacts。默认分支构建成功后生成预发布，推送 `v<版本>` 标签可触发对应 Release。iOS 的 PR 构建用于无签名编译检查，TestFlight 由独立工作流上传。 [发布指南](docs/release/README.md)

---

## 技术栈

| 层面 | 选型 | 在 THMR 中的职责 |
| --- | --- | --- |
| **应用框架** | Flutter 3.47.5 · Dart | 单套 Dart 业务代码覆盖桌面与移动五端 |
| **状态管理** | Riverpod | 驱动频道、播放器、收藏夹、账号会话与更新状态 |
| **网络通信** | Dio | 封装 Radio 与 THMR 业务接口、Bearer 鉴权与统一错误映射 |
| **音频播放** | media_kit | 基于 libmpv 播放直播流，切换码率时连接新的直播流 |
| **媒体会话** | audio_service · audio_session | Android 和 iOS 的后台播放、系统媒体会话与音频焦点管理 |
| **桌面原生集成** | window_manager · tray_manager · smtc_windows | 自绘标题栏、系统托盘与 Windows SMTC 接入 |
| **身份认证** | flutter_inappwebview | 承载 Natayark OAuth 内嵌登录（Linux 走外部浏览器入口） |
| **安全存储** | flutter_secure_storage | 加密持久化保存会话 Token |
| **外设输入** | gamepads | 游戏手柄焦点导航与快捷播控 |
| **原生音频频谱** | C++ · Java · minimp3 | WASAPI 音频采样、原生解码与实时 FFT 计算 |
| **图形渲染** | Fragment Shader · 自绘控件 | 大屏幕音乐动效、频谱可视化与主题绘制 |
| **更新安全** | Ed25519 · 哈希校验 | 更新清单数字签名验证、安装包完整性校验与异常回滚 |
| **工程化** | FVM · GitHub Actions | 锁定 SDK 版本，自动化多端构建与 Release 发布 |

## 项目结构

| 路径 | 职责说明 |
| --- | --- |
| [`lib/main.dart`](lib/main.dart)、[`lib/app.dart`](lib/app.dart) | 初始化播放器内核、平台环境与主题系统，挂载全局输入监听 |
| [`lib/core/`](lib/core/) | 网络 API、数据模型、Riverpod 状态、播放控制、应用更新、诊断与平台桥接 |
| [`lib/features/`](lib/features/) | 收听、曲库、收藏、账号、网络诊断、迷你播放器与大屏幕等业务模块 |
| [`lib/shared/widgets/`](lib/shared/widgets/) | 跨模块复用的基础 UI 组件 |
| [`native/`](native/)、各平台目录 | 原生频谱采样、播放辅助与各系统运行器集成 |
| [`assets/`](assets/)、[`shaders/`](shaders/) | 品牌视觉素材、角色图标、安装脚本与大屏幕着色器代码 |
| [`test/`](test/)、[`tool/`](tool/) | 单元与集成测试、CI 辅助脚本及手动验证工具 |
| [`docs/`](docs/) | 用户手册、开发文档与发布规范 |

## 文档索引

| 文档 | 内容概览 |
| --- | --- |
| [使用指南](docs/user/README.md) | 安装与更新、Linux 桌面配置、大屏幕模式、键盘与手柄、播放源与网络诊断 |
| [开发指南](docs/development/README.md) | 本地环境搭建、代码入口导览、后端接口接入、频谱管线与测试验证 |
| [发布指南](docs/release/README.md) | GitHub Releases 流程、包签名、更新服务 API 与 TestFlight 分发 |
| [更新日志](CHANGELOG.md) | 当前版本的发布说明 |

---

## 参与 THMR

遇到奇怪的「异变」或有新的功能脑洞，欢迎提交 Issue。若是播放或网络问题，可在「我的 → 播放与网络 → 网络诊断」导出报告，检查并删去不希望公开的 IP 等信息后，再随 Issue 附上。

发现宝藏同人曲想找人安利，也欢迎来官方交流群一起听歌摸鱼。如果这个小电台合你胃口，不妨在 GitHub 顺手点一颗 Star——毕竟连某位黑白魔法使路过都要顺走几颗星星，DA☆ZE！

[GitHub Issues](https://github.com/Yunmoan/thmr-app/issues) · [官方 QQ 群](https://qm.qq.com/q/pKXxsx4m52) · [GitHub 项目页](https://github.com/Yunmoan/thmr-app)

### 新贡献者留名

首次向 THMR 提交 PR 时，请在同一个 PR 里把自己的 GitHub 用户名（不带 `@`）追加到 `_contributors` 列表末尾。按 PR 合入顺序留名，原有条目按现有顺序保留。若遇到合并冲突，请先同步目标分支的名单，再把自己的用户名追加到末尾。已在名单中的贡献者只需提交本次改动。

名单会显示在客户端的「我的 → 关于 → 项目与社区」。 [编辑贡献者名单](lib/features/account/about_panel.dart#L100)

---

<p align="center">
  <sub>THMR · Touhou Music Radio 客户端 · 基于 Flutter 构建</sub>
</p>
