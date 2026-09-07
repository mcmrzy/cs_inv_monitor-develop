// 设备详情页 Tab 子组件
//
// 包含 3 个 Tab（远程设置 Tab 由页面内嵌 RemoteSettingsTab 提供）：
//   1. RealtimeDataTab  实时数据（安装商视角，分组键值列表）
//   2. EnergyStatsTab   能量统计（今日 / 累计，来自 EnergyData）
//   3. DeviceHealthTab  设备健康（健康度圆环 + 温度/风扇/运行时长）
//
// 数据统一来自 InverterRealtime（RealtimeDataService 订阅/轮询），
// derived 字段（如 derived_health_score）由页面传入的扁平 realtime map 提供。

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/l10n/app_localizations.dart';

// ═══════════════════════════ 通用格式化 ═══════════════════════════

/// 数值 1 位小数，null 显示 '--'
String _fmt1(double? v) => v == null ? '--' : v.toStringAsFixed(1);

/// 电量格式化：≥1000 kWh 显示 MWh
String _fmtKwh(double v) {
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} MWh';
  return '${v.toStringAsFixed(1)} kWh';
}

/// CO₂ 减排：≥1000 kg 转 t（1 位小数）
String _fmtCo2(double kg) {
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)} t';
  return '${kg.toStringAsFixed(0)} kg';
}

// ═══════════════════════════ 通用卡片组件 ═══════════════════════════

/// 卡片组头：图标 + 标题
Widget _cardHeader(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
}) {
  return Row(
    children: [
      Container(
        padding: EdgeInsets.all(6.w),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Icon(icon, size: 16.sp, color: color),
      ),
      SizedBox(width: 8.w),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: AppColor.textPrimary(context),
          ),
        ),
      ),
    ],
  );
}

/// 键值行：标签左 / 值右
Widget _kvRow(
  BuildContext context,
  String label,
  String value, {
  Color? valueColor,
}) {
  return Padding(
    padding: EdgeInsets.only(top: 8.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textSecondary(context),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColor.textPrimary(context),
          ),
        ),
      ],
    ),
  );
}

/// 大号数值展示（数值 + 下方说明标签）
Widget _bigValue(BuildContext context, String value, String label, Color color) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 8.h),
      Text(
        value,
        style: TextStyle(
          fontSize: 22.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      SizedBox(height: 2.h),
      Text(
        label,
        style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
      ),
    ],
  );
}

/// 分组卡片：组头 + 键值行列表（Tab2 实时数据用）
Widget _groupCard(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required List<Widget> rows,
}) {
  return Container(
    margin: EdgeInsets.only(bottom: 12.h),
    padding: EdgeInsets.all(14.w),
    decoration: AppColor.card(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader(context, icon: icon, color: color, title: title),
        SizedBox(height: 4.h),
        ...rows,
      ],
    ),
  );
}

// ═══════════════════════════ 实时数据 ═══════════════════════════

/// 实时数据（安装商视角）
/// PV / 电池 / 逆变器 / 交流输出 四组键值列表 + 底部功能入口
class RealtimeDataTab extends StatelessWidget {
  final InverterRealtime? data;

  /// 底部附加内容（参数设置 / 协议遥测入口，由页面注入）
  final Widget? footer;

