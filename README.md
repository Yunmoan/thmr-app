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

## 客户端版本与自动更新

客户端只向 `https://api.zyghit.cn/updater/thmr` 检查更新。支持后台下载、Ed25519 清单验签、SHA-256 文件校验、准确匹配平台架构、应用内安装；桌面端自动替换和重启，启动失败自动恢复旧版。Android 使用系统安装器，仍需用户确认。自动检查与自动下载均可关闭，支持取消下载和忽略版本。

界面、更新比较和安装包统一使用客户端构建版本。CI 标签 `v0.2.0` 对应 `0.2.0`，构建号是 `Actions run number × 100 + run attempt`；普通本地构建取 `pubspec.yaml`，可由 `--build-name` / `--build-number` 覆盖。更新 API 不依赖电台或账号后端的版本号。

部署插件为 [`server-plugin/updater.js`](server-plugin/updater.js)，保留原 `/ofcpl` 路由。完整的密钥、API 插件部署、GitHub Variables/Secrets、Android 签名、macOS 公证和发版步骤见 **[自动更新配置文档](docs/AUTO_UPDATE.md)**。正式发布前必须完成文档中的密钥与签名配置。

## 构建与发布

`.github/workflows/build.yml` 在各平台系统上构建，并打包完整安装目录：

| 平台 | 产物 |
| --- | --- |
| Windows x64 | `thmr-app-windows-x64.zip` |
| macOS 12+，Intel / Apple Silicon | `thmr-app-macos-universal.zip` |
| Linux x64 | `thmr-app-linux-x64.tar.gz` |
| Android | `thmr-app-android.apk` |

普通构建保存在 Actions Artifacts。正式标签在全部构建通过后生成 Release 和签名更新清单，并按配置自动发布到自有更新 API；尚未配置发布 token 时可手动部署签名清单。macOS、Linux 的本地构建必须在对应系统进行。

Linux Debian/Ubuntu 构建依赖：

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev \
  liblzma-dev libstdc++-12-dev libsecret-1-dev libjsoncpp-dev \
  libayatana-appindicator3-dev libmpv-dev mpv
```

分发时保留整个 `bundle/`，运行系统仍需 libmpv、GTK、libsecret、jsoncpp 和 Ayatana AppIndicator 等运行库。Linux 内置 WebView 登录暂不支持，可使用网页版；macOS/Linux 暂用原生标题栏。Windows 托盘和迷你播放器保持原有行为。

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
- **系统媒体控制**:Windows SMTC 与 Android/iOS `audio_service` 同步曲目信息、播放状态和进度；系统播放/暂停键共用直播流状态机，不提供直播流 seek。
- **M5 反馈**:曲目反馈表单(10 类枚举、联系方式必填、`autoSkipped` 提示)
- **M4 部分**:切歌投票(阈值来自 `/api/meta`,公开接口可看票数)
- **M2 账号**:Bearer 会话存取、`/auth/me` 引导、昵称修改与内置 WebView 登录（Linux 除外）
- **M3 骨架**:收藏夹 CRUD / 曲库搜索加曲 / 收藏 toggle / 默认收藏夹约定(首个 position 最小)/ 409 幂等提示;分享开关已接 `/share`

## 待接入

| 项 | 说明 |
| --- | --- |
| Linux 登录 | 当前 WebView 插件不支持 Linux，需替换登录方案或提供系统浏览器回调接口 |
| macOS/Linux 桌面扩展 | 托盘、迷你窗口和频谱原生实现待接入；Windows 已支持 |
| 评论 / 广场 | 等后端 `/api/social/*` 接口落地后再对接(FLUTTER.md 第十章) |

## 平台注意

- Android:`INTERNET` 权限由 Flutter 模板自带;minSdk 默认满足(≥21);全 HTTPS。
- iOS:已配置 `audio_service` 和 `UIBackgroundModes: audio`；锁屏显示仍需在真机核验。
- Windows:首次构建需 Visual Studio 2022 桌面 C++ 工作负载。
- 字体:google_fonts 首次联网拉取 Noto Serif SC;离线发布时将字体文件放入 `assets/google_fonts/`(见 google_fonts 文档)即可免下载。
