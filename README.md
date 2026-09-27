# THMR 客户端(Flutter)

东方音乐电台 **THMR(TouHouMusicRadio)** 跨平台客户端 — PC / Android / iOS。

对接双后端(均无需改动):

- Radio 流媒体后端:`https://radio.yunmoan.cn`(状态 / 直播流 / 封面 / 反馈)
- THMR 账号后端:`https://api.yunmoan.cn`(Natayark 登录 / 收藏 / 投票 / 曲库代理)

接口契约详见 [FLUTTER.md](FLUTTER.md)。

## 快速开始

```bash
flutter pub get
flutter run -d windows          # Windows 桌面
flutter run -d <android-device> # Android
```

Windows 标题栏的画中画按钮可切换到迷你播放器。迷你窗无系统外框，双击窗口或点击右上角展开按钮可返回主界面。拖到任一显示器工作区的顶边会优先吸附，左右边也支持；贴边侧变为直角。「我的 → 迷你播放器吸边」提供三种方式：默认二段式在顶边留下封面、歌名和作者（侧边显示小条）；显示小条仅留下顶边 44×16 像素或侧边 16×44 像素的入口；完全隐藏仅在原吸附位置留下透明的鼠标触发区，也可从系统托盘恢复。同处可开启跟随当前主题的人物立绘背景，默认关闭。悬停或点击可展开，移出后再次收起。将展开后的窗口拖离边缘可取消吸附。

配置覆盖(可选):

```bash
flutter run \
  --dart-define=THMR_RADIO_BASE_URL=http://localhost:3323 \
  --dart-define=THMR_BASE_URL=http://localhost:3324 \
  --dart-define=THMR_STATION_ID=main \
  --dart-define=THMR_STREAM_TOKEN=...
```

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
- **M2 骨架**:Bearer 会话存取(flutter_secure_storage)、`/auth/me` 引导、昵称修改;**WebView 登录流程待接入**(见下)
- **M3 骨架**:收藏夹 CRUD / 曲库搜索加曲 / 收藏 toggle / 默认收藏夹约定(首个 position 最小)/ 409 幂等提示;分享开关已接 `/share`

## 待接入

| 项 | 说明 |
| --- | --- |
| WebView 登录(M2) | `flutter_inappwebview` 打开 `/api/auth/login?redirect=https://thmr.yunmoan.cn/`,落地后读 `thmr_session` Cookie(必须 in-app WebView,HttpOnly),存 Bearer |
| 桌面托盘 | 关窗最小化到托盘继续播放(window_manager / tray_manager) |
| 评论 / 广场 | 等后端 `/api/social/*` 接口落地后再对接(FLUTTER.md 第十章) |

## 平台注意

- Android:`INTERNET` 权限由 Flutter 模板自带;minSdk 默认满足(≥21);全 HTTPS。
- iOS:已配置 `audio_service` 和 `UIBackgroundModes: audio`；锁屏显示仍需在真机核验。
- Windows:首次构建需 Visual Studio 2022 桌面 C++ 工作负载。
- 字体:google_fonts 首次联网拉取 Noto Serif SC;离线发布时将字体文件放入 `assets/google_fonts/`(见 google_fonts 文档)即可免下载。
