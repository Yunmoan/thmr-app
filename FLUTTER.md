# THMR Flutter 客户端开发文档

> 读者:开发 Flutter 跨平台客户端(PC / Android / iOS)的开发者。
> 目标:对接现有两个后端(Radio Livestream 后端 + THMR 账号后端),实现与 Web 端(PWA)对等的功能,并为评论、广场等 App 特色功能预留扩展点。
> **现状:两个后端不需要任何改动即可支撑本文档描述的全部基础功能。** 所有接口契约均从后端源码核实(2026-09)。

---

## 一、架构总览

```
┌─────────────────────────┐        ┌─────────────────────────┐
│  Radio Livestream 后端   │◄──私有──│    THMR 账号后端          │
│  radio.yunmoan.cn:3323  │  API+  │    api.yunmoan.cn:3324   │
│                         │ API key│                          │
│  · 直播流(MP3/HLS)      │        │  · Natayark OAuth 登录    │
│  · 电台状态 / 队列 / 封面 │        │  · 收藏夹 / 分享 / 导出    │
│  · 曲库搜索(v1 机器接口) │        │  · 投票切歌               │
│  · 曲目反馈              │        │  · 代理曲库搜索            │
└───────────▲─────────────┘        └───────────▲─────────────┘
            │                                  │
            │  流 + 状态 + 封面 + 反馈           │  会话(Bearer)+ 业务接口
            │                                  │
┌───────────┴──────────────────────────────────┴─────────────┐
│                Flutter 客户端(PC / Android / iOS)           │
│   基础功能 = Web PWA 对等:收听 / 登录 / 收藏 / 分享 / 投票     │
│   App 特色(规划):评论 / 广场(后端接口未实现)               │
└─────────────────────────────────────────────────────────────┘
```

要点:

- 客户端同时对接**两个后端**,各自独立域名,互不代理(曲库搜索除外——走账号后端代理)。
- Web PWA 是功能参照物,源码在 `thmr/src/`(Vue 3 + Pinia),本文档的状态机、轮询策略均与 Web 端保持一致。
- 原生客户端没有浏览器 CORS 机制,两个后端都**不需要**为 App 配置来源白名单。

---

## 二、基础配置

| 配置项 | 生产值 | 说明 |
| --- | --- | --- |
| `radioBaseUrl` | `https://radio.yunmoan.cn` | Radio 后端(流 / 状态 / 封面 / 反馈) |
| `thmrBaseUrl` | `https://api.yunmoan.cn` | 账号后端(登录 / 收藏 / 投票) |
| `stationId` | `main` | 频道 ID |
| `streamToken` | 与 Web 端 `dist/config.js` 的 `token` 同值 | 仅当电台 `streamAuth.enabled=true` 时必填;追加在流地址与反馈接口上 |
| `features.vote` | Web 端当前为 `false`(隐藏) | App 建议同样做成开关,并可在运行时按 `GET /api/meta` 调整 |

建议:配置以 JSON 资产内置 + `--dart-define` 覆盖;`streamToken` 属于发布物敏感项,更新随版本走。

---

## 三、通用约定(必读)

1. **全部 JSON**(`export` 接口除外);错误响应统一为 `{"error": "<message>"}`。
2. **ID 一律是字符串**:`trackId`、`collectionId`、`itemId`、`userId` 在 Dart 中用 `String` 接,不要用 int。
3. **时间戳两套**:
   - `*Ms` 后缀(`startedAtMs` / `expectedEndMs` / `submittedAtMs` / `plannedStartMs`):毫秒 epoch,`int`。
   - `createdAt` / `updatedAt` / `addedAt` / `expiresAt`:ISO 8601 字符串或 `null`。
4. **`coverUrl` 相对/绝对不一致**(易踩坑):
   - Radio 后端直接返回的 `coverUrl` 是**相对路径**(如 `/api/stations/main/tracks/xxx/cover`,无封面时为 `""`);
   - 账号后端返回的 `coverUrl` 是**绝对 URL**。
   - 统一处理:非 `http` 开头就拼 `radioBaseUrl`。
