import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/ota/config/device_local_capabilities.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 本地OTA升级通道类型
enum LocalOTAChannel {
  /// WiFi直连（设备热点模式）
  wifi,

  /// 蓝牙低功耗
  ble,
}

/// 本地OTA通道选择页面
///
/// 让用户选择使用WiFi直连还是BLE进行本地固件升级。
/// - WiFi直连：所有设备均支持，通过设备热点传输固件
/// - BLE：仅部分新型号设备支持，通过蓝牙低功耗传输固件
class LocalOTAChannelSelectPage extends StatelessWidget {
  /// 设备序列号
  final String deviceSN;

  /// 设备型号（如 INV-5000、CS-6K2）
  final String deviceModel;

  /// 当前固件版本
  final String currentFirmwareVersion;

  const LocalOTAChannelSelectPage({
    super.key,
    required this.deviceSN,
    required this.deviceModel,
    required this.currentFirmwareVersion,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final supportsBle = DeviceLocalCapabilities.supportsBle(deviceModel);

    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.str('local_ota_channel_select_title'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 设备信息卡片
              _buildDeviceInfoCard(context),
              SizedBox(height: 24.h),

              // 通道选择标题
              Text(
                l10n.str('select_upgrade_channel'),
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                l10n.str('select_upgrade_channel_hint'),
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
              SizedBox(height: 16.h),

              // WiFi直连选项（所有设备支持）
              _ChannelOptionCard(
                icon: Icons.wifi_rounded,
                iconColor: AppColors.primary,
                iconBackgroundColor: AppColor.primarySoft(context),
                title: l10n.str('channel_wifi_direct'),
                subtitle: l10n.str('channel_wifi_direct_desc'),
                isRecommended: true,
                onTap: () => _navigateToLocalOTA(context, LocalOTAChannel.wifi),
              ),
              SizedBox(height: 12.h),

              // BLE选项（仅支持BLE的设备显示）
              if (supportsBle) ...[
                _ChannelOptionCard(
                  icon: Icons.bluetooth_rounded,
                  iconColor: AppColors.indigo,
                  iconBackgroundColor:
                      AppColors.indigo.withValues(alpha: 0.1),
                  title: l10n.str('channel_ble'),
                  subtitle: l10n.str('channel_ble_desc'),
                  isRecommended: false,
                  onTap: () =>
                      _navigateToLocalOTA(context, LocalOTAChannel.ble),
                ),
                SizedBox(height: 12.h),
              ],

              SizedBox(height: 24.h),

              // 兼容性提示
              _buildCompatibilityHint(context, supportsBle),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建设备信息卡片
  Widget _buildDeviceInfoCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              Icons.devices_rounded,
              size: 22.sp,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.currentDevice,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  deviceSN,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textSecondary(context),
                    fontFamily: 'monospace',
                  ),
                ),
                if (deviceModel.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.surfaceHover(context),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          deviceModel,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColor.textSecondary(context),
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'v$currentFirmwareVersion',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建兼容性提示信息
  Widget _buildCompatibilityHint(BuildContext context, bool supportsBle) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceHover(context),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColor.border(context),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16.sp,
                color: AppColor.textSecondary(context),
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('compatibility_info'),
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _buildHintItem(
            context,
            icon: Icons.wifi_rounded,
            text: l10n.str('wifi_direct_hint'),
          ),
          if (supportsBle) ...[
            SizedBox(height: 6.h),
            _buildHintItem(
              context,
              icon: Icons.bluetooth_rounded,
              text: l10n.str('ble_hint'),
            ),
          ] else ...[
            SizedBox(height: 6.h),
            _buildHintItem(
              context,
              icon: Icons.bluetooth_disabled_rounded,
              text: l10n.str('ble_not_supported_hint'),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建提示项
  Widget _buildHintItem(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 14.sp,
          color: AppColor.textHint(context),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textSecondary(context),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  /// 跳转到本地OTA页面
  void _navigateToLocalOTA(BuildContext context, LocalOTAChannel channel) {
    // 构建查询参数，传递通道类型
    final queryParams = <String, String>{
      'sn': deviceSN,
      'ip': '192.168.4.1', // 默认设备热点IP
      'channel': channel == LocalOTAChannel.wifi ? 'wifi' : 'ble',
    };

    final uri = Uri(
      path: '/ota/$deviceSN/local',
      queryParameters: queryParams,
    );

    context.push(uri.toString());
  }
}

/// 通道选项卡片组件
///
/// 显示可选的升级通道，包含图标、标题、副标题和推荐标签。
class _ChannelOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final String subtitle;
  final bool isRecommended;
  final VoidCallback onTap;

  const _ChannelOptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.title,
    required this.subtitle,
    required this.isRecommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: AppColor.surfaceContainer(context),
            borderRadius: BorderRadius.circular(14.r),
            border: isRecommended
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  )
                : Border.all(
                    color: AppColor.border(context),
                    width: 0.5,
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 通道图标
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  icon,
                  size: 24.sp,
                  color: iconColor,
                ),
              ),
              SizedBox(width: 14.w),

              // 标题和副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColor.textPrimary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isRecommended) ...[
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              l10n.str('recommended'),
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textSecondary(context),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),

              // 箭头图标
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16.sp,
                color: AppColor.textHint(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}