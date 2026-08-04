/// 代理设置子配置
/// 从 AppSettings 拆分，独立管理网络代理配置
library;

class ProxySettings {
  final bool proxyEnabled;
  final String proxyHost;
  final int proxyPort;
  final String proxyUsername;
  final String proxyPassword;
  final bool proxyApplyToAi;

  const ProxySettings({
    this.proxyEnabled = false,
    this.proxyHost = '',
    this.proxyPort = 1080,
    this.proxyUsername = '',
    this.proxyPassword = '',
    this.proxyApplyToAi = false,
  });

  ProxySettings copyWith({
    bool? proxyEnabled,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    bool? proxyApplyToAi,
  }) {
    return ProxySettings(
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      proxyUsername: proxyUsername ?? this.proxyUsername,
      proxyPassword: proxyPassword ?? this.proxyPassword,
      proxyApplyToAi: proxyApplyToAi ?? this.proxyApplyToAi,
    );
  }

  Map<String, dynamic> toJson() => {
        'proxyEnabled': proxyEnabled,
        'proxyHost': proxyHost,
        'proxyPort': proxyPort,
        'proxyUsername': proxyUsername,
        'proxyPassword': proxyPassword,
        'proxyApplyToAi': proxyApplyToAi,
      };

  factory ProxySettings.fromJson(Map<String, dynamic> j) => ProxySettings(
        proxyEnabled: j['proxyEnabled'] == true,
        proxyHost: j['proxyHost']?.toString() ?? '',
        proxyPort: (j['proxyPort'] as num?)?.toInt() ?? 1080,
        proxyUsername: j['proxyUsername']?.toString() ?? '',
        proxyPassword: j['proxyPassword']?.toString() ?? '',
        proxyApplyToAi: j['proxyApplyToAi'] == true,
      );
}