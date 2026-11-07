/// 运行配置:与 Web 端 dist/config.js 同值,`--dart-define` 可覆盖。
class AppConfig {
  const AppConfig({
    this.radioBaseUrl = defaultRadioBaseUrl,
    this.thmrBaseUrl = defaultThmrBaseUrl,
    this.stationId = defaultStationId,
    this.streamToken = '',
    this.featuresVote = false,
  });

  static const defaultRadioBaseUrl = 'https://radio.yunmoan.cn';
  static const defaultThmrBaseUrl = 'https://thmr.yunmoan.cn';
  static const defaultStationId = 'touhou';

  /// Radio 流媒体后端(状态 / 流 / 封面 / 反馈)
  final String radioBaseUrl;

  /// THMR 账号后端(登录 / 收藏 / 投票)
  final String thmrBaseUrl;

  /// 频道 ID(Web 端 window.RADIO_PUBLIC_CONFIG.stationId)
  final String stationId;

  /// streamAuth 启用时的访问密钥(与 Web 端 dist/config.js token 同值)
  final String streamToken;

  /// 功能开关:投票切歌(Web 端 features.vote,当前隐藏禁用)
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
  featuresVote: bool.fromEnvironment('THMR_FEATURE_VOTE'),
);

/// 分享落地页(Web 浏览器打开),用于「复制分享链接」。
const shareWebOrigin = 'https://thmr.yunmoan.cn';
