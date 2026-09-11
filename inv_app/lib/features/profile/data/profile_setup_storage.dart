import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 「完善个人信息」引导的结束标记（按用户记，一次性）。
///
/// 存 SharedPreferences `profile_setup_done_<userId>`：
/// - 用户点了「跳过」，或保存过一次资料，就置位；
/// - 之后即使昵称仍为空也不再打扰，资料随时可在「我的 → 点击头像」里补。
/// 按用户 id 分开记，避免同一台手机上换账号后互相压制引导。
class ProfileSetupStorage {
  static String _key(int userId) => 'profile_setup_done_$userId';

  Future<bool> isDone(int userId) async {
    try {
      final storage = getIt<StorageService>();
      final value = await storage.getString(_key(userId));
      return value == '1';
    } catch (_) {
      // 存储异常时保守返回已完成，避免每次启动都弹
      return true;
    }
  }

  Future<void> markDone(int userId) async {
    try {
      final storage = getIt<StorageService>();
      await storage.saveString(_key(userId), '1');
    } catch (_) {}
  }
}
