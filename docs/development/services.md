# 后端接入

[返回开发指南](README.md)

## 服务边界

Radio 流媒体服务提供频道放送状态、直播音频、封面、队列、昨日歌单和反馈。THMR 业务服务提供频道目录、Natayark 登录、收藏、分享、切歌投票和曲库代理。客户端更新是另一条独立链路。 [更新 API 部署](../release/update-api.md)

域名、默认频道和构建开关以 [`AppConfig`](../../lib/core/config.dart) 为准，可通过 Flutter 的 `--dart-define=键=值` 覆盖。

| 定义 | 用途 |
| --- | --- |
| `THMR_RADIO_BASE_URL` | Radio 源 1 的基础地址 |
| `THMR_BASE_URL` | THMR 业务与部署配置地址 |
| `THMR_STATION_ID` | 默认频道 ID |
| `THMR_STREAM_TOKEN` | 电台要求访问密钥时传入，对应 Radio 请求的 `token` 查询参数 |
| `THMR_FEATURE_VOTE` | 客户端投票开关。允许时还需读取部署端 `/config.js` 的 `features.vote`，投票和撤回前会重新检查。 |

Radio 线路与测速策略在 [`radio_sources.dart`](../../lib/core/network/radio_sources.dart) 和 [`radio_source_provider.dart`](../../lib/core/state/radio_source_provider.dart) 中维护。客户端使用选定线路的 Radio 地址加载状态、封面和流。

## 接口与状态入口

| 主题 | 当前实现 |
| --- | --- |
| Radio 请求路径、查询参数、反馈错误 | [`RadioApi`](../../lib/core/api/radio_api.dart) |
| THMR 业务请求、授权头与错误映射 | [`ThmrApi`](../../lib/core/api/thmr_api.dart) |
| JSON 字段、ID 类型、相对封面 URL | [`models.dart`](../../lib/core/models/models.dart) |
| 频道目录与换曲刷新 | [`channel_provider.dart`](../../lib/core/state/channel_provider.dart) · [`station_provider.dart`](../../lib/core/state/station_provider.dart) |
| 播放、暂停、切换码率和重连 | [`playback_controller.dart`](../../lib/core/player/playback_controller.dart) · [`audio_engine.dart`](../../lib/core/player/audio_engine.dart) |
| 登录与会话存储 | [`login_screen.dart`](../../lib/features/account/login_screen.dart) · [`auth_provider.dart`](../../lib/core/state/auth_provider.dart) |
| 收藏、分享和昨日歌单 | [`collections/`](../../lib/features/collections/) · [`collection_cache.dart`](../../lib/core/state/collection_cache.dart) |

## 修改接口时核对的约定

- 放送元数据定时轮询，并按 `expectedEndMs` 安排换曲时的刷新。前台音频播放、系统媒体键和码率切换都通过同一个播放控制器。
- 内嵌登录优先使用回环回调。客户端从 WebView 读取候选 Cookie，逐个向 `/api/auth/me` 验证，接受有效会话后用安全存储持久化，业务请求使用 Bearer。Linux 使用网页版入口。Windows WebView 依赖见 [安装说明](../user/install.md)。
- 收藏列表中位置最靠前的一项用作默认收藏夹，重复收藏按幂等操作处理。昨日歌单保留接口顺序与重复播放，`playedAtMs` 转为北京时间显示，缺失时显示「播放时间未记录」。

联调时优先运行 [API 测试与诊断工具](verification.md)。
