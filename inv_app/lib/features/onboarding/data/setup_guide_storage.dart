import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 首启快速设置向导完成标记（一次性，不随版本重置）。
///
/// 通过 SharedPreferences 存储 `setup_guide_done`：
/// - 未置位且用户无电站时，首页触发向导；
/// - 完成或跳过后置位，不再打扰。
class SetupGuideStorage {
  static const String _keyDone = 'setup_guide_done';

  Future<bool> isDone() async {
    try {
      final storage = getIt<StorageService>();
      final value = await storage.getString(_keyDone);
      return value == '1';
    } catch (_) {
      // 存储异常时保守返回已完成，避免反复弹出向导
      return true;
    }
  }

  Future<void> markDone() async {
    try {
      final storage = getIt<StorageService>();
      await storage.saveString(_keyDone, '1');
    } catch (_) {}
  }
}
