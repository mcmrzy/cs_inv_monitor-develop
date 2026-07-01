/// OTA 相关异常类型定义
class DeviceConnectionException implements Exception {
  final String message;
  DeviceConnectionException(this.message);
  @override
  String toString() => message;
}
