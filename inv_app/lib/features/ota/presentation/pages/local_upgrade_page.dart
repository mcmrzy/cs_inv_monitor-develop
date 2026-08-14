import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/ota/config/device_local_capabilities.dart';
import 'package:inv_app/features/ota/domain/entities/local_channel.dart';
import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 本地升级双 Tab 页（需求 16：OTA 四卡片 Hub 的"本地升级"入口）
///
/// 通过 [DefaultTabController] 提供左右两个通道：
/// - 左 BLE：BLE 广播扫描 → 连接 → 选本地适配固件 → 升级；
/// - 右 AP：WiFi 热点直连上传。
/// 底层复用 [LocalOTAPage] 的完整升级执行逻辑（选固件→连接→推送→升级），
/// 仅按设备能力（[DeviceLocalCapabilities.supportsBle]）过滤可用通道：
/// 不支持 BLE 的型号只展示 WiFi 热点单 Tab。
class LocalUpgradePage extends StatelessWidget {
  /// 设备序列号
  final String deviceSN;

  /// 设备型号（用于能力判定）
  final String deviceModel;

  const LocalUpgradePage({
    super.key,
    required this.deviceSN,
    required this.deviceModel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final supportsBle = DeviceLocalCapabilities.supportsBle(deviceModel);

    return DefaultTabController(
      length: supportsBle ? 2 : 1,
      child: Scaffold(
        backgroundColor: AppColor.surface(context),
        appBar: AppBar(
          title: Text(
            l10n.str('ota_local_upgrade'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: AppColor.surfaceContainer(context),
          foregroundColor: AppColor.textPrimary(context),
          bottom: TabBar(
            tabs: [
              if (supportsBle)
                Tab(
                  text: l10n.str('local_upgrade_tab_ble'),
                  icon: const Icon(Icons.bluetooth_rounded, size: 20),
                  height: 52.h,
                ),
              Tab(
                text: l10n.str('local_upgrade_tab_ap'),
                icon: const Icon(Icons.wifi_rounded, size: 20),
                height: 52.h,
              ),
            ],
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColor.textSecondary(context),
            indicatorColor: AppColors.primary,
          ),
        ),
        body: TabBarView(
          children: [
            if (supportsBle)
              LocalOTAPage(
                deviceSN: deviceSN,
                deviceIP: '192.168.4.1',
                channel: LocalCommunicationChannel.ble,
                embedded: true,
              ),
            LocalOTAPage(
              deviceSN: deviceSN,
              deviceIP: '192.168.4.1',
              channel: LocalCommunicationChannel.wifiAp,
              embedded: true,
            ),
          ],
        ),
      ),
    );
  }
}
