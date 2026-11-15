# THMR 客户端(Flutter)

东方音乐电台 **THMR(TouHouMusicRadio)** 跨平台客户端 — Windows / macOS / Linux / Android / iOS。

对接双后端(均无需改动):

- Radio 流媒体后端:`https://radio.yunmoan.cn`(状态 / 直播流 / 封面 / 反馈)
- THMR 账号后端:`https://api.yunmoan.cn`(Natayark 登录 / 收藏 / 投票 / 曲库代理)

接口契约详见 [FLUTTER.md](FLUTTER.md)。

## 快速开始

```bash
flutter pub get
flutter run -d windows          # Windows 桌面
flutter run -d macos            # macOS（在 macOS 上运行）
flutter run -d linux            # Linux（在 Linux 上运行）
flutter run -d <android-device> # Android
```

## 键盘、手柄与无障碍

Tab / Shift+Tab 遍历控件，Enter / 空格操作选中的按钮。Ctrl（macOS 为 ⌘）+ 1–4 切换主页面，+ F 定位曲库搜索，+ P 播放/暂停，+ ↑ / ↓ 调整音量。Ctrl+M 静音（macOS 使用 ⌘+Shift+M，保留 ⌘+M 最小化）；Windows 使用 Ctrl+Shift+M 切换迷你播放器。Esc 关闭可取消的弹窗或返回，迷你模式下恢复主窗口。

手柄十字键或左摇杆移动焦点，A / × 确认、B / ○ 返回，X / □ 播放/暂停，Y / △ 搜索，LB / L1 和 RB / R1 切页，右摇杆上下滚动、按下静音。文本输入仍使用键盘或系统输入法。手柄输入只在应用前台生效。

按 F1 或在「我的 → 操作帮助 → 键盘与手柄操作」查看图文说明。按键图标采用 Kenney Input Prompts（CC0）。隐藏页面隔离焦点，主要自绘控件提供焦点框，播放与窗口按钮提供读屏名称，角色主题调整强调色以保证实色面板和按钮文字对比度。支持范围和真机验收项见 [无障碍说明](docs/ACCESSIBILITY.md)。

## 播放源与网络诊断

在「我的 → 播放与网络」选择「自动测速」「源 1」或「源 2」，选择会持久化。
自动模式在启动时同时对两路直播流进行有界采样，优先选择连接并读取 32 KiB 音频更快的可用来源；也可手动重新测速。
播放中切换来源会保留码率并重新连接，已暂停时保持暂停。手动指定来源不会被测速结果覆盖。

点击「网络诊断」即可查看公网 IP 与属地（`https://myip.ipip.net/json`）、本机 IPv4/IPv6 接口、系统环境、应用与系统内存，以及六个服务的 HTTP 状态、响应耗时、DNS、实际连接 IP 和 CDN 响应标识。
诊断以收到 HTTP 响应为连通，包含域名根路径的 404；节点名称未公开时仅展示实际 IP 与服务端提供的标识。
「导出 TXT」使用系统另存为窗口，生成含 UTF-8 BOM 的中文文本报告；不写入登录凭据、Cookie 或流媒体访问密钥。

开发时可用 `dart tool/diagnostics_smoke.dart` 检查真实接口并在本地 `build/` 生成报告，普通测试使用本地服务或模拟结果。

## 客户端版本与自动更新

客户端只向 `https://api.zyghit.cn/updater/thmr` 检查更新。支持后台下载、Ed25519 清单验签、SHA-256 文件校验、准确匹配平台架构、应用内安装；桌面端自动替换和重启，启动失败自动恢复旧版。Android 使用系统安装器，仍需用户确认。自动检查与自动下载均可关闭，支持取消下载和忽略版本。

界面、更新比较和安装包统一使用客户端构建版本。CI 标签 `v0.2.0` 对应 `0.2.0`，构建号是 `Actions run number × 100 + run attempt`；普通本地构建取 `pubspec.yaml`，可由 `--build-name` / `--build-number` 覆盖。更新 API 不依赖电台或账号后端的版本号。

API 插件单独交付为 OPENAPI-Next-Core 的 Next ZIP 包，也兼容 legacy 单文件方式；保留原 `/ofcpl` 路由，不纳入客户端仓库。完整的密钥、API 插件部署、GitHub Variables/Secrets、Android 签名、macOS 公证和发版步骤见 **[自动更新配置文档](docs/AUTO_UPDATE.md)**。