  const RealtimeDataTab({super.key, required this.data, this.footer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pv = data?.pv;
    final battery = data?.battery;
    final sys = data?.sysStatus;
    final ac = data?.ac;

    // 组内行构造：值含单位、1 位小数；对应分组数据缺失时显示 '--'
    String num1(double? v, String unit) => v == null
        ? '--'
        : unit.isEmpty
            ? v.toStringAsFixed(1)
            : '${v.toStringAsFixed(1)} $unit';

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
      children: [
        // ── PV ──
        _groupCard(
          context,
          icon: Icons.wb_sunny_outlined,
          color: AppColors.orange,
          title: l10n.str('pv'),
          rows: [
            _kvRow(context, l10n.str('energy_pv1_voltage'), num1(pv?.pvVoltage, 'V')),
            _kvRow(context, l10n.str('energy_pv1_current'), num1(pv?.pvCurrent, 'A')),
            _kvRow(context, l10n.str('energy_pv1_power'), num1(pv?.pvPower, 'W')),
            _kvRow(context, l10n.str('energy_pv2_voltage'), num1(pv?.pv2Voltage, 'V')),
            _kvRow(context, l10n.str('energy_pv2_current'), num1(pv?.pv2Current, 'A')),
            _kvRow(context, l10n.str('energy_pv2_power'), num1(pv?.pv2Power, 'W')),
            _kvRow(
              context,
              l10n.str('energy_mppt_state'),
              (pv == null || pv.mpptState.isEmpty) ? '--' : pv.mpptState,
            ),
          ],
        ),
        // ── 电池 ──
        _groupCard(
          context,
          icon: Icons.battery_charging_full,
          color: AppColors.teal,
          title: l10n.str('battery_label'),
          rows: [
            _kvRow(context, l10n.str('voltage'), num1(battery?.voltage, 'V')),
            _kvRow(context, 'SOC', num1(battery?.soc, '%')),
            _kvRow(context, l10n.str('current'), num1(battery?.current, 'A')),
            _kvRow(
              context,
              l10n.str('energy_battery_temp_max'),
              num1(battery?.tempMax, '℃'),
            ),
            _kvRow(
              context,
              l10n.str('energy_max_charge_current'),
              num1(battery?.maxChargeCurrent, 'A'),
            ),
            _kvRow(
              context,
              l10n.str('energy_max_discharge_current'),
              num1(battery?.maxDischargeCurrent, 'A'),
            ),
            _kvRow(
              context,
              l10n.str('energy_cycle_count'),
              battery == null ? '--' : '${battery.cycleCount}',
            ),
          ],
        ),
        // ── 逆变器 ──
        _groupCard(
          context,
          icon: Icons.power_rounded,
          color: AppColors.primary,
          title: l10n.str('inverter'),
          rows: [
            _kvRow(context, l10n.str('inverter_temp'), num1(sys?.tempInv, '℃')),
            _kvRow(context, l10n.str('boost_temp'), num1(sys?.boostTemp, '℃')),
            _kvRow(
              context,
              l10n.str('transformer_temp'),
              num1(sys?.transformerTemp, '℃'),
            ),
            _kvRow(context, l10n.str('pv_temp'), num1(sys?.pvTemp, '℃')),
            _kvRow(
              context,
              l10n.str('energy_dc_bus_voltage'),
              num1(sys?.dcBusVoltage, 'V'),
            ),
            _kvRow(
                context, l10n.str('mppt_fan_speed'), num1(data?.fan?.mpptSpeed, '%')),
            _kvRow(
                context, l10n.str('inv_fan_speed'), num1(data?.fan?.invSpeed, '%')),
            _kvRow(
              context,
              l10n.str('energy_runtime_hours'),
              (data?.workTimeTotalSec ?? 0) > 0
                  ? '${(data!.workTimeTotalSec / 3600).toStringAsFixed(0)} h'
                  : '--',
            ),
          ],
        ),
        // ── 交流输出 ──
        _groupCard(
          context,
          icon: Icons.bolt_rounded,
          color: AppColors.purple,
          title: l10n.str('ac_output'),
          rows: [
            _kvRow(context, l10n.str('voltage'), num1(ac?.voltage, 'V')),
            _kvRow(context, l10n.str('current'), num1(ac?.current, 'A')),
            _kvRow(context, l10n.str('ac_output_power'), num1(ac?.power, 'W')),
            _kvRow(context, l10n.str('frequency'), num1(ac?.frequency, 'Hz')),
            _kvRow(context, l10n.str('load_rate'), num1(sys?.loadPercent, '%')),
            _kvRow(
              context,
              l10n.str('energy_power_factor'),
              num1(ac?.pf, ''),
            ),
          ],
        ),
        // 底部功能入口（参数设置 / 协议遥测）
        if (footer != null) footer!,
      ],
    );
  }
}

// ═══════════════════════════ 能量统计 ═══════════════════════════

