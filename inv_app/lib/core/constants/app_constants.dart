class AppConstants {
  static const String appName = 'PV Inverter';
  static const String appVersion = '1.0.0';

  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;

  static const int dataRefreshInterval = 3000;

  static const int maxRetryCount = 3;

  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'HH:mm:ss';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';

  static const List<String> runModes = [
    'Grid-Tied',
    'Off-Grid',
    'Standby',
    'Fault',
  ];
  static const List<String> alarmLevels = ['Info', 'Warning', 'Severe'];

  static const Map<String, String> faultCodes = {
    'E001': 'Grid Overvoltage',
    'E002': 'Grid Undervoltage',
    'E003': 'Grid Overfrequency',
    'E004': 'Grid Underfrequency',
    'E005': 'PV Overvoltage',
    'E006': 'PV Undervoltage',
    'E007': 'Battery Overvoltage',
    'E008': 'Battery Undervoltage',
    'E009': 'Over-temperature',
    'E010': 'Communication Fault',
  };
}