5. **缓存**:所有 `/api/*` 响应带 `Cache-Control: no-store`,不要做 HTTP 层缓存;封面图可正常缓存。
6. **503** 有两种:Radio 返回 `station disabled`;账号后端 MySQL 不可用时业务接口失败,可稍后重试。
7. **401 `authentication required`**:会话过期,清 token 引导重新登录(会话 TTL 168 小时)。
8. **直播流没有 seek/总时长概念**,播放器 UI 不要做进度条拖动;「已收听时长」只能自己计时。

---

## 四、收听链路(核心)

### 4.1 流地址

```
GET {radioBaseUrl}/radio/{stationId}/{profileId}        # 直连 MP3 直播流(推荐)
GET {radioBaseUrl}/radio/{stationId}/{profileId}.mp3    # 等价
GET {radioBaseUrl}/radio/{stationId}/{profileId}.m3u8   # HLS(App 一般不需要)
GET {radioBaseUrl}/radio/{stationId}/{profileId}.m3u    # 文本播放列表(内嵌带 token 的流地址)
```

- `profileId` 取自状态接口的 `station.bitrates[]` 中 `enabled !== false` 的条目(如 `96k` / `128k` / `320k`)。
- `streamToken` 存在时统一追加 `?token={streamToken}`(流、m3u、反馈接口都要带;状态 / 封面接口不需要,但统一带上也无害)。
- 直播流为无限 MP3 流,播放器需按「直播」处理(见 4.3)。

### 4.2 码率切换

更换 `profileId` = 更换流地址重连:记录用户选择(按 station 隔离持久化),若正在播放则切完继续播放。Web 端行为:切换瞬间可能有小段缓冲,属正常。

### 4.3 元数据轮询与换曲

参照 Web 端([thmr/src/stores/station.js](src/stores/station.js))的双定时器策略:

1. **常规轮询**:`GET /api/stations/{stationId}/status`,每 **10s** 一次。
2. **精准换曲刷新**:每次拿到状态后,若 `current.expectedEndMs` 存在,则定时在 `expectedEndMs - now + 800ms` 再拉一次,换曲几乎零延迟。

`current.trackId` 变化时:刷新 UI、更新媒体通知(见第五章)、重置投票轮次展示。

### 4.4 播放状态机

与 Web 端 `player store` 对齐:

| 状态 | 含义 | 进入条件 |
| --- | --- | --- |
| `idle` | 待机 | 初始 / 用户暂停 / 自动播放放弃 |
| `connecting` | 连接中 | 发起 play 后未出声 |
| `online` | 在线 | 播放器进入 playing |
| `buffering` | 缓冲中 | `waiting` 事件 |
| `reconnecting` | 重连中 | 出错后的自动恢复期 |

断线恢复建议(对齐 Web 端):`waiting` 持续 >5s 或 `stalled` → 3s 后重连;`error` → 1s 后重连(重设数据源并 play);用户已手动暂停则不自动恢复;连续失败 N 次后退回 `idle` 并提示。

### 4.5 技术选型建议

| 端 | 推荐 | 备注 |
| --- | --- | --- |
| Android / iOS | `just_audio` + `audio_service` | 后台播放、通知栏媒体控制、音频聚焦一套解决;`just_audio` 可直接播无限 MP3 流 |
| Windows / macOS / Linux | `media_kit` | `just_audio` 的桌面实现(`just_audio_windows` 等)功能有限 |
| 网络 | `dio` | 拦截器统一追加 Bearer / token、解析 `{error}` |
| 状态管理 | Riverpod 或 Bloc 任选 | 本文档不约束 |
| 安全存储 | `flutter_secure_storage` | 存会话 token |
| WebView(仅登录用) | `flutter_inappwebview` | 见第六章 |

---

## 五、后台播放与媒体通知