/// 能量统计（全部来自 EnergyData，无需新接口）
class EnergyStatsTab extends StatelessWidget {
  final InverterRealtime? data;

  const EnergyStatsTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final energy = data?.energy;

    String kwh(double? v) => v == null ? '--' : _fmtKwh(v);

    // CO₂ 减排 = 累计发电 × 0.997 kg
    final totalPV = energy?.totalPV ?? 0;
    final co2 = totalPV * 0.997;

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
      children: [
        // ── 今天 ──
        _groupCard(
          context,
          icon: Icons.today_rounded,
          color: AppColors.orange,
          title: l10n.str('time_today'),
          rows: [
            _kvRow(context, l10n.str('pv_generation'), kwh(energy?.dailyPV)),
            _kvRow(context, l10n.str('battery_charge'), kwh(energy?.dailyCharge)),
            _kvRow(context, l10n.str('battery_discharge'), kwh(energy?.dailyDischarge)),
            _kvRow(context, l10n.str('energy_load_usage'), kwh(energy?.dailyLoad)),
            // V2 能量分项（仅在有值时显示）
            if ((energy?.dailyGenEnergy ?? 0) > 0)
              _kvRow(context, l10n.str('energy_gen_daily'), kwh(energy?.dailyGenEnergy)),
            if ((energy?.dailyAcChargeEnergy ?? 0) > 0)
              _kvRow(context, l10n.str('energy_ac_charge_daily'), kwh(energy?.dailyAcChargeEnergy)),
            if ((energy?.dailyAcBypassEnergy ?? 0) > 0)
              _kvRow(context, l10n.str('energy_ac_bypass_daily'), kwh(energy?.dailyAcBypassEnergy)),
            if ((energy?.dailyOutputEnergy ?? 0) > 0)
              _kvRow(context, l10n.str('energy_output_daily'), kwh(energy?.dailyOutputEnergy)),
          ],
        ),
        // ── 累计 ──
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: AppColor.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardHeader(
                context,
                icon: Icons.show_chart_rounded,
                color: AppColors.blue,
                title: l10n.str('time_total'),
              ),
              _bigValue(
                context,
                kwh(totalPV),
                l10n.str('total_generation'),
                AppColors.blue,
              ),
              _kvRow(
                context,
                l10n.str('co2_reduction'),
                _fmtCo2(co2),
                valueColor: AppColors.success,
              ),
              _kvRow(
                context,
                l10n.str('energy_total_load'),
                kwh(energy?.totalLoad),
              ),
              // V2 累计能量分项（仅在有值时显示）
              if ((energy?.totalGenEnergy ?? 0) > 0)
                _kvRow(context, l10n.str('energy_gen_total'), kwh(energy?.totalGenEnergy)),
              if ((energy?.totalAcChargeEnergy ?? 0) > 0)
                _kvRow(context, l10n.str('energy_ac_charge_total'), kwh(energy?.totalAcChargeEnergy)),
              if ((energy?.totalAcBypassEnergy ?? 0) > 0)
                _kvRow(context, l10n.str('energy_ac_bypass_total'), kwh(energy?.totalAcBypassEnergy)),
              if ((energy?.totalOutputEnergy ?? 0) > 0)
                _kvRow(context, l10n.str('energy_output_total'), kwh(energy?.totalOutputEnergy)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════ 设备健康 ═══════════════════════════

/// 设备健康
/// 健康度圆环（derived_health_score 优先，缺失时本地估算）+
/// 温度卡片 + 风扇转速 + 累计运行时长；设备离线时展示离线空态
class DeviceHealthTab extends StatelessWidget {
  final InverterRealtime? data;

  /// 页面扁平 realtime map（derived_health_score / diag_work_time_total 来源）
  final Map<String, dynamic> flat;

  /// 设备在线状态
  final bool online;

  const DeviceHealthTab({
    super.key,
    required this.data,
    required this.flat,
    required this.online,
  });

  /// 健康度估算：derived 字段优先；缺失时按简单规则估算
  /// （100 起，faultCode!=0 -40，tempInv>65 -20，风扇最大转速>80 -10，下限 0）
  int _estimateScore() {
    final derived = flat['derived_health_score'];
    if (derived is num) return derived.round().clamp(0, 100);

    final sys = data?.sysStatus;
    int score = 100;
    if (sys != null) {
      if (sys.faultCode != 0) score -= 40;
      if (sys.tempInv > 65) score -= 20;
      if ((data?.fan?.maxSpeed ?? 0) > 80) score -= 10;
    }
    return score.clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // 设备离线：沿用 XiaoshuoStatePanel 展示离线空态
    if (!online) {
      return XiaoshuoStatePanel(
        asset: CsergyAssets.xiaoshuoOffline,
        title: l10n.str('offline'),
        message: l10n.str('health_offline_hint'),
        size: 150,
      );
    }

    final score = _estimateScore();
    final color = score >= 80
        ? AppColors.success
        : (score >= 60 ? AppColors.warning : AppColors.error);
    final levelKey = score >= 80
        ? 'health_level_healthy'
        : (score >= 60 ? 'health_level_attention' : 'health_level_maintenance');

    final sys = data?.sysStatus;

    // 累计运行时长：diag 组 work_time_total（秒）
    final String workHours =
        ((data?.workTimeTotalSec ?? 0) / 3600).toStringAsFixed(0);

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
      children: [
        // ── 健康度圆环 ──
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
          decoration: AppColor.card(context),
          child: Column(
            children: [
              SizedBox(
                width: 120.w,
                height: 120.w,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (score / 100).clamp(0.0, 1.0),
                      strokeWidth: 8.w,
                      color: color,
                      backgroundColor: AppColor.divider(context),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$score',
                            style: TextStyle(
                              fontSize: 28.sp,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          Text(
                            l10n.str('health_score'),
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppColor.textHint(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10.h),
              // 级别文案：健康 / 注意 / 维护
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  l10n.str(levelKey),
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        // ── 温度卡片（2×2：逆变/升压/变压器/PV 电池板）──
        Row(
          children: [
            Expanded(
              child: _tempCard(
                context,
                l10n.str('inverter_temp'),
                sys?.tempInv,
                Icons.device_thermostat_rounded,
                AppColors.orange,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _tempCard(
                context,
                l10n.str('boost_temp'),
                sys?.boostTemp,
                Icons.memory_rounded,
                AppColors.errorLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            Expanded(
              child: _tempCard(
                context,
                l10n.str('transformer_temp'),
                sys?.transformerTemp,
                Icons.thermostat_rounded,
                AppColors.blue,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _tempCard(
                context,
                l10n.str('pv_temp'),
                sys?.pvTemp,
                Icons.wb_sunny_rounded,
                AppColors.teal,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        // ── 风扇转速（MPPT/逆变双风扇）+ 累计运行时长 ──
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: AppColor.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardHeader(
                context,
                icon: Icons.air_rounded,
                color: AppColors.cyan,
                title: l10n.str('energy_fan_speed'),
              ),
              SizedBox(height: 8.h),
              _fanBar(context, l10n.str('mppt_fan_speed'), data?.fan?.mpptSpeed),
              SizedBox(height: 10.h),
              _fanBar(context, l10n.str('inv_fan_speed'), data?.fan?.invSpeed),
              SizedBox(height: 8.h),
              _kvRow(
                context,
                l10n.str('health_work_time'),
                '$workHours ${l10n.str('health_hours')}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 风扇转速条（标签 + 进度 + 百分比）
  Widget _fanBar(BuildContext context, String label, double? speed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
            ),
            Text(
              '${_fmt1(speed)} %',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.cyan,
              ),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: LinearProgressIndicator(
            value: ((speed ?? 0) / 100).clamp(0.0, 1.0),
            minHeight: 6.h,
            color: AppColors.cyan,
            backgroundColor: AppColor.divider(context),
          ),
        ),
      ],
    );
  }

  /// 温度小卡片（带 ℃）
  Widget _tempCard(
    BuildContext context,
    String label,
    double? temp,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.sp, color: color),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            '${_fmt1(temp)} ℃',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
