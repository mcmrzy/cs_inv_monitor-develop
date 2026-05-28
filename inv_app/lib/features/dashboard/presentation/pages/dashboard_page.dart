import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/widgets/power_gauge.dart';
import 'package:inv_app/core/widgets/status_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/animated_value.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';

class DashboardPage extends StatefulWidget {
  final InverterRealtime? data;
  final bool isOnline;
  final VoidCallback? onRefresh;

  const DashboardPage({
    super.key,
    this.data,
    this.isOnline = false,
    this.onRefresh,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _lastUpdate = '';

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _lastUpdate =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    });
  }

  @override
  void didUpdateWidget(DashboardPage old) {
    super.didUpdateWidget(old);
    if (widget.data != old.data) _updateTime();
  }

  @override
  void initState() {
    super.initState();
    _updateTime();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isRunning = data?.sysStatus?.state == 'inverting';
    final hasFault = data?.sysStatus?.faultCode != 0;

    return StyledRefreshIndicator(
      onRefresh: () async => widget.onRefresh?.call(),
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _buildHeader(context, data),
          SizedBox(height: 16.h),
          _buildPowerHero(context, data),
          SizedBox(height: 16.h),
          _buildQuickStats(context, data),
          SizedBox(height: 16.h),
          _buildDataSection(context, data),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, InverterRealtime? data) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CS-I10-6K2',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.w700,
                color: AppColor.onSurface(context),
              ),
            ),
            SizedBox(height: 4.h),
            Row(
              children: [
                StatusIndicator(
                  status: widget.isOnline ? 1 : (data?.sysStatus?.faultCode != 0 ? 2 : 0),
                  label: '',
                ),
                SizedBox(width: 8.w),
                Text(
                  widget.isOnline ? (data?.sysStatus?.state ?? '在线') : '离线',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.onSurfaceVariant(context),
                  ),
                ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '更新 $_lastUpdate',
              style: TextStyle(fontSize: 11.sp, color: AppColor.outline(context)),
            ),
            SizedBox(height: 4.h),
            Text(
              data?.deviceSN ?? '',
              style: TextStyle(fontSize: 12.sp, color: AppColor.outline(context)),
            ),
          ],
        ),
      ],
    );
  }

  /// Hero section with power gauge and gradient background.
  Widget _buildPowerHero(BuildContext context, InverterRealtime? data) {
    final activePower = (data?.ac?.power ?? 0) / 1000.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 24.w, horizontal: 20.w),
      decoration: AppColor.heroCard(context),
      child: Column(
        children: [
          Text(
            '交流输出功率',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          SizedBox(height: 12.h),
          PowerGauge(
            power: activePower,
            maxPower: 6.2,
            size: 180.w,
            textColor: Colors.white,
            subtextColor: Colors.white70,
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  /// Compact quick stats below the hero card.
  Widget _buildQuickStats(BuildContext context, InverterRealtime? data) {
    final loadPercent = data?.ac?.loadPercent ?? 0;
    final frequency = data?.ac?.frequency ?? 0;
    final pf = data?.ac?.pf ?? 0;

    return Row(
      children: [
        _quickStatChip(context, '负载率', '${loadPercent.toStringAsFixed(1)}%', Icons.speed, AppColors.success),
        SizedBox(width: 8.w),
        _quickStatChip(context, '频率', '${frequency.toStringAsFixed(1)}Hz', Icons.electrical_services, AppColors.warning),
        SizedBox(width: 8.w),
        _quickStatChip(context, 'PF', pf.toStringAsFixed(2), Icons.tune, AppColors.blue),
      ],
    );
  }

  Widget _quickStatChip(BuildContext context, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 10.w),
        decoration: AppColor.card(context),
        child: Column(
          children: [
            Icon(icon, size: 18.sp, color: color),
            SizedBox(height: 6.h),
            Text(
              value,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: AppColor.onSurface(context),
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(fontSize: 10.sp, color: AppColor.outline(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// All data sections in a single unified card.
  Widget _buildDataSection(BuildContext context, InverterRealtime? data) {
    final batt = data?.battery;
    final pv = data?.pv;
    final ac = data?.ac;
    final energy = data?.energy;
    final sysStatus = data?.sysStatus;

    return Container(
      decoration: AppColor.card(context),
      child: Column(
        children: [
          // Battery BMS
          if (batt != null) ...[
            _sectionHeader(context, '电池 BMS', Icons.battery_charging_full, AppColors.success),
            _dataGrid(context, [
              _dataItem('SOC', '${batt.soc.toStringAsFixed(1)}%', AppColors.success),
              _dataItem('电压', '${batt.voltage.toStringAsFixed(1)}V', AppColors.blue),
              _dataItem('电流', '${batt.current.toStringAsFixed(2)}A', AppColors.warning),
              _dataItem('SOH', '${batt.soh.toStringAsFixed(1)}%', AppColors.teal),
              _dataItem('充放状态', batt.chargeState, AppColors.teal),
            ]),
          ],

          // PV MPPT
          if (pv != null) ...[
            _divider(context),
            _sectionHeader(context, '光伏 MPPT', Icons.wb_sunny, AppColors.orange, trailing: pv.mpptState),
            _dataGrid(context, [
              _dataItem('PV电压', '${pv.pvVoltage.toStringAsFixed(1)}V', AppColors.orange),
              _dataItem('PV电流', '${pv.pvCurrent.toStringAsFixed(2)}A', AppColors.warning),
              _dataItem('PV功率', '${(pv.pvPower / 1000).toStringAsFixed(2)}kW', AppColors.success),
            ]),
          ],

          // AC Output
          if (ac != null) ...[
            _divider(context),
            _sectionHeader(context, '交流输出', Icons.power, AppColors.success),
            _dataGrid(context, [
              _dataItem('电压', '${ac.voltage.toStringAsFixed(1)}V', AppColors.success),
              _dataItem('电流', '${ac.current.toStringAsFixed(2)}A', AppColors.warning),
              _dataItem('有功功率', '${ac.power.toStringAsFixed(0)}W', AppColors.success),
              _dataItem('频率', '${ac.frequency.toStringAsFixed(2)}Hz', AppColors.orange),
              _dataItem('负载率', '${ac.loadPercent.toStringAsFixed(1)}%', AppColors.blue),
            ]),
          ],

          // Energy
          if (energy != null) ...[
            _divider(context),
            _sectionHeader(context, '能量统计', Icons.battery_charging_full, AppColors.primary),
            _dataGrid(context, [
              _dataItem('日PV发电', '${energy.dailyPV.toStringAsFixed(2)}kWh', AppColors.success),
              _dataItem('总PV发电', '${energy.totalPV.toStringAsFixed(1)}kWh', AppColors.blue),
              _dataItem('运行时', '${energy.runtimeHours}h', AppColors.teal),
            ]),
          ],

          // System Status
          if (sysStatus != null) ...[
            _divider(context),
            _sectionHeader(context, '系统状态', Icons.info_outline, AppColors.primary),
            _statusGrid(context, sysStatus),
          ],

          SizedBox(height: 4.h),
        ],
      ),
    );
  }

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

  /// Grid of data items - 3 per row.
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
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: AppColor.onSurface(context),
            ),
          ),
          SizedBox(height: 1.h),
          Text(
            item.label,
            style: TextStyle(fontSize: 10.sp, color: AppColor.outline(context)),
          ),
        ],
      ),
    );
  }

  /// Status grid with colored indicators.
  Widget _statusGrid(BuildContext context, SysStatus sysStatus) {
    final isRunning = sysStatus.state == 'inverting';
    final hasFault = sysStatus.faultCode != 0;
    final hasAlarm = sysStatus.alarmCode != 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statusCell(context, '工作状态', sysStatus.state, isRunning ? AppColors.success : AppColors.warning)),
              SizedBox(width: 8.w),
              Expanded(child: _statusCell(context, '故障码', '${sysStatus.faultCode}', hasFault ? AppColors.error : AppColors.success)),
              SizedBox(width: 8.w),
              Expanded(child: _statusCell(context, '告警码', '${sysStatus.alarmCode}', hasAlarm ? AppColors.warning : AppColors.success)),
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
          AnimatedValue(
            value: value,
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: color),
          ),
          SizedBox(height: 2.h),
          Text(label, style: TextStyle(fontSize: 10.sp, color: AppColor.outline(context))),
        ],
      ),
    );
  }

  _DataItem _dataItem(String label, String value, Color color) => _DataItem(label, value, color);
}

class _DataItem {
  final String label;
  final String value;
  final Color color;
  _DataItem(this.label, this.value, this.color);
}
