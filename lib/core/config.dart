/// 客户端运行配置。appConfig 的默认值可通过 `--dart-define` 在构建时覆盖。
class AppConfig {
  const AppConfig({
    this.radioBaseUrl = defaultRadioBaseUrl,
    this.thmrBaseUrl = defaultThmrBaseUrl,
    this.stationId = defaultStationId,
    this.streamToken = '',
    this.featuresVote = true,
  });

  static const defaultRadioBaseUrl = 'https://radio.yunmoan.cn';
  static const defaultThmrBaseUrl = 'https://thmr.yunmoan.cn';
  static const defaultStationId = 'touhou';

  /// Radio 流媒体后端(状态 / 流 / 封面 / 反馈)
  final String radioBaseUrl;

  /// THMR 账号后端(登录 / 收藏 / 投票)
  final String thmrBaseUrl;

  /// 未保存频道偏好时使用的默认频道 ID。
  final String stationId;

  /// Radio 后端启用 streamAuth 时使用的访问 token。
  final String streamToken;

  /// 本地投票开关，开启时仍需 Web 端 features.vote 允许。
  final bool featuresVote;

  AppConfig copyWith({
    String? radioBaseUrl,
    String? thmrBaseUrl,
    String? stationId,
    String? streamToken,
    bool? featuresVote,
  }) =>
      AppConfig(
        radioBaseUrl: radioBaseUrl ?? this.radioBaseUrl,
        thmrBaseUrl: thmrBaseUrl ?? this.thmrBaseUrl,
        stationId: stationId ?? this.stationId,
        streamToken: streamToken ?? this.streamToken,
        featuresVote: featuresVote ?? this.featuresVote,
      );
}

const appConfig = AppConfig(
  radioBaseUrl: String.fromEnvironment(
    'THMR_RADIO_BASE_URL',
    defaultValue: AppConfig.defaultRadioBaseUrl,
  ),
  thmrBaseUrl: String.fromEnvironment(
    'THMR_BASE_URL',
    defaultValue: AppConfig.defaultThmrBaseUrl,
  ),
  stationId: String.fromEnvironment(
    'THMR_STATION_ID',
    defaultValue: AppConfig.defaultStationId,
  ),
  streamToken: String.fromEnvironment('THMR_STREAM_TOKEN'),
  featuresVote: bool.fromEnvironment('THMR_FEATURE_VOTE', defaultValue: true),
);

/// 分享落地页(Web 浏览器打开),用于「复制分享链接」。
const shareWebOrigin = 'https://thmr.yunmoan.cn';