安装包构建完成后会逐个平台上传到同一个 GitHub Release 草稿，仓库所有者可先下载；全部平台完成后自动发布（普通构建为预发布，`v*` 稳定标签为正式发布）。你下载原包上传到镜像后，修改 Next 插件 `apis/updater/index.js` 顶部 `THMR_DOWNLOAD_URLS` 的四个地址，再把 Release 的签名清单放到插件的 `data/`。支持 `thmr-update.json` 和 `thmr-release.json`，后者优先；legacy 使用项目根目录的 `data/updates/`。`/updater/thmr/status` 可检查已验签的版本和故障类型。镜像地址可以单独调整，版本、文件大小与哈希仍经过验签。

CI 自动获取最新 Flutter stable 和 Node.js LTS；同一次构建的四个平台共用解析后的 Flutter SDK。GitHub Actions 跟随最新稳定主版本，Dependabot 每周检查后续主版本升级。Windows 使用 `windows-latest`，Linux 固定 `ubuntu-24.04` 作为兼容基线；macOS 因 arm64 容量不足暂用当前稳定版 Intel 运行器，仓库 Variable `THMR_MACOS_RUNNER` 可覆盖为 `macos-latest`。Java 自动选取当前 Gradle 支持范围内的最新稳定版。

## 构建与发布

`.github/workflows/build.yml` 在各平台系统上构建，并打包完整安装目录：

| 平台 | 产物 |
| --- | --- |
| Windows x64 | `thmr-app-windows-x64.zip` |
| macOS 12+，Intel / Apple Silicon | `thmr-app-macos-universal.dmg`（拖拽安装）；另附 `.zip` 供客户端自更新 |
| Linux x64 | `thmr-app-linux-x64.tar.gz` |
| Android | `thmr-app-android.apk` |

普通构建保存在 Actions Artifacts。所有平台完成后发布 Release；稳定版本同时生成签名更新清单，需要按上述步骤部署到自有更新 API。macOS、Linux 的本地构建必须在对应系统进行。

macOS DMG 包含 THMR 应用、Applications 拖拽入口和中英文安装引导背景。先拖入 Applications，再从该目录启动。更新镜像中的 macOS 地址仍填写 ZIP，现有客户端的安装器使用此格式。

Linux Debian/Ubuntu 构建依赖：

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev \
  liblzma-dev g++ libsecret-1-dev libjsoncpp-dev \
  libayatana-appindicator3-dev libmpv-dev mpv
```

分发时保留整个 `bundle/`，使用 `./thmr` 启动，可运行 `./install-desktop.sh` 添加当前用户的应用菜单入口。运行系统仍需 libmpv、GTK、libsecret、jsoncpp 和 Ayatana AppIndicator 等运行库；频谱使用内置 minimp3，无需安装 FFmpeg 命令。Linux 已接入托盘、关闭行为设置、MPRIS 系统媒体控制和本应用实时频谱，托盘不可用时回退任务栏最小化。Linux 登录保留网页版入口，本轮不适配客户端登录和迷你播放器；macOS/Linux 使用原生标题栏。完整安装、测试和兼容边界见 [Linux 使用说明](docs/LINUX.md)。

桌面端（Windows / macOS / Linux）每个登录会话只运行一个实例。重复启动会退出新进程并唤起已有窗口；Windows 支持从托盘隐藏或最小化状态恢复，并保留当前的主窗口 / 迷你播放器模式。退出或崩溃后可正常重新启动。

macOS 已接入菜单栏图标：点击图标打开“显示主窗口／退出”菜单。在“我的 → 关闭按钮”可选择每次询问、退出程序或隐藏到菜单栏；隐藏后继续播放，可通过菜单栏、Dock 或重复启动恢复窗口。菜单栏图标不可用时回退到 Dock 最小化，Cmd+Q 与菜单“退出”共用音频资源清理流程。实现与验证边界见 [性能与 macOS 说明](docs/PERFORMANCE_AND_MACOS.md)。

## 设计语言:「幻想乡放送局」

与 Web 端(`thmr/src/styles/tokens.css`)同一套令牌,源出博丽神社的红白配色:

| 令牌 | 浅色 | 深色 |
| --- | --- | --- |
| 页面底 `pageBg` | `#fbf2f4`(粉纸渐变) | `#160d10`(酒红黑渐变) |
| 主墨 `ink` | `#24161a` | `#f8edf0` |
| 弱化 `mutedInk` | `#6f5960` | `#d7c1c8` |
| 面板 `panelBg` | `rgba(255,251,252,.92)` 毛玻璃 | `rgba(31,19,23,.90)` |
| 描边 `panelBorder` | `rgba(84,34,46,.16)` | `rgba(255,228,236,.13)` |
| 强调 `accent` | `#c65a69` 绯红(可被 `station.public.accentColor` 运行时覆盖) | 同左 |

