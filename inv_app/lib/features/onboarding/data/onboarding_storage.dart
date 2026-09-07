import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 引导页展示记录：首次安装 + 版本升级后各显示一次。
///
/// 通过 SharedPreferences 存储上次已看过引导页的版本号（key: `onboarding_seen_version`），
/// 与 `pubspec.yaml` / `AppConfig.version` 对比：
/// - 首次安装：key 不存在 → 需要展示；
/// - 版本升级：key 与当前版本不一致 → 需要展示；
/// - 同版本再次启动：key 与当前版本一致 → 不再展示。
class OnboardingStorage {
  /// 存储 key：引导页已看过的版本号（新 key，避免与其他代理冲突）
  static const String keyLastSeenVersion = 'onboarding_seen_version';

  /// 当前版本是否需要展示引导页
  Future<bool> needsOnboarding() async {
    try {
      final storage = getIt<StorageService>();
      final seen = await storage.getString(keyLastSeenVersion);
      return seen != AppConfig.version;
    } catch (_) {
      // 存储异常时保守放行（不阻塞启动流程），下次启动再判断
      return false;
    }
  }

  /// 引导页看完/跳过成功后，记录当前版本，下次启动不再展示
  Future<void> markSeen() async {
    final storage = getIt<StorageService>();
    await storage.saveString(keyLastSeenVersion, AppConfig.version);
  }
}
