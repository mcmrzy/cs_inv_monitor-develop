class AppConfig {
  static const String appName = '光伏逆变器';
  static const String version = '1.0.0';
  
  static const String apiBaseUrl = 'http://192.168.8.248:8080/api/v1';
  static const String mqttBrokerHost = 'jiuxiaoyw.online';
  static const int mqttBrokerPort = 8883;
  
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