排版:**思源宋体(Noto Serif SC)通栏**,正文行高 1.62,与 Web 端一致。
背景:所选角色的插画固定在左下方，页面使用透明底色与半透明渐变遮罩；切换主题时插画平滑过渡。
品牌元素:logo 的鸟居「T」、阴阳玉「R」、电波弧线被复用为封面 fallback、空状态插画。

## 目录结构

```
lib/
├── main.dart                  # MediaKit 初始化 + Riverpod
├── app.dart                   # MaterialApp + 明暗主题
├── core/
│   ├── config.dart            # JSON 资产内置 + --dart-define 覆盖
│   ├── theme/                 # 设计令牌 + ThemeData 工厂
│   ├── models/models.dart     # 后端 JSON 模型(ID 全 String)
│   ├── api/                   # RadioApi / ThmrApi(dio,统一 {error} 解析)
│   ├── player/                # media_kit 直播流播放器 + 状态机
│   └── state/                 # 轮询 / 设置 / 认证 / 收藏 providers
├── shared/widgets/            # 纸面板、插画背景、封面、LIVE 徽标
└── features/
    ├── shell/                 # 底部导航 / 宽屏 NavigationRail
    ├── listen/                # 收听页:正在放送 + 码率 + 队列 + 反馈 + 投票
    ├── library/               # 曲库搜索(账号后端代理)
    ├── collections/           # 收藏夹列表 / 详情 / 分享 / 导出
    └── account/               # 账号 + 主题设置 + 关于
```

## 已实现(对齐 FLUTTER.md 里程碑)

- **M1 播放器**:状态双定时器轮询(10s + `expectedEndMs` 精准换曲刷新)、media_kit 直连 MP3 流、直播状态机(idle/connecting/online/buffering/reconnecting,重连策略与 Web 端一致)、码率切换(按 station 持久化、播放中热切换)、听众数 / LIVE 徽标
- **系统媒体控制**:Windows SMTC、Linux MPRIS 与 Android/iOS `audio_service` 同步曲目信息、播放状态和进度；系统播放/暂停键共用直播流状态机，不提供直播流 seek。
- **M5 反馈**:曲目反馈表单(10 类枚举、联系方式必填、`autoSkipped` 提示)
- **M4 部分**:切歌投票(阈值来自 `/api/meta`,公开接口可看票数)
- **M2 账号**:Bearer 会话存取、`/auth/me` 引导、昵称修改与内置 WebView 登录（Linux 除外）
- **M3 骨架**:收藏夹 CRUD / 曲库搜索加曲 / 收藏 toggle / 默认收藏夹约定(首个 position 最小)/ 409 幂等提示;分享开关已接 `/share`

## 待接入

| 项 | 说明 |
| --- | --- |
| Linux 登录 | 保留网页版入口，本轮不适配；当前后端没有可用于桌面浏览器登录的凭据交付契约 |
| macOS 桌面扩展 | 菜单栏托盘和关闭行为已接入；迷你窗口和频谱原生实现待接入 |
| Linux 迷你播放器 | 本轮明确不适配 |
| 评论 / 广场 | 等后端 `/api/social/*` 接口落地后再对接(FLUTTER.md 第十章) |

## 平台注意

- Android:`INTERNET` 权限由 Flutter 模板自带;minSdk 默认满足(≥21);全 HTTPS。
- iOS:已配置 `audio_service` 和 `UIBackgroundModes: audio`；锁屏显示仍需在真机核验。
- Windows:首次构建需 Visual Studio 2022 桌面 C++ 工作负载。
- 字体:google_fonts 首次联网拉取 Noto Serif SC;离线发布时将字体文件放入 `assets/google_fonts/`(见 google_fonts 文档)即可免下载。
