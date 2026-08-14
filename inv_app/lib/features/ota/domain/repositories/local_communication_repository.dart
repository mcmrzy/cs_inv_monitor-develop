/// 本地OTA通信接口
/// 定义与设备WiFi AP通信的抽象方法
///
/// 支持 BLE 和 WiFi AP 两种通道（见 [LocalCommunicationChannel]）。
abstract class LocalCommunicationRepository {
  /// 连接设备WiFi热点 (CS-INV-xxxx)
  Future<bool> connectToDevice({
    required String deviceSN,
    required String deviceIP,
    String? password,
  });

  /// 断开WiFi连接，恢复正常网络
  Future<void> disconnect();

  /// 上传固件到设备
  /// HTTP POST 上传固件到 http://{device_ip}:80/ota/upload
  Future<void> uploadFirmware({
    required String deviceIP,
    required String filePath,
    required Map<String, dynamic> manifest,
    void Function(int sent, int total)? onProgress,
  });

  /// 触发升级
  /// 部分设备上传完固件后自动触发，此方法用于手动触发场景
  Future<void> triggerUpgrade(String deviceIP);

  /// GET查询升级进度 /ota/progress
  Future<Map<String, dynamic>> getProgress(String deviceIP);

  /// GET获取设备信息 /ota/info
  Future<Map<String, dynamic>> getDeviceInfo(String deviceIP);

  /// 检测设备连接状态
  Future<bool> testConnection(String deviceIP);

  /// 检查当前是否连接到设备热点
  Future<bool> isConnectedToDeviceAP();

  // ============ 参数读写（本地 HTTP） ============

  /// 读取设备参数
  /// GET http://{deviceIP}/api/params?name={paramName}
  /// 返回参数当前值（字符串形式），失败抛异常
  Future<String> readParameter(String deviceIP, String paramName);

  /// 写入设备参数
  /// POST http://{deviceIP}/api/params
  /// body: {"name": paramName, "value": value}
  /// 返回设备是否确认接受
  Future<bool> writeParameter(String deviceIP, String paramName, String value);

  /// 发送控制命令
  /// POST http://{deviceIP}/api/control
  /// body: {"command": command, "params": params}
  /// 返回设备响应结果
  Future<Map<String, dynamic>> controlDevice(
    String deviceIP,
    String command, {
    Map<String, dynamic>? params,
  });
}

/// 升级进度信息
class UpgradeProgress {
  /// 进度百分比 0-100
  final double progress;

  /// 当前状态，如 uploading / verifying / done / error
  final String status;

  /// 可读的进度描述
  final String message;

  const UpgradeProgress({
    required this.progress,
    required this.status,
    this.message = '',
  });
}

/// 设备基本信息（本地通信获取）
class LocalDeviceInfo {
  /// 设备序列号
  final String sn;

  /// 设备型号，如 CS-L10-6K2
  final String model;

  /// 主固件版本
  final String firmwareVersion;

  /// 各芯片固件版本，如 {"esp": "1.2.0", "arm": "2.0.1"}
  final Map<String, String> chipVersions;

  const LocalDeviceInfo({
    required this.sn,
    required this.model,
    this.firmwareVersion = '',
    this.chipVersions = const {},
  });
}