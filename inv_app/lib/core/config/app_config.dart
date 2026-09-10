// 环境配置：本地开发时通过 --dart-define=API_BASE_URL 注入开发环境地址
// 模拟器：--dart-define=API_BASE_URL=http://localhost:8888/api/v1 (经 API Gateway)
// 真机：  --dart-define=API_BASE_URL=http://192.168.8.57:8888/api/v1 (电脑局域网 IP，经 API Gateway)
// 生产环境（默认值，无需注入）: https://api.jiuxiaoyw.online/api/v1
//                         --dart-define=FRONTEND_BASE_URL=https://www.jiuxiaoyw.online
class AppConfig {
  static const String appName = '辰烁光伏';

  /// 版本名（展示用）：发版脚本 build_release.bat 注入
  /// `--dart-define=APP_VERSION_NAME=<pubspec version>`，与 pubspec.yaml 保持一致。
  static const String version = String.fromEnvironment(
    'APP_VERSION_NAME',
    defaultValue: '1.0.0',
  );

  /// 版本号兜底值：更新检查优先读取安装包真实 versionCode（见
  /// AppUpdateService.resolveCurrentVersionCode），仅在读取失败时使用本值。
  /// 发版脚本 build_release.bat 会注入 `--dart-define=APP_VERSION_CODE=<build number>`。
  static const int versionCode = int.fromEnvironment(
    'APP_VERSION_CODE',
    defaultValue: 1,
  );

  // 默认值必须是生产 https 地址：避免构建时漏注入 --dart-define
  // 导致登录密码/JWT 等凭据经明文 HTTP 传输
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.jiuxiaoyw.online/api/v1',
  );

  /// 管理后台（Web）外部访问地址，用于邀请链接等分享场景；
  /// 生产构建时通过 --dart-define=FRONTEND_BASE_URL 注入。
  static const String frontendBaseUrl = String.fromEnvironment(
    'FRONTEND_BASE_URL',
    defaultValue: 'https://www.jiuxiaoyw.online',
  );

  /// 安装包/固件下载受信域名（逗号分隔）：更新包下载走 CDN 域，与 API/前端同属受信来源。
  /// 生产构建可经 `--dart-define=TRUSTED_DOWNLOAD_HOSTS=a.example.com,b.example.com` 覆盖。
  static const String trustedDownloadHosts = String.fromEnvironment(
    'TRUSTED_DOWNLOAD_HOSTS',
    defaultValue: 'download.jiuxiaoyw.online,jiuxiaoyw.online',
  );
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;
  static const int sendTimeout = 30000;

  static const int refreshTokenBeforeExpire = 600;

  static const int maxRetryCount = 3;
  static const int retryDelay = 1000;

  static const int dataRefreshInterval = 3000;
  static const int stationListRefreshInterval = 30000;

  static const List<String> supportedLocales = ['zh', 'en'];
  static const String defaultLocale = 'zh';
}
