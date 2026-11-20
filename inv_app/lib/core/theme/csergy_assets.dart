abstract final class CsergyAssets {
  static const String inverterThumbnail =
      'assets/images/inverter_thumbnail.png';

  // ============ 小烁角色动作（透明底 PNG） ============
  static const String characterDirectory = 'assets/character/xiaoshuo';

  /// 欢迎/挥手（开屏、登录、首页）
  static const String xiaoshuoWelcome =
      '$characterDirectory/xiaoshuo_welcome_1024.png';

  /// 展示光伏模型（电站、新建电站）
  static const String xiaoshuoStation =
      '$characterDirectory/xiaoshuo_station_1024.png';

  /// 展示设备（设备列表、设备详情）
  static const String xiaoshuoDevice =
      '$characterDirectory/xiaoshuo_device_1024.png';

  /// 离线/断线
  static const String xiaoshuoOffline =
      '$characterDirectory/xiaoshuo_offline_1024.png';

  /// 成功
  static const String xiaoshuoSuccess =
      '$characterDirectory/xiaoshuo_success_1024.png';

  /// 警告/失败
  static const String xiaoshuoWarning =
      '$characterDirectory/xiaoshuo_warning_1024.png';

  /// 空状态
  static const String xiaoshuoEmpty =
      '$characterDirectory/xiaoshuo_empty_1024.png';

  /// 提醒
  static const String xiaoshuoReminder =
      '$characterDirectory/xiaoshuo_reminder_1024.png';

  /// WiFi 配网引导（横版 1536x1024）
  static const String xiaoshuoWifiGuide =
      '$characterDirectory/xiaoshuo_wifi_1536x1024.png';

  /// OTA 升级引导（横版 1536x1024）
  static const String xiaoshuoOtaGuide =
      '$characterDirectory/xiaoshuo_ota_1536x1024.png';

  // ============ 空状态插画 ============
  static const String emptyStation = xiaoshuoStation;
  static const String emptyDevice = xiaoshuoDevice;
  static const String emptyAlarm = xiaoshuoSuccess;
  static const String emptyRecord = xiaoshuoEmpty;

  // ============ 页面背景（WebP，控制包体积） ============
  /// 登录页背景：品牌深蓝渐变 + 抽象光伏/能量元素（上部深色放品牌区，下部浅色放表单）
  static const String bgAuth =
      'assets/images/backgrounds/bg_auth_abstract.webp';
  static const String bgSplash =
      'assets/images/backgrounds/bg_splash_xiaoshuo.webp';

  /// 一键登录页背景：深蓝科技网格 + 能量粒子（底部浅色区放操作按钮）
  static const String bgJverify =
      'assets/images/backgrounds/bg_jverify_abstract.webp';

  // ============ 品牌与头像 ============
  static const String avatarDefault = 'assets/images/avatar_default.png';

  /// 电站默认图片（无图时占位，与 home_page 电站卡片一致）
  static const String stationDefaultImage = 'assets/images/solar_panel.png';
}
