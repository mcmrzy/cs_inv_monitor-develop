class AppConstants {
  static const String appName = '光伏逆变器';
  static const String appVersion = '1.0.0';
  
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;
  
  static const int dataRefreshInterval = 3000;
  
  static const int maxRetryCount = 3;
  
  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'HH:mm:ss';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
  
  static const List<String> runModes = ['并网', '离网', '待机', '故障'];
  static const List<String> alarmLevels = ['提示', '警告', '严重'];
  
  static const Map<String, String> faultCodes = {
    'E001': '电网过压',
    'E002': '电网欠压',
    'E003': '电网过频',
    'E004': '电网欠频',
    'E005': '光伏过压',
    'E006': '光伏欠压',
    'E007': '电池过压',
    'E008': '电池欠压',
    'E009': '过温保护',
    'E010': '通信故障',
  };
}