- `audio_service` 配置 `AndroidForegroundType.mediaPlayback`,Android 通知栏常驻;iOS 开 `UIBackgroundModes: audio`。
- `MediaItem`:title = `current.title`,artist = `current.artist`,artUri = 封面绝对地址,album 可空。轮询到 `current.trackId` 变化时更新 `MediaItem`(换曲通知同步)。
- **不要暴露 seek / 上一曲**:直播流没有这些能力,通知栏只放「播放 / 暂停」。
- 控制中心(iOS 锁屏 / Android 通知)的播放暂停需与 4.4 状态机联动。
- 桌面端:关窗最小化到托盘时保持播放。
- macOS 系统媒体控制:原生 `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`(`macos/Runner/MediaControls.swift`,通道 `thmr/macos_media`),与 Windows SMTC / Linux MPRIS 共用 `audio_engine` 的同一套更新入口;媒体键经 togglePlayPauseCommand 按当前状态映射为 play/pause。

---

## 六、登录与认证(重点)

### 6.1 关键前提

账号后端会话提取**同时支持两种载体**(`thmr/backend/src/auth.js`):

- Cookie `thmr_session`(Web 端用);
- `Authorization: Bearer <token>`,token 值 = Cookie 的值。

→ **App 采用 Bearer 方案**:从 WebView 提取一次 token,之后所有请求走 header,无需维护 CookieJar。

### 6.2 登录流程

```
App ── WebView 打开 ──► GET {thmrBaseUrl}/api/auth/login?redirect=https%3A%2F%2Fthmr.yunmoan.cn%2F
        (302 → Natayark 授权页 → 用户登录授权)
        (302 → GET /api/auth/callback?code&state → 服务端换 token、建会话)
        (Set-Cookie: thmr_session=...; 302 → redirect 地址,必要时附 &profile_setup=nickname)
App ◄── 落地页已携带会话 Cookie ── CookieManager 提取 thmr_session 值
App ── 保存到安全存储,后续全部请求带 Authorization: Bearer <token>
```

实现要点:

1. **必须用 in-app WebView**(系统外部浏览器拿不到会话 Cookie)。`redirect` 参数填 `https://thmr.yunmoan.cn/`(该域在后端 `frontendOrigins` 白名单内,会被接受)。
2. 落地后读 `thmr_session` Cookie(注意 HttpOnly——`flutter_inappwebview` 的 `CookieManager` 可读取,`webview_flutter` 不行;这也是推荐前者的原因)。
3. 提取成功立即关 WebView;调 `GET /api/auth/me` 验证。
4. `user.needsNickname == true`(首次登录)→ 强制昵称设置页:`PATCH /api/auth/profile`,`nickname` 2–64 字符;命中敏感词返回 400「昵称包含违规或不当内容，请修改」,需提示用户改。
5. 会话 168h;任意接口 401 → 清 token 重走登录。登出:`POST /api/auth/logout`(带 token)再清本地。

---

## 七、API 契约

