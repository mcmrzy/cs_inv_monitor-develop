import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/ota/config/device_local_capabilities.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class OtaTabPage extends StatefulWidget {
  const OtaTabPage({super.key});

  @override
  State<OtaTabPage> createState() => _OtaTabPageState();
}

class _OtaTabPageState extends State<OtaTabPage> {
  DeviceListLoaded? _cachedState;
  String _searchQuery = '';
  dynamic _selectedDevice;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(const DeviceListRequested(pageSize: 200));
  }

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
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          if (state is DeviceListLoaded) {
            _cachedState = state;
          }

          if (_cachedState != null) {
            return _buildContent(context, _cachedState!, l10n);
          }

          if (state is DeviceError) {
            return XiaoshuoStatePanel(
              asset: CsergyAssets.xiaoshuoOffline,
              title: l10n.translateError(state.message),
              message: l10n.loadFailed,
              size: 176,
              action: OutlinedButton(
                onPressed: () => context
                    .read<DeviceBloc>()
                    .add(const DeviceListRequested(pageSize: 200)),
                child: Text(l10n.retry),
              ),
            );
          }

          return const SkeletonOtaPage();
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    DeviceListLoaded state,
    AppLocalizations l10n,
  ) {
    if (state.devices.isEmpty) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.emptyDevice,
        title: l10n.noUpgradableDevices,
        size: 176,
      );
    }
    final devices = _filterDevices(state.devices);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
      children: [
        _buildLocalModeEntry(context, l10n),
        SizedBox(height: 8.h),
        DeviceSearchBar(
          onSearchChanged: (v) => setState(() {
            _searchQuery = v;
            _selectedDevice = null;
          }),
        ),
        // 设备选择列表（精简显示，选中后折叠）
        if (_selectedDevice == null && devices.isNotEmpty)
          ...devices.take(5).map((d) => _buildDeviceSelectCard(d, l10n)),
        if (_selectedDevice == null && devices.length > 5)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Text(
              l10n.str('ota_more_devices').replaceAll('{count}', '${devices.length}'),
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ),
        if (_selectedDevice == null && devices.isEmpty)
          _buildNoSearchResult(l10n),
        // 已选设备：显示四张功能卡片（检查更新/本地升级/固件列表/升级历史）
        if (_selectedDevice != null) ...[
          _buildSelectedDeviceChip(l10n),
          SizedBox(height: 12.h),
          ..._buildHubCards(l10n),
        ],
      ],
    );
  }

  /// 已选设备标签：点击可取消选择
  Widget _buildSelectedDeviceChip(AppLocalizations l10n) {
    final d = _selectedDevice;
    final sn = (d['sn'] ?? d['device_sn'] ?? '').toString();
    final name = (d['name'] ?? d['device_name'] ?? sn).toString();
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.devices_rounded, size: 18.sp, color: AppColors.primary),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '$name ($sn)',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _selectedDevice = null),
            child: Icon(Icons.close_rounded, size: 18.sp, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  /// 设备选择卡片（精简行）
  Widget _buildDeviceSelectCard(dynamic device, AppLocalizations l10n) {
    final sn = (device['sn'] ?? device['device_sn'] ?? '').toString();
    final name = (device['name'] ?? device['device_name'] ?? sn).toString();
    final status = device['status'] ?? 0;
    final isOnline = status == 1 || status == 2;

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedDevice = device),
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          child: Row(
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? AppColors.success : AppColors.textHint,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      sn,
                      style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18.sp, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  /// 四张升级功能卡片（需求 16 重构）
  ///
  /// 1. 检查更新 → 在线 OTAPage（GET /ota/check/:sn）
  /// 2. 本地升级 → 双 Tab 页（BLE 直连 / WiFi 热点）
  /// 3. 固件列表 → FirmwareListPage（GET /ota/app/packages 按设备过滤）
  /// 4. 升级历史 → UpgradeHistoryPage（GET /ota/devices/:sn/history + 回退）
  List<Widget> _buildHubCards(AppLocalizations l10n) {
    final d = _selectedDevice;
    final sn = (d['sn'] ?? d['device_sn'] ?? '').toString();
    final model = (d['model'] ?? d['device_model'] ?? '').toString();
    final status = d['status'] ?? 0;
    final isOnline = status == 1 || status == 2;
    final supportsWifi = DeviceLocalCapabilities.supportsWifiAp(model);
    final supportsBle = DeviceLocalCapabilities.supportsBle(model);
    final firmwareVersion =
        (d['firmware_version'] ?? d['fw_version'] ?? '').toString();

    return [
      _ModeCard(
        icon: Icons.cloud_done_rounded,
        iconColor: AppColors.primary,
        title: l10n.str('ota_check_update'),
        subtitle: l10n.str('ota_check_update_hint'),
        available: isOnline,
        unavailableHint: l10n.str('ota_device_offline_hint'),
        onTap: () => context.push('/ota/$sn'),
      ),
      SizedBox(height: 10.h),
      _ModeCard(
        icon: Icons.wifi_rounded,
        iconColor: AppColors.success,
        title: l10n.str('ota_local_upgrade'),
        subtitle: l10n.str('ota_local_upgrade_hint'),
        available: supportsWifi || supportsBle,
        unavailableHint: l10n.str('ota_local_upgrade_unavailable'),
        onTap: () => context.push(
          '/local-upgrade?sn=${Uri.encodeComponent(sn)}'
          '&model=${Uri.encodeComponent(model)}',
        ),
      ),
      SizedBox(height: 10.h),
      _ModeCard(
        icon: Icons.folder_outlined,
        iconColor: AppColors.orange,
        title: l10n.str('ota_firmware_library'),
        subtitle: l10n.str('ota_firmware_library_hint'),
        available: true,
        unavailableHint: '',
        onTap: () => context.push(
          '/firmware-list?sn=${Uri.encodeComponent(sn)}'
          '&model=${Uri.encodeComponent(model)}'
          '&version=${Uri.encodeComponent(firmwareVersion)}',
        ),
      ),
      SizedBox(height: 10.h),
      _ModeCard(
        icon: Icons.history_rounded,
        iconColor: AppColors.purple,
        title: l10n.str('ota_upgrade_history'),
        subtitle: l10n.str('ota_upgrade_history_hint'),
        available: true,
        unavailableHint: '',
        onTap: () => context.push(
          '/upgrade-history?sn=${Uri.encodeComponent(sn)}',
        ),
      ),
    ];
  }

  /// 本地离网模式入口横幅
  Widget _buildLocalModeEntry(BuildContext context, AppLocalizations l10n) {
    return Container(
      margin: EdgeInsets.only(bottom: 4.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.blue.withValues(alpha: 0.12),
            AppColors.primary.withValues(alpha: 0.06),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: InkWell(
        onTap: () => context.push('/local-mode'),
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2.h),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  size: 22.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str('local_mode_entry_title'),
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      l10n.str('local_mode_entry_hint'),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14.sp,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<dynamic> _filterDevices(List<dynamic> devices) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return devices;
    return devices.where((d) {
      final sn = (d['sn'] ?? d['device_sn'] ?? '').toString().toLowerCase();
      final name = (d['name'] ?? d['device_name'] ?? '').toString().toLowerCase();
      final alias = (d['alias'] ?? '').toString().toLowerCase();
      return sn.contains(query) || name.contains(query) || alias.contains(query);
    }).toList();
  }

  Widget _buildNoSearchResult(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 56.sp, color: AppColors.textHint),
          SizedBox(height: 12.h),
          Text(
            l10n.noSearchResults,
            style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 升级模式卡片：图标 + 标题 + 通道能力副标题 + 可用状态
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool available;
  final String unavailableHint;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.available,
    required this.unavailableHint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = available ? iconColor : AppColors.textHint;
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        border: available
            ? Border.all(color: iconColor.withValues(alpha: 0.2))
            : null,
      ),
      child: InkWell(
        onTap: available ? onTap : null,
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: displayColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Icon(icon, size: 24.sp, color: displayColor),
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
                        color: available
                            ? AppColor.textPrimary(context)
                            : AppColors.textHint,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      available ? subtitle : unavailableHint,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              if (available)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14.sp,
                  color: iconColor,
                )
              else
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16.sp,
                  color: AppColors.textHint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
