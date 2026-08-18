import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 固件升级中心（功能优先四入口）
///
/// 1. 检查更新 → /ota/check-all（并行检查所有在线设备）
/// 2. 本地升级 → /local-upgrade（双 Tab：BLE/AP 扫描设备）
/// 3. 固件库   → /firmware-library（按型号浏览发布版本，可预下载）
/// 4. 升级历史 → /upgrade-history（全设备统一列表）
class OtaTabPage extends StatelessWidget {
  const OtaTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.otaTitle,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
        children: [
          _ModeCard(
            icon: Icons.cloud_done_rounded,
            iconColor: AppColors.primary,
            title: l10n.str('ota_check_update'),
            subtitle: l10n.str('ota_check_update_hint'),
            onTap: () => context.push('/ota/check-all'),
          ),
          SizedBox(height: 10.h),
          _ModeCard(
            icon: Icons.wifi_rounded,
            iconColor: AppColors.success,
            title: l10n.str('ota_local_upgrade'),
            subtitle: l10n.str('ota_local_upgrade_hint'),
            onTap: () => context.push('/local-upgrade'),
          ),
          SizedBox(height: 10.h),
          _ModeCard(
            icon: Icons.folder_outlined,
            iconColor: AppColors.orange,
            title: l10n.str('ota_firmware_library'),
            subtitle: l10n.str('ota_firmware_library_hint'),
            onTap: () => context.push('/firmware-library'),
          ),
          SizedBox(height: 10.h),
          _ModeCard(
            icon: Icons.history_rounded,
            iconColor: AppColors.purple,
            title: l10n.str('ota_upgrade_history'),
            subtitle: l10n.str('ota_upgrade_history_hint'),
            onTap: () => context.push('/upgrade-history'),
          ),
        ],
      ),
    );
  }
}

/// 升级模式卡片：图标 + 标题 + 副标题
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Icon(icon, size: 24.sp, color: iconColor),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14.sp,
                color: iconColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