### 7.1 Radio 后端(`radioBaseUrl`)— 全部免登录

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/healthz` | 探活 `{ok, version, stations}` |
| GET | `/api/version` | 版本信息 |
| GET | `/api/stations` | 电台列表(含各台当前曲、听众数) |
| GET | `/api/stations/:sid/status` | **核心状态接口**(结构见下) |
| GET | `/api/stations/:sid/playlist` | 队列数组(≤200 条,同 status.queue) |
| GET | `/api/stations/:sid/preview?date=YYYY-MM-DD` | 当日节目单 |
| GET | `/api/stations/:sid/tracks/:trackId/cover` | 曲目封面图 |
| GET | `/api/stations/:sid/cover` | 电台封面图 |
| POST | `/api/stations/:sid/feedback` | 曲目反馈(见 7.3) |
| GET | `/radio/:sid/:profileId` | 直播流(4.1) |

**`GET /api/stations/:sid/status` 响应结构:**

```jsonc
{
  "station": {
    "id": "main", "name": "东方音乐电台 THMR", "enabled": true,
    "public": { "enabled": true, "title": "...", "description": "...", "accentColor": "#c65a69" },
    "streamAuthEnabled": false,
    "bitrates": [ { "id": "128k", "bitrateKbps": 128, "sampleRate": 44100, "channels": 2, "enabled": true } ]
  },
  "runtime": { "active": true, "paused": false, "scanInProgress": false },
  "totals": { "listeners": 12, "rawConnections": 12, "uniqueIps": 8 },
  "profiles": [ { "id": "128k", "listeners": 12, "rawConnections": 12 } ],
  "libraryCount": 1024,
  "current": {                       // 可能为 null(无曲目)
    "trackId": "abc123", "title": "...", "artist": "...", "relativePath": "...",
    "coverUrl": "/api/stations/main/tracks/abc123/cover",   // 相对路径!见通用约定 4
    "startedAtMs": 1758770000000, "expectedEndMs": 1758770200000,
    "positionSec": 30, "durationSec": 200
  },
  "previous": { "trackId": "...", "title": "...", "artist": "...", "coverUrl": "..." },
  "queue": [ { "trackId": "...", "title": "...", "artist": "...", "coverUrl": "...",
               "plannedStartMs": 0, "plannedEndMs": 0, "durationSec": 180 } ],
  "backend": { "version": "..." }
}
```

错误:`404 {"error":"station not found"}`;`503 {"error":"station disabled"}`。

### 7.2 账号后端(`thmrBaseUrl`)

除标注「公开」外均需登录(Bearer);登录态指有效会话,不区分 Cookie/Bearer 载体。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 公开。探活 `{ok, version, database: "up"\|"down", uptimeSec}` |
| GET | `/api/meta` | 公开。`{version, auth.natayarkConfigured, radio.publicBaseUrl, radio.defaultStationId, vote.threshold, collections.maxPerUser, collections.maxItemsPerCollection}` —— 启动时拉取,投票阈值/上限以它为准 |
| GET | `/api/auth/me` | `{user: {id, naidsId, username, nickname, email, realnameVerified, createdAt, needsNickname}}` |
| PATCH | `/api/auth/profile` | body `{nickname}` → `{ok, nickname}`;400:少于 2 字符 / 违规词 |
| POST | `/api/auth/logout` | `{ok: true}` |

**收藏夹**(对象结构见 8):

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/me/collections` | 列表(第一个 position 最小者为**默认收藏夹**) |
| POST | `/api/me/collections` | body `{name, description?}` → `201` Collection;409 达上限(maxPerUser);400 空名/违规词 |
| GET | `/api/me/collections/:cid?sort=position\|title\|artist\|addedAt&order=asc\|desc` | `{collection, items}` |
| PATCH | `/api/me/collections/:cid` | body `{name?, description?, position?}` → Collection。**分享开关不要走这里**,用下面 /share |
| DELETE | `/api/me/collections/:cid` | `{ok}`;403 默认收藏夹不允许删除 |
| GET | `/api/me/favorites/status?stationId=&trackId=` | 快捷收藏状态:`{favorited, itemId, collectionId, collections: [{collectionId, name, favorited, itemId}]}`(favorited 看默认收藏夹) |
| POST | `/api/me/collections/:cid/items` | body `{stationId, trackId}` → `201` Item;409 已在夹内 / 达条目上限;404 曲目不在电台曲库 |
| DELETE | `/api/me/collections/:cid/items/:itemId` | `{ok}` |
| POST | `/api/me/collections/:cid/items/reorder` | body `{itemIds: [...]}`(必须**恰好**为该夹全部 item 的新顺序)→ `{items}` |
| GET | `/api/me/collections/:cid/export?format=json\|m3u\|csv` | 附件下载(m3u 内含 `#THMR:sid:tid` 行) |
| POST | `/api/me/collections/:cid/share` | body `{enabled: true\|false}` → `{ok, share}`;开启(或重复开启)时续期 TTL(默认 14 天) |
| GET | `/api/collections/:slug` | **公开**。分享内容 `{collection: {name, description, owner, itemCount, ...}, items}`;404 不存在;**410 分享已过期** |
| GET | `/api/tracks/search?stationId=&q=&page=&pageSize=20\|50\|100\|200&sort=title\|artist\|path\|duration-desc\|duration-asc` | 曲库搜索(代理 Radio 后端)→ `{stationId, page, pageSize, totalPages, totalTracks, filteredCount, tracks}`;track 结构同 `toApiV1Track`:`{trackId, title, artist, album, relativePath, durationSec, coverUrl(绝对)}` |

