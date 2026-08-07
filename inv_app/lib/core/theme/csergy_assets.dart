import 'package:flutter/material.dart';

class CsergyNavAsset {
  final String normalAsset;
  final String activeAsset;
  final IconData normalFallbackIcon;
  final IconData activeFallbackIcon;

  const CsergyNavAsset({
    required this.normalAsset,
    required this.activeAsset,
    required this.normalFallbackIcon,
    required this.activeFallbackIcon,
  });
}

abstract final class CsergyAssets {
  static const String iconDirectory = 'assets/icons/csergy';
  static const double navigationIconSize = 24;

  // ============ 小烁角色动作（透明底 WebP） ============
  static const String characterDirectory = 'assets/character/xiaoshuo';
  /// 欢迎/挥手（开屏、登录、首页）
  static const String xiaoshuoWelcome = '$characterDirectory/xiaoshuo_welcome_1024.webp';
  /// 展示光伏模型（电站、新建电站）
  static const String xiaoshuoStation = '$characterDirectory/xiaoshuo_station_1024.webp';
  /// 展示设备（设备列表、设备详情）
  static const String xiaoshuoDevice = '$characterDirectory/xiaoshuo_device_1024.webp';
  /// 离线/断线
  static const String xiaoshuoOffline = '$characterDirectory/xiaoshuo_offline_1024.webp';
  /// 成功
  static const String xiaoshuoSuccess = '$characterDirectory/xiaoshuo_success_1024.webp';
  /// 警告/失败
  static const String xiaoshuoWarning = '$characterDirectory/xiaoshuo_warning_1024.webp';
  /// 空状态
  static const String xiaoshuoEmpty = '$characterDirectory/xiaoshuo_empty_1024.webp';
  /// 提醒
  static const String xiaoshuoReminder = '$characterDirectory/xiaoshuo_reminder_1024.webp';
  /// WiFi 配网引导（横版 1536x1024）
  static const String xiaoshuoWifiGuide = '$characterDirectory/xiaoshuo_wifi_1536x1024.webp';
  /// OTA 升级引导（横版 1536x1024）
  static const String xiaoshuoOtaGuide = '$characterDirectory/xiaoshuo_ota_1536x1024.webp';

  // ============ 空状态插画 ============
  static const String illustrationDirectory = 'assets/illustrations/states';
  static const String emptyStation = '$illustrationDirectory/empty_station_720.webp';
  static const String emptyDevice = '$illustrationDirectory/empty_device_720.webp';
  static const String emptyAlarm = '$illustrationDirectory/empty_alarm_720.webp';
  static const String emptyRecord = '$illustrationDirectory/empty_record_720.webp';

  // ============ 页面背景（WebP，控制包体积） ============
  static const String bgAuth = 'assets/images/backgrounds/bg_auth_abstract.webp';
  static const String bgSplash = 'assets/images/backgrounds/bg_splash_xiaoshuo.webp';
  static const String bgJverify = 'assets/images/backgrounds/bg_jverify_xiaoshuo.webp';

  // ============ 产品图 ============
  static const String productDirectory = 'assets/products';
  static const String inverterMaster = '$productDirectory/csergy_inverter_product_master_2048.png';
  static const String inverterCard = '$productDirectory/csergy_inverter_product_card_800.webp';

  // ============ 品牌与头像 ============
  static const String brandShowcase = 'assets/brand/brand_showcase_1600x900.webp';
  static const String avatarDefault = 'assets/images/avatar_default_512.webp';

  static const CsergyNavAsset home = CsergyNavAsset(
    normalAsset: '$iconDirectory/nav_home_normal.svg',
    activeAsset: '$iconDirectory/nav_home_active.svg',
    normalFallbackIcon: Icons.home_outlined,
    activeFallbackIcon: Icons.home,
  );

  static const CsergyNavAsset statistics = CsergyNavAsset(
    normalAsset: '$iconDirectory/nav_statistics_normal.svg',
    activeAsset: '$iconDirectory/nav_statistics_active.svg',
    normalFallbackIcon: Icons.insights_outlined,
    activeFallbackIcon: Icons.insights,
  );

  static const CsergyNavAsset devices = CsergyNavAsset(
    normalAsset: '$iconDirectory/nav_devices_normal.svg',
    activeAsset: '$iconDirectory/nav_devices_active.svg',
    normalFallbackIcon: Icons.devices_other_outlined,
    activeFallbackIcon: Icons.devices_other,
  );

  static const CsergyNavAsset alarms = CsergyNavAsset(
    normalAsset: '$iconDirectory/nav_alarms_normal.svg',
    activeAsset: '$iconDirectory/nav_alarms_active.svg',
    normalFallbackIcon: Icons.notifications_none,
    activeFallbackIcon: Icons.notifications,
  );

  static const CsergyNavAsset profile = CsergyNavAsset(
    normalAsset: '$iconDirectory/nav_profile_normal.svg',
    activeAsset: '$iconDirectory/nav_profile_active.svg',
    normalFallbackIcon: Icons.person_outline,
    activeFallbackIcon: Icons.person,
  );
}
