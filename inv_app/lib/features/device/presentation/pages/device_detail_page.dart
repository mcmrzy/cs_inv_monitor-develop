import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/widgets/data_card.dart';
import 'package:inv_app/core/widgets/status_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class DeviceDetailPage extends StatelessWidget {
  final InverterRealtime? data;
  final bool isOnline;
  final VoidCallback? onRefresh;
  final VoidCallback? onNavigateControl;

  const DeviceDetailPage({
    super.key,
    this.data,
    this.isOnline = false,
    this.onRefresh,
    this.onNavigateControl,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;

    if (d == null) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh?.call(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_download_outlined, size: 56.sp, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
              SizedBox(height: 16.h),
              Text(
                '等待实时数据...',
                style: TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.outline),
              ),
              SizedBox(height: 8.h),
              Text(
                '通过MQTT接收设备数据中',
                style: TextStyle(fontSize: 13.sp, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh?.call(),
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _buildDeviceInfo(context, d),
          SizedBox(height: 16.h),
          _buildAcOverview(context, d),
          SizedBox(height: 16.h),
          _buildBatteryDetail(context, d),
          SizedBox(height: 16.h),
          _buildPvDetail(context, d),
          SizedBox(height: 16.h),
          _buildEnergyDetail(context, d),
          SizedBox(height: 16.h),
          _buildStatusDetail(context, d),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo(BuildContext context, InverterRealtime d) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            width: 50.w,
            height: 50.w,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(Icons.solar_power, size: 28.sp, color: AppColors.success),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CS-I10-6K2', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 4.h),
                Text('SN: ${d.deviceSN}', style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          StatusIndicator(status: isOnline ? 1 : (d.sysStatus?.faultCode != 0 ? 2 : 0), label: ''),
        ],
      ),
    );
  }

  Widget _buildAcOverview(BuildContext context, InverterRealtime d) {
    final ac = d.ac;
    if (ac == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('交流输出概览', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '电压', value: ac.voltage.toStringAsFixed(1), unit: 'V', icon: Icons.electrical_services, color: AppColors.success)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '电流', value: ac.current.toStringAsFixed(2), unit: 'A', icon: Icons.bolt, color: AppColors.warning)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '有功功率', value: (ac.power / 1000).toStringAsFixed(2), unit: 'kW', icon: Icons.power, color: AppColors.success)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '视在功率', value: (ac.apparent / 1000).toStringAsFixed(2), unit: 'kVA', icon: Icons.flash_on, color: Colors.blue)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '频率', value: ac.frequency.toStringAsFixed(2), unit: 'Hz', icon: Icons.electrical_services, color: Colors.orange)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '功率因数', value: ac.pf.toStringAsFixed(2), unit: '', icon: Icons.speed, color: Colors.blue)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryDetail(BuildContext context, InverterRealtime d) {
    final batt = d.battery;
    if (batt == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('电池 BMS 详情', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: DataCard(title: 'SOC', value: batt.soc.toStringAsFixed(1), unit: '%', icon: Icons.battery_charging_full, color: AppColors.success)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: 'SOH', value: batt.soh.toStringAsFixed(1), unit: '%', icon: Icons.health_and_safety, color: Colors.teal)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '电压', value: batt.voltage.toStringAsFixed(1), unit: 'V', icon: Icons.electrical_services, color: Colors.blue)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '电流', value: batt.current.toStringAsFixed(2), unit: 'A', icon: Icons.flash_on, color: AppColors.warning)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '剩余容量', value: batt.capacityRemain.toStringAsFixed(1), unit: 'Ah', icon: Icons.battery_full, color: Colors.blue)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '总容量', value: batt.capacityTotal.toStringAsFixed(1), unit: 'Ah', icon: Icons.battery_std, color: Colors.purple)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '最高温度', value: batt.tempMax.toStringAsFixed(1), unit: '°C', icon: Icons.thermostat, color: Colors.red)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '循环次数', value: batt.cycleCount.toString(), unit: '', icon: Icons.loop, color: Colors.orange)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '电芯压差', value: (batt.cellVoltDiff * 1000).toStringAsFixed(0), unit: 'mV', icon: Icons.compare, color: AppColors.warning)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '充放状态', value: batt.chargeState, unit: '', icon: Icons.swap_horiz, color: Colors.teal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPvDetail(BuildContext context, InverterRealtime d) {
    final pv = d.pv;
    if (pv == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(context),
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
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: 'PV功率', value: (pv.pvPower / 1000).toStringAsFixed(2), unit: 'kW', icon: Icons.solar_power, color: AppColors.success)),
              SizedBox(width: 10.w),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyDetail(BuildContext context, InverterRealtime d) {
    final energy = d.energy;
    if (energy == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('能量统计', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '日PV发电', value: energy.dailyPV.toStringAsFixed(2), unit: 'kWh', icon: Icons.wb_sunny_outlined, color: AppColors.success)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '总PV发电', value: energy.totalPV.toStringAsFixed(1), unit: 'kWh', icon: Icons.summarize, color: Colors.blue)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '日充电', value: energy.dailyCharge.toStringAsFixed(2), unit: 'kWh', icon: Icons.upload, color: Colors.green)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '日放电', value: energy.dailyDischarge.toStringAsFixed(2), unit: 'kWh', icon: Icons.download, color: Colors.orange)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '日负载', value: energy.dailyLoad.toStringAsFixed(2), unit: 'kWh', icon: Icons.home, color: Colors.purple)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '运行时', value: energy.runtimeHours.toString(), unit: 'h', icon: Icons.timer, color: Colors.teal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDetail(BuildContext context, InverterRealtime d) {
    final sys = d.sysStatus;
    if (sys == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('系统状态', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '运行状态', value: sys.state, unit: '', icon: Icons.info, color: AppColors.success)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '故障码', value: sys.faultCode.toString(), unit: '', icon: Icons.error_outline, color: sys.faultCode != 0 ? AppColors.error : AppColors.success)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '逆变温度', value: sys.tempInv.toStringAsFixed(1), unit: '°C', icon: Icons.thermostat, color: AppColors.warning)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: 'MOS温度', value: sys.tempMos.toStringAsFixed(1), unit: '°C', icon: Icons.device_thermostat, color: Colors.red)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: '环境温度', value: sys.tempAmbient.toStringAsFixed(1), unit: '°C', icon: Icons.ac_unit, color: Colors.blue)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '效率', value: sys.efficiency.toStringAsFixed(1), unit: '%', icon: Icons.trending_up, color: AppColors.success)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: DataCard(title: 'DC母线', value: sys.dcBusVoltage.toStringAsFixed(1), unit: 'V', icon: Icons.power, color: Colors.orange)),
              SizedBox(width: 10.w),
              Expanded(child: DataCard(title: '风扇', value: '${sys.fanSpeed}%', unit: '', icon: Icons.toys, color: Colors.teal)),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16.r),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
    );
  }
}