**投票:**

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/vote/status?stationId=` | 公开(未登录 `myVote:false`)。`{stationId, active, listeners, current?, round?, myVote}`;`round = {votes, threshold, actionTaken}`;`active:false` 时只有 `reason` |
| POST | `/api/vote` | body `{stationId}` → `{voted: true, alreadyVoted, votes, threshold, actionTaken, skipTriggered, skippedTrack?, current}` |
| DELETE | `/api/vote?stationId=` | 取消本次投票 → `{ok, removed, votes, threshold, actionTaken}` |

投票说明:`current.trackId + startedAtMs` 唯一确定一轮(round);换曲后自动开启新一轮,票数清零。`votes >= threshold` 时后端向 Radio 请求切歌(`skipTriggered: true`),前端 UI 应即时反映「已达阈值、切歌中/已切」。

### 7.3 曲目反馈

```
POST /api/stations/:sid/feedback
Body: {
  "type": "metadata",
  "contact": "邮箱 / QQ 等联系方式(必填,≤200)",
  "message": "补充说明(可选,≤1000)",
  "track": { "trackId": "...", "title": "...", "artist": "..." },  // 建议传当前曲目
  "pageUrl": ""                                                     // App 留空即可
}
→ 201: { ok, feedbackId, submittedAtMs, trackMatchesCurrent, feedbackCountForTrack,
          autoSkipThreshold, autoSkipRequested, autoSkipped }
```

`type` 枚举(`src/radio-service.js`):

| 值 | 含义 |
| --- | --- |
| `non-touhou` | 非东方歌曲 |
| `non-music` | 非音乐节目 |
| `copyright` | 版权投诉 |
| `copyright-takedown` | 下架请求 |
| `copyright-attribution` | 版权信息错误 |
| `copyright-permission` | 授权 / 来源补充 |
| `violation` | 违规反馈 |
| `metadata` | 曲目信息错误 |
| `playback` | 播放异常 |
| `other` | 其他 |

错误:`400`(type/contact 缺失)、`403 invalid stream token`(streamAuth 开启时必须带 token)、`409 no current track`。
注意响应里的 `autoSkipped`:同一曲目累积反馈达到内部阈值会自动切歌,App 应提示「感谢反馈,已切换曲目」。

---

## 八、Dart 数据模型草案

```dart
class StreamProfile {
  final String id;            // "128k"
  final int bitrateKbps;
  final int sampleRate;
  final int channels;
  final bool enabled;
}

class CurrentTrack {
  final String trackId;
  final String title;
  final String artist;
  final String coverUrl;      // 可能是相对路径 → 统一 absolutize
  final int startedAtMs;
  final int expectedEndMs;
  final int positionSec;
  final int durationSec;
}

class StationStatus {
  final StationInfo station;
  final Totals totals;        // listeners / uniqueIps
  final CurrentTrack? current;
  final CurrentTrack? previous;   // 无 startedAt 等字段,可复用模型置空
  final List<QueueEntry> queue;
  final List<StreamProfile> bitrates => station.bitrates.where(enabled);
}

class Collection {
  final String id;            // 字符串!
  final String name;
  final String description;
  final int position;
  final int itemCount;
  final String? createdAt;    // ISO
  final String? updatedAt;
  final ShareInfo share;      // {enabled, slug, expiresAt, url}
}

