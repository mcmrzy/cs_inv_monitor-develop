/// OTA 相关异常类型定义
class DeviceConnectionException implements Exception {
  final String message;
  DeviceConnectionException(this.message);
  @override
  String toString() => message;
}

/// 本地固件相关异常
class LocalFirmwareException implements Exception {
  final String message;
  LocalFirmwareException(this.message);
  @override
  String toString() => message;
}
