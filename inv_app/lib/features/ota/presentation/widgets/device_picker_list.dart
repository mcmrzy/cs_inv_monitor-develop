import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/ota/config/device_local_capabilities.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// OTA 场景通用设备选择列表（本地升级 / 升级历史共用）
///
/// 展示全部设备：名称、SN、固件版本、在线状态，可选 BLE/WiFi
/// 通道能力徽标；支持搜索；点击回调设备原始 Map。
class DevicePickerList extends StatefulWidget {
  /// 选中设备回调（DeviceBloc 返回的原始设备 Map）
  final void Function(Map<String, dynamic> device) onSelected;

  /// 是否显示本地通道能力徽标（BLE / WiFi）
  final bool showCapabilities;

  /// 顶部提示文案（可空）
  final String? hint;

  const DevicePickerList({
    super.key,
    required this.onSelected,
    this.showCapabilities = false,
    this.hint,
  });

  @override
  State<DevicePickerList> createState() => _DevicePickerListState();
}

class _DevicePickerListState extends State<DevicePickerList> {
  String _query = '';
  DeviceListLoaded? _cached;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(const DeviceListRequested(pageSize: 200));
  }

  String _str(dynamic device, List<String> keys) {
    for (final k in keys) {
      final v = device is Map ? device[k] : null;
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  List<dynamic> _filter(List<dynamic> devices) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return devices;
    return devices.where((d) {
      final sn = _str(d, ['sn', 'device_sn']).toLowerCase();
      final name = _str(d, ['name', 'device_name', 'alias']).toLowerCase();
      return sn.contains(q) || name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<DeviceBloc, DeviceState>(
      builder: (context, state) {
        if (state is DeviceListLoaded) _cached = state;
        final cached = _cached;
        if (cached == null) {
          if (state is DeviceError) {
            return XiaoshuoStatePanel(
              asset: CsergyAssets.xiaoshuoOffline,
              title: l10n.translateError(state.message),
              message: l10n.loadFailed,
              size: 160,
              action: OutlinedButton(
                onPressed: () => context
                    .read<DeviceBloc>()
                    .add(const DeviceListRequested(pageSize: 200)),
                child: Text(l10n.retry),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        if (cached.devices.isEmpty) {
          return XiaoshuoStatePanel(
            asset: CsergyAssets.emptyDevice,
            title: l10n.str('ota_picker_empty'),
            size: 160,
          );
        }
        final devices = _filter(cached.devices);
        final hasHint = widget.hint != null;
        final leadingItemCount = hasHint ? 2 : 1;
        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
          itemCount: leadingItemCount +
              (devices.isEmpty ? 1 : devices.length),
          itemBuilder: (context, index) {
            if (index == 0) {
              return DeviceSearchBar(
                onSearchChanged: (v) => setState(() => _query = v),
              );
            }
            if (hasHint && index == 1) {
              return Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Text(
                  widget.hint!,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              );
            }
            if (devices.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 32.h),
                child: Center(
                  child: Text(
                    l10n.noSearchResults,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ),
              );
            }
            return _buildRow(devices[index - leadingItemCount], l10n);
          },
        );
      },
    );
  }

  Widget _buildRow(dynamic device, AppLocalizations l10n) {
    final sn = _str(device, ['sn', 'device_sn']);
    final name = _str(device, ['name', 'device_name', 'alias']);
    final model = _str(device, ['model', 'device_model']);
    final firmware = _str(device, ['firmware_version', 'fw_version']);
    final status = device is Map ? (device['status'] ?? 0) : 0;
    final isOnline = status == 1 || status == 2;
    final supportsBle = DeviceLocalCapabilities.supportsBle(model);
    final supportsWifi = DeviceLocalCapabilities.supportsWifiAp(model);

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: InkWell(
        onTap: device is Map
            ? () => widget.onSelected(Map<String, dynamic>.from(device))
            : null,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          child: Row(
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline
                      ? AppColors.success
                      : AppColor.textHint(context),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? sn : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '$sn${firmware.isEmpty ? '' : ' · $firmware'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                    if (widget.showCapabilities &&
                        (supportsBle || supportsWifi)) ...[
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          if (supportsBle) _capBadge('BLE', AppColors.blue),
                          if (supportsBle && supportsWifi)
                            SizedBox(width: 6.w),
                          if (supportsWifi)
                            _capBadge('WiFi', AppColors.success),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18.sp,
                color: AppColor.textHint(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capBadge(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
