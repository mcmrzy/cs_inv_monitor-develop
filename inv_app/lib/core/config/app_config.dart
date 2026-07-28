// 环境配置：修改 apiBaseUrl 的 defaultValue 切换环境
// 本地开发：http://localhost:8888/api/v1 (模拟器) 或 http://<电脑IP>:8888/api/v1 (真机)
// 生产环境：https://jiuxiaoyw.online/api/v1
class AppConfig {
  static const String appName = '辰烁光伏';
  static const String version = '1.0.0';
  static const int versionCode = 1; // 与 pubspec.yaml 中的 build number 一致

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8888/api/v1',
  );
  static const String mqttBrokerHost = String.fromEnvironment(
    'MQTT_BROKER_HOST',
    defaultValue: 'jiuxiaoyw.online',
  );
  static const int mqttBrokerPort = int.fromEnvironment(
    'MQTT_BROKER_PORT',
    defaultValue: 8883,
  );
  static const String mqttCertificateSha1 = String.fromEnvironment(
    'MQTT_CERT_SHA1',
    defaultValue: '701d2f1ffc5e7ac91232a2c98ac9ee918e0b8245',
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
