import 'package:collection/collection.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';

/// 设备型号本地通信能力配置
///
/// 根据设备型号判断支持的本地通信通道（BLE / WiFi AP）。
/// 新增型号时只需在 [_capabilities] 映射表中添加条目。
class DeviceLocalCapabilities {
  DeviceLocalCapabilities._();

  /// 设备型号 → 支持的通道列表（精确匹配）
  static const Map<String, List<LocalCommunicationChannel>> _capabilities = {
    'CS-L10-6K2': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
    'CS-INV-A1': [
      LocalCommunicationChannel.wifiAp,
    ],
  };
  
  /// 型号前缀 → 支持的通道列表（精确匹配未命中时兜底）。
  /// 合并自原通道选择页内嵌的重复实现，避免同一设备在不同入口
  /// 得到相反的通道能力结论
  static const Map<String, List<LocalCommunicationChannel>>
      _prefixCapabilities = {
    'INV-6K': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
    'INV-8K': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
    'INV-10K': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
    'CS-6K2': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
    'CS-8K': [
      LocalCommunicationChannel.ble,
      LocalCommunicationChannel.wifiAp,
    ],
  };
  
  /// 获取指定型号支持的本地通信通道
  ///
  /// 匹配优先级：精确型号 → 型号前缀 → 默认 [LocalCommunicationChannel.wifiAp]
  /// （WiFi AP 为所有设备的兜底通道）。
  static List<LocalCommunicationChannel> getSupportedChannels(String model) {
    final normalized = model.trim().toUpperCase();
    final exact = _capabilities.entries
        .where((e) => e.key.toUpperCase() == normalized)
        .map((e) => e.value)
        .firstOrNull;
    if (exact != null) return exact;
    final prefix = _prefixCapabilities.entries
        .where((e) => normalized.startsWith(e.key.toUpperCase()))
        .map((e) => e.value)
        .firstOrNull;
    if (prefix != null) return prefix;
    return const [LocalCommunicationChannel.wifiAp];
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
