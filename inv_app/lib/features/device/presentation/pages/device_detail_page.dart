import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/widgets/energy_flow_diagram.dart';
import 'package:inv_app/core/widgets/status_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/animated_value.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';

class DeviceDetailPage extends StatelessWidget {
  final InverterRealtime? data;
  final dynamic device;
  final bool isOnline;
  final VoidCallback? onRefresh;
  final VoidCallback? onNavigateControl;
  final VoidCallback? onUnbind;

  const DeviceDetailPage({
    super.key,
    this.data,
    this.device,
    this.isOnline = false,
    this.onRefresh,
    this.onNavigateControl,
    this.onUnbind,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;

    if (d == null) {
      return StyledRefreshIndicator(
        onRefresh: () async => onRefresh?.call(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_download_outlined, size: 56.sp, color: AppColor.outline(context).withValues(alpha: 0.5)),
              SizedBox(height: 16.h),
              Text('等待实时数据...', style: TextStyle(fontSize: 16.sp, color: AppColor.outline(context))),
              SizedBox(height: 8.h),
              Text('通过MQTT接收设备数据中', style: TextStyle(fontSize: 13.sp, color: AppColor.outline(context).withValues(alpha: 0.7))),
            ],
          ),
        ),
      );
    }

    return StyledRefreshIndicator(
      onRefresh: () async => onRefresh?.call(),
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _buildDeviceInfo(context, d),
          SizedBox(height: 16.h),
          _buildEnergyFlow(context, d),
          SizedBox(height: 16.h),
          _buildDataSection(context, d),
          SizedBox(height: 16.h),
          _buildEnergySection(context, d),
          SizedBox(height: 24.h),
          if (onUnbind != null) _buildUnbindButton(context),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo(BuildContext context, InverterRealtime d) {
    final apiModel = device?['model'] as String?;
    final apiRatedPower = device?['rated_power'];
    final apiFirmwareVersion = device?['firmware_version'] as String?;
    final apiHardwareVersion = device?['hardware_version'] as String?;

    final model = apiModel ?? d.deviceInfo?.model ?? '-';
    final ratedPower = apiRatedPower ?? d.deviceInfo?.ratedPower;
    final firmware = apiFirmwareVersion ?? d.deviceInfo?.firmwareArm ?? '-';
    final hardware = apiHardwareVersion ?? '-';
    final batteryType = d.deviceInfo?.batteryType ?? '-';
    final cellCount = d.deviceInfo?.cellCount ?? 0;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.infoCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.solar_power, size: 24.sp, color: AppColors.success),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700, color: AppColor.onSurface(context))),
                    SizedBox(height: 2.h),
                    Text('SN: ${d.deviceSN}', style: TextStyle(fontSize: 12.sp, color: AppColor.outline(context))),
                  ],
                ),
              ),
              StatusIndicator(status: isOnline ? 1 : (d.sysStatus?.faultCode != 0 ? 2 : 0), label: ''),
            ],
          ),
          SizedBox(height: 14.h),
          _infoGrid(context, [
            _infoItem('额定功率', ratedPower != null && (ratedPower is double ? ratedPower > 0 : (ratedPower is int ? ratedPower > 0 : false)) ? '${ratedPower} W' : '-'),
            _infoItem('固件版本', firmware != '0' && firmware != '-' ? firmware : '-'),
            _infoItem('硬件版本', hardware != '0' && hardware != '-' ? hardware : '-'),
            _infoItem('电池类型', batteryType),
            if (cellCount > 0) _infoItem('电芯数量', '$cellCount 串'),
          ]),
        ],
      ),
    );
  }

  Widget _infoGrid(BuildContext context, List<_InfoItem> items) {
    return Wrap(
      spacing: 16.w,
      runSpacing: 8.h,
      children: items.map((item) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 80.w) / 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item.label}  ', style: TextStyle(fontSize: 12.sp, color: AppColor.outline(context))),
              Expanded(child: Text(item.value, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColor.onSurface(context)))),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEnergyFlow(BuildContext context, InverterRealtime d) {
    final pvPower = d.pv?.pvPower ?? 0.0;
    final loadPower = d.ac?.power ?? 0.0;
    final batteryVoltage = d.battery?.voltage ?? 0.0;
    final batteryCurrent = d.battery?.current ?? 0.0;
    final batteryPower = batteryVoltage * batteryCurrent;
    final gridPower = pvPower - batteryPower - loadPower;
    final soc = d.battery?.soc ?? 0.0;

    return EnergyFlowDiagram(
      pvPower: pvPower,
      batteryPower: batteryPower,
      loadPower: loadPower,
      gridPower: gridPower,
      batterySoc: soc,
    );
  }

  /// Unified data card: AC + Battery + PV + System Status in one card.
  Widget _buildDataSection(BuildContext context, InverterRealtime d) {
    final ac = d.ac;
    final batt = d.battery;
    final pv = d.pv;
    final sys = d.sysStatus;

    return Container(
      decoration: AppColor.card(context),
      child: Column(
        children: [
          if (ac != null) ...[
            _sectionHeader(context, '交流输出', Icons.power, AppColors.success),
            _dataGrid(context, [
              _dataItem('电压', '${ac.voltage.toStringAsFixed(1)}V', AppColors.success),
              _dataItem('电流', '${ac.current.toStringAsFixed(2)}A', AppColors.warning),
              _dataItem('有功功率', '${ac.power.toStringAsFixed(0)}W', AppColors.success),
              _dataItem('频率', '${ac.frequency.toStringAsFixed(2)}Hz', AppColors.orange),
              _dataItem('负载率', '${ac.loadPercent.toStringAsFixed(1)}%', AppColors.blue),
            ]),
          ],

          if (batt != null) ...[
            _divider(context),
            _sectionHeader(context, '电池 BMS', Icons.battery_charging_full, AppColors.success),
            _dataGrid(context, [
              _dataItem('SOC', '${batt.soc.toStringAsFixed(1)}%', AppColors.success),
              _dataItem('SOH', '${batt.soh.toStringAsFixed(1)}%', AppColors.teal),
              _dataItem('电压', '${batt.voltage.toStringAsFixed(1)}V', AppColors.blue),
              _dataItem('电流', '${batt.current.toStringAsFixed(2)}A', AppColors.warning),
              _dataItem('充放状态', batt.chargeState, AppColors.teal),
            ]),
          ],

          if (pv != null) ...[
            _divider(context),
            _sectionHeader(context, '光伏 MPPT', Icons.wb_sunny, AppColors.orange, trailing: pv.mpptState),
            _dataGrid(context, [
              _dataItem('PV电压', '${pv.pvVoltage.toStringAsFixed(1)}V', AppColors.orange),
              _dataItem('PV电流', '${pv.pvCurrent.toStringAsFixed(2)}A', AppColors.warning),
              _dataItem('PV功率', '${pv.pvPower.toStringAsFixed(0)}W', AppColors.success),
            ]),
          ],

          if (sys != null) ...[
            _divider(context),
            _sectionHeader(context, '系统状态', Icons.info_outline, AppColors.primary),
            _statusGrid(context, sys),
          ],

          SizedBox(height: 4.h),
        ],
      ),
    );
  }

  Widget _buildEnergySection(BuildContext context, InverterRealtime d) {
    final energy = d.energy;
    if (energy == null) return const SizedBox.shrink();

    return Container(
      decoration: AppColor.card(context),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 8.h),
            child: Row(
              children: [
                Container(
                  width: 28.w,
                  height: 28.w,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.summarize, size: 16.sp, color: AppColors.success),
                ),
                SizedBox(width: 10.w),
                Text('能量统计', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColor.onSurface(context))),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.push('/device/${d.deviceSN}/history'),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.show_chart, size: 14.sp, color: AppColors.primary),
                        SizedBox(width: 3.w),
                        Text('历史曲线', style: TextStyle(fontSize: 11.sp, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _dataGrid(context, [
            _dataItem('日PV发电', '${energy.dailyPV.toStringAsFixed(2)}kWh', AppColors.success),
            _dataItem('总PV发电', '${energy.totalPV.toStringAsFixed(1)}kWh', AppColors.blue),
            _dataItem('运行时', '${energy.runtimeHours}h', AppColors.teal),
          ]),
          SizedBox(height: 4.h),
        ],
      ),
    );
  }

  Widget _buildUnbindButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: OutlinedButton(
        onPressed: onUnbind,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off, size: 20),
            SizedBox(width: 8.w),
            Text('解绑设备', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Shared helper methods ──

  Widget _sectionHeader(BuildContext context, String title, IconData icon, Color color, {String? trailing}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 8.h),
      child: Row(
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 16.sp, color: color),
          ),
          SizedBox(width: 10.w),
          Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColor.onSurface(context))),
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing, style: TextStyle(fontSize: 12.sp, color: AppColor.outline(context))),
          ],
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Divider(height: 1, color: AppColor.outline(context).withValues(alpha: 0.15)),
    );
  }

  Widget _dataGrid(BuildContext context, List<_DataItem> items) {
    final rows = <List<_DataItem>>[];
    for (var i = 0; i < items.length; i += 3) {
      rows.add(items.sublist(i, i + 3 > items.length ? items.length : i + 3));
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  Expanded(
                    child: i < row.length
                        ? _dataCell(context, row[i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _dataCell(BuildContext context, _DataItem item) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedValue(
            value: item.value,
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColor.onSurface(context)),
          ),
          SizedBox(height: 1.h),
          Text(item.label, style: TextStyle(fontSize: 10.sp, color: AppColor.outline(context))),
        ],
      ),
    );
  }

  Widget _statusGrid(BuildContext context, SystemStatus sysStatus) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statusCell(context, '运行状态', sysStatus.state, AppColors.success)),
              SizedBox(width: 8.w),
              Expanded(child: _statusCell(context, '故障码', '${sysStatus.faultCode}', sysStatus.faultCode != 0 ? AppColors.error : AppColors.success)),
              SizedBox(width: 8.w),
              Expanded(child: _statusCell(context, '告警码', '${sysStatus.alarmCode}', sysStatus.alarmCode != 0 ? AppColors.warning : AppColors.success)),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(child: _statusCell(context, '效率', '${sysStatus.efficiency.toStringAsFixed(1)}%', AppColors.blue)),
              SizedBox(width: 8.w),
              Expanded(child: _statusCell(context, '逆变温度', '${sysStatus.tempInv.toStringAsFixed(1)}°C', AppColors.warning)),
              SizedBox(width: 8.w),
              Expanded(child: _statusCell(context, 'MOS温度', '${sysStatus.tempMos.toStringAsFixed(1)}°C', AppColors.errorLight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCell(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        children: [
          AnimatedValue(value: value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: color)),
          SizedBox(height: 2.h),
          Text(label, style: TextStyle(fontSize: 10.sp, color: AppColor.outline(context))),
        ],
      ),
    );
  }

  _DataItem _dataItem(String label, String value, Color color) => _DataItem(label, value, color);
  _InfoItem _infoItem(String label, String value) => _InfoItem(label, value);
}

class _DataItem {
  final String label;
  final String value;
  final Color color;
  _DataItem(this.label, this.value, this.color);
}

class _InfoItem {
  final String label;
  final String value;
  _InfoItem(this.label, this.value);
}