class CollectionItem {
  final String id;
  final String stationId;
  final String trackId;
  final int position;
  final String title;
  final String artist;
  final String album;
  final int? durationSec;
  final String coverUrl;      // 账号后端给的是绝对 URL
  final String? addedAt;
}

class VoteStatus {
  final String stationId;
  final bool active;
  final int listeners;
  final CurrentTrack? current;
  final VoteRound? round;     // {votes, threshold, actionTaken}
  final bool myVote;
}
```

字段名与后端 JSON 完全一致(camelCase),`json_serializable` 无需注解重命名。

---

## 九、关键业务流程

### 9.1 收藏 toggle(播放页爱心按钮)

```
进入播放页 / 换曲时:
  GET /api/me/favorites/status?stationId&trackId
  → favorited ? 显示已收藏 : 未收藏
点击:
  未收藏 → POST /api/me/collections/{默认collectionId}/items {stationId, trackId}
  已收藏 → DELETE /api/me/collections/{collectionId}/items/{itemId}
  409 → 提示「已在收藏夹中」;401 → 跳登录
```

### 9.2 查看他人分享

分享出去的**网页链接**是 `https://thmr.yunmoan.cn/share/{slug}`(浏览器可开);App 内直接渲染则调 `GET /api/collections/{slug}`(公开)。分享 URL 里的 slug 与收藏夹 `share.slug` 一致。`410` = 过期,提示重新生成。

### 9.3 启动时序

```
App 启动
 ├─ 读配置 → 拉 Radio /api/stations/{sid}/status(失败进入重连态)
 ├─ 拉 {thmrBaseUrl}/api/meta(拿 vote.threshold、上限,判定登录后可用功能)
 ├─ 有本地 token → GET /api/auth/me(401 则清 token)
 └─ 不自动播放(iOS/Android 首次需用户手势;桌面端可按策略自动起播)
```

---

## 十、App 规划功能(后端未实现,预留)

架构图中的 **评论**、**广场** 属于 App 特色功能,当前两个后端均无对应接口。约定:

- App 侧预留 `social` 功能模块与入口路由,版本检测到接口可用再开放(可调 `GET /api/meta` 的版本号辅助判断);
- 接口设计届时由账号后端新增(如 `/api/social/*`),本文档更新后再对接;
- 在此之前**不要**自行猜测接口实现,避免返工。

---

## 十一、平台适配清单

| 平台 | 要点 |
| --- | --- |
| Android | `INTERNET` 权限;前台服务 `mediaPlayback`;音频聚焦由 `audio_service` 处理;minSdk ≥ 21;全 HTTPS 无需 cleartext 配置 |
| iOS | `UIBackgroundModes: audio`;锁屏 Now Playing;ATS 默认满足(全 HTTPS) |
| Windows 等 | `media_kit` 播放;关闭主窗口 → 最小化托盘继续播放;开机自启可选 |

---

## 十二、建议迭代路线

| 里程碑 | 内容 |
| --- | --- |
| M1 播放器 | 收听 + 状态轮询 + 码率切换 + 后台/通知栏(不登录可用) |
| M2 账号 | WebView 登录 + Bearer 存取 + 昵称门槛 + 我的信息 |
| M3 收藏 | 收藏夹 CRUD + 曲库搜索添加 + 播放页收藏 toggle + 导出 |
| M4 社交 | 投票切歌 + 分享链接生成/查看他人分享 |
| M5 反馈 | 曲目反馈对话框(类型枚举见 7.3) |
| M6 特色 | 评论 / 广场(等后端接口,见第十章) |

---

## 附:与 Web 端行为对齐清单

- 码率选择、音量按 station 隔离持久化;
- `expectedEndMs` 换曲精准刷新;
- 流地址与反馈接口统一携带 `streamToken`(存在时);
- 「默认收藏夹」= 列表第一个(position 最小),不可删除;
- 重复收藏返回 409,前端做幂等提示;
- 投票轮次跟随 `current.trackId + startedAtMs`,换曲自动重置。
