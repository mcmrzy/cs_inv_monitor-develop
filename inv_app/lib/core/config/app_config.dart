// 环境配置：本地开发时通过 --dart-define=API_BASE_URL 注入开发环境地址
// 模拟器：--dart-define=API_BASE_URL=http://localhost:8888/api/v1 (经 API Gateway)
// 真机：  --dart-define=API_BASE_URL=http://192.168.8.57:8888/api/v1 (电脑局域网 IP，经 API Gateway)
// 生产环境（默认值，无需注入）: https://api.jiuxiaoyw.online/api/v1
//                         --dart-define=FRONTEND_BASE_URL=https://www.jiuxiaoyw.online
class AppConfig {
  static const String appName = '辰烁光伏';
  static const String version = '1.0.0';
  static const int versionCode = 1; // 与 pubspec.yaml 中的 build number 一致

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
