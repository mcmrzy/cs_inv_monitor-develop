import 'dart:convert';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 绑定设备后「设置设备名称」引导的忽略记忆（按 SN 记，一次性）。
///
/// 存 SharedPreferences `device_name_prompt_skipped`（JSON 数组）：
/// - 用户点「暂不设置」后把该 SN 记下，之后不再为这台设备弹引导；
/// - 之后绑定的新设备不受影响，仍会正常引导。
class DeviceNamePromptStorage {
  static const String _keySkipped = 'device_name_prompt_skipped';

  Future<List<String>> _readSkipped() async {
    try {
      final storage = getIt<StorageService>();
      final raw = await storage.getString(_keySkipped);
      if (raw == null || raw.isEmpty) return <String>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded.whereType<String>().toList();
    } catch (_) {
      // 存储异常时按「没忽略过」处理，最多多弹一次，不会漏引导
      return <String>[];
    }
  }

  Future<bool> isSkipped(String sn) async {
    final skipped = await _readSkipped();
    return skipped.contains(sn);
  }

  Future<void> markSkipped(String sn) async {
    try {
      final storage = getIt<StorageService>();
      final skipped = await _readSkipped();
      if (skipped.contains(sn)) return;
      skipped.add(sn);
      await storage.saveString(_keySkipped, jsonEncode(skipped));
    } catch (_) {}
  }
}
