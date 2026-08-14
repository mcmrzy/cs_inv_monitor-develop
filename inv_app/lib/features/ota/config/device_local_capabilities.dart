import 'package:inv_app/features/ota/domain/entities/local_channel.dart';

/// 设备型号本地通信能力配置
///
/// 根据设备型号判断支持的本地通信通道（BLE / WiFi AP）。
/// 新增型号时只需在 [_capabilities] 映射表中添加条目。
class DeviceLocalCapabilities {
  DeviceLocalCapabilities._();

  /// 设备型号 → 支持的通道列表
  static const Map<String, List<LocalCommunicationChannel>> _capabilities = {
    'CS-L10-6K2': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
    'CS-INV-A1': [
      LocalCommunicationChannel.wifiAp,
    ],
  };

  /// 获取指定型号支持的本地通信通道
  ///
  /// 若型号未配置，返回仅包含 [LocalCommunicationChannel.wifiAp] 的默认列表
  /// （WiFi AP 为所有设备的兜底通道）。
  static List<LocalCommunicationChannel> getSupportedChannels(String model) {
    final normalized = model.trim().toUpperCase();
    return _capabilities.entries
        .firstWhere(
          (e) => e.key.toUpperCase() == normalized,
          orElse: () => MapEntry(model, const [LocalCommunicationChannel.wifiAp]),
        )
        .value;
  }

  /// 判断指定型号是否支持 BLE
  static bool supportsBle(String model) {
    return getSupportedChannels(model).contains(LocalCommunicationChannel.ble);
  }

  /// 判断指定型号是否支持 WiFi AP
  static bool supportsWifiAp(String model) {
    return getSupportedChannels(model).contains(LocalCommunicationChannel.wifiAp);
  }
}
