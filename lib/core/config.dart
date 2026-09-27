/// 运行配置:与 Web 端 dist/config.js 同值,`--dart-define` 可覆盖。
class AppConfig {
  const AppConfig({
    this.radioBaseUrl = 'https://radio.yunmoan.cn',
    this.thmrBaseUrl = 'https://thmr.yunmoan.cn',
    this.stationId = 'touhou',
    this.streamToken = '',
    this.featuresVote = false,
  });

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
        radioBaseUrl: String.fromEnvironment(
          'THMR_RADIO_BASE_URL',
          defaultValue: radioBaseUrl ?? this.radioBaseUrl,
        ),
        thmrBaseUrl: String.fromEnvironment(
          'THMR_BASE_URL',
          defaultValue: thmrBaseUrl ?? this.thmrBaseUrl,
        ),
        stationId: String.fromEnvironment(
          'THMR_STATION_ID',
          defaultValue: stationId ?? this.stationId,
        ),
        streamToken: String.fromEnvironment(
          'THMR_STREAM_TOKEN',
          defaultValue: streamToken ?? this.streamToken,
        ),
        featuresVote: bool.fromEnvironment(
          'THMR_FEATURE_VOTE',
          defaultValue: featuresVote ?? this.featuresVote,
        ),
      );
}

const appConfig = AppConfig();

/// 分享落地页(Web 浏览器打开),用于「复制分享链接」。
const shareWebOrigin = 'https://thmr.yunmoan.cn';
