import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/widgets/power_gauge.dart';
import 'package:inv_app/core/widgets/data_card.dart';
import 'package:inv_app/core/widgets/status_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';

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
    if (widget.data != old.data) {
      _updateTime();
    }
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

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh?.call();
      },
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _buildHeader(context, data),
          SizedBox(height: 16.h),
          _buildPowerSection(context, data),
          SizedBox(height: 16.h),
          _buildBatterySection(context, data),
          SizedBox(height: 16.h),
          _buildPVSection(context, data),
          SizedBox(height: 16.h),
          _buildEnergyCards(context, data),
          SizedBox(height: 16.h),
          _buildStatusSection(context, data, isRunning, hasFault),
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
                color: Theme.of(context).colorScheme.onSurface,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              style: TextStyle(
                fontSize: 11.sp,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              data?.deviceSN ?? '',
              style: TextStyle(
                fontSize: 12.sp,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPowerSection(BuildContext context, InverterRealtime? data) {
    final activePower = (data?.ac?.power ?? 0) / 1000.0;
    final loadPercent = data?.ac?.loadPercent ?? 0;
    final frequency = data?.ac?.frequency ?? 0;
    final pf = data?.ac?.pf ?? 0;

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '交流输出功率',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 12.h),
          PowerGauge(
            power: activePower,
            maxPower: 6.2,
            size: 200.w,
          ),
          SizedBox(height: 16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildQuickStat('负载率', '${loadPercent.toStringAsFixed(1)}', '%', Icons.speed, AppColors.success),
              _buildQuickStat('频率', '${frequency.toStringAsFixed(1)}', 'Hz', Icons.electrical_services, AppColors.warning),
              _buildQuickStat('功率因数', '${pf.toStringAsFixed(2)}', '', Icons.tune, Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatterySection(BuildContext context, InverterRealtime? data) {
    final batt = data?.battery;
    if (batt == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('电池 BMS', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: DataCard(title: 'SOC', value: batt.soc.toStringAsFixed(1), unit: '%', icon: Icons.battery_charging_full, color: AppColors.success)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '电压', value: batt.voltage.toStringAsFixed(1), unit: 'V', icon: Icons.electrical_services, color: Colors.blue)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '电流', value: batt.current.toStringAsFixed(2), unit: 'A', icon: Icons.flash_on, color: AppColors.warning)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '电池温度', value: batt.tempMax.toStringAsFixed(1), unit: '°C', icon: Icons.thermostat, color: Colors.orange)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '循环次数', value: batt.cycleCount.toString(), unit: '', icon: Icons.loop, color: Colors.purple)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: 'SOH', value: batt.soh.toStringAsFixed(1), unit: '%', icon: Icons.health_and_safety, color: Colors.teal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPVSection(BuildContext context, InverterRealtime? data) {
    final pv = data?.pv;
    if (pv == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('光伏 MPPT', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
              Text(pv.mpptState, style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.outline)),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: DataCard(title: 'PV电压', value: pv.pvVoltage.toStringAsFixed(1), unit: 'V', icon: Icons.wb_sunny, color: Colors.orange)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: 'PV电流', value: pv.pvCurrent.toStringAsFixed(2), unit: 'A', icon: Icons.electric_bolt, color: Colors.amber)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: 'PV功率', value: (pv.pvPower / 1000).toStringAsFixed(2), unit: 'kW', icon: Icons.solar_power, color: AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyCards(BuildContext context, InverterRealtime? data) {
    final energy = data?.energy;
    if (energy == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: DataCard(
            title: '日PV发电',
            value: energy.dailyPV.toStringAsFixed(2),
            unit: 'kWh',
            icon: Icons.wb_sunny_outlined,
            color: AppColors.success,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: DataCard(
            title: '总PV发电',
            value: energy.totalPV.toStringAsFixed(1),
            unit: 'kWh',
            icon: Icons.summarize,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStat(String label, String value, String unit, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20.sp, color: color),
        SizedBox(height: 4.h),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection(BuildContext context, InverterRealtime? data, bool isRunning, bool hasFault) {
    final sysStatus = data?.sysStatus;
    final energy = data?.energy;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '运行状态',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              _buildStatusItem('工作状态', sysStatus?.state ?? '--', isRunning ? AppColors.success : AppColors.warning),
              SizedBox(width: 8.w),
              _buildStatusItem('故障码', sysStatus != null ? '${sysStatus.faultCode}' : '--', hasFault ? AppColors.error : AppColors.success),
              SizedBox(width: 8.w),
              _buildStatusItem('逆变温度', sysStatus != null ? '${sysStatus.tempInv.toStringAsFixed(1)}°C' : '--', AppColors.warning),
            ],
          ),
          SizedBox(height: 12.h),
          const Divider(height: 1),
          SizedBox(height: 12.h),
          Row(
            children: [
              _buildStatusItem('效率', sysStatus != null ? '${sysStatus.efficiency.toStringAsFixed(1)}%' : '--', Colors.blue),
              SizedBox(width: 8.w),
              _buildStatusItem('风扇转速', sysStatus != null ? '${sysStatus.fanSpeed}%' : '--', Colors.blue),
              SizedBox(width: 8.w),
              _buildStatusItem('运行时长', energy != null ? '${energy.runtimeHours}h' : '--', Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.sp,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
