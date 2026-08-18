// 设备详情「能源流监控中心」Tab 子组件
//
// 包含 5 个 Tab：
//   1. EnergyFlowTab    能源流（普通用户视角，粒子动画 + 四卡片）
//   2. RealtimeDataTab  实时数据（安装商视角，分组键值列表）
//   3. EnergyStatsTab   能量统计（今日 / 累计，来自 EnergyData）
//   4. StatusCenterTab  状态中心（系统状态卡 + 历史告警列表）
//   5. DeviceHealthTab  设备健康（健康度圆环 + 温度/风扇/运行时长）
//
// 数据统一来自 InverterRealtime（RealtimeDataService 订阅/轮询），
// derived 字段（如 derived_health_score）由页面传入的扁平 realtime map 提供。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/core/widgets/energy_flow_diagram.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/l10n/app_localizations.dart';

// ═══════════════════════════ 通用格式化 ═══════════════════════════

/// 功率格式化：≥1000W 显示 kW（1 位小数），null 显示 '--'
String _fmtPower(double? w) {
  if (w == null) return '--';
  if (w.abs() >= 1000) return '${(w / 1000).toStringAsFixed(1)} kW';
  return '${w.toStringAsFixed(0)} W';
}

/// 带符号功率（电池：充电 +W / 放电 -W）
String _fmtSignedPower(double w) {
  if (w.abs() >= 1000) {
    final kw = w / 1000;
    return '${kw > 0 ? '+' : ''}${kw.toStringAsFixed(1)} kW';
  }
  return '${w > 0 ? '+' : ''}${w.toStringAsFixed(0)} W';
}

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

/// 电池充放电状态判定（charging 为充电）
enum _BatteryState { charging, discharging, standby }

_BatteryState _batteryStateOf(String chargeState) {
  final s = chargeState.toLowerCase();
  if (s.contains('discharg')) return _BatteryState.discharging;
  if (s.contains('charg')) return _BatteryState.charging;
  return _BatteryState.standby;
}

// ═══════════════════════════ 能源流数据模型 ═══════════════════════════

/// 能源流功率模型：统一各节点功率与方向约定
///
/// [EnergyFlowDiagram] 组件约定：
///   - batteryPower > 0 = 充电（逆变器 → 电池），< 0 = 放电
///   - gridPower    > 0 = 馈电（逆变器 → 电网），< 0 = 购电（电网 → 逆变器）
class _EnergyModel {
  /// 光伏功率 W
  final double pvW;

  /// 负载功率 W
  final double loadW;

  /// 电池功率 W（充电为正 / 放电为负，组件约定）
  final double battW;

  /// 电网交换功率 W（按需求公式：负载 - 光伏 - 放电功率，购电为正）
  final double gridRawW;

  /// 电池 SOC
  final double soc;

  const _EnergyModel({
    required this.pvW,
    required this.loadW,
    required this.battW,
    required this.gridRawW,
    required this.soc,
  });

  /// 放电功率（放电为正 / 充电为负）
  double get dischargeW => battW < 0 ? -battW : 0;

  /// 电网功率按组件语义传参：馈电为正 / 购电为负；<20W 视为待机
  double get gridDiagramW {
    if (gridRawW.abs() < 20) return 0;
    return -gridRawW;
  }

  factory _EnergyModel.from(InverterRealtime? data) {
    final pvW = data?.pv?.pvPower ?? 0;
    final loadW = data?.ac?.power ?? 0;
    final battery = data?.battery;

    // 电池功率方向按 chargeState（charging=充电），幅值优先取 power，
    // 缺失时用 |电压 × 电流| 估算
    double battW = 0;
    if (battery != null && battery.chargeState.isNotEmpty) {
      final mag = battery.power != 0
          ? battery.power.abs()
          : (battery.voltage * battery.current).abs();
      switch (_batteryStateOf(battery.chargeState)) {
        case _BatteryState.charging:
          battW = mag;
        case _BatteryState.discharging:
          battW = -mag;
        case _BatteryState.standby:
          battW = 0;
      }
    }
    final dischargeW = battW < 0 ? -battW : 0;
    // gridW = 负载 - 光伏 - 放电功率（放电为正 / 充电为负）
    final gridRawW = loadW - pvW - dischargeW;

    return _EnergyModel(
      pvW: pvW,
      loadW: loadW,
      battW: battW,
      gridRawW: gridRawW,
      soc: battery?.soc ?? 0,
    );
  }
}

// ═══════════════════════════ 通用卡片组件 ═══════════════════════════

/// 圆角卡片容器
Widget _card(BuildContext context, {required Widget child}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(14.w),
    decoration: AppColor.card(context),
    child: child,
  );
}

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

// ═══════════════════════════ Tab1 能源流 ═══════════════════════════

/// Tab1：能源流（普通用户视角）
/// 顶部粒子动画能流图 + 下方光伏/电池/负载/市电四张语义色卡片
class EnergyFlowTab extends StatelessWidget {
  final InverterRealtime? data;

  const EnergyFlowTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final m = _EnergyModel.from(data);

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
      children: [
        // 能流图（按组件语义传参：电池充电为正，电网馈电为正）
        EnergyFlowDiagram(
          pvPower: m.pvW,
          batteryPower: m.battW,
          loadPower: m.loadW,
          gridPower: m.gridDiagramW,
          batterySoc: m.soc,
        ),
        SizedBox(height: 12.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildPvCard(context, l10n)),
            SizedBox(width: 10.w),
            Expanded(child: _buildBatteryCard(context, l10n, m)),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLoadCard(context, l10n)),
            SizedBox(width: 10.w),
            Expanded(child: _buildGridCard(context, l10n, m)),
          ],
        ),
      ],
    );
  }

  /// ☀️ 光伏卡片（橙色）
  Widget _buildPvCard(BuildContext context, AppLocalizations l10n) {
    final pv = data?.pv;
    final energy = data?.energy;
    // PV2 电压可能为空（未接组串），0 视为无数据显示 '--'
    final pv2 = (pv == null || pv.pv2Voltage <= 0) ? null : pv.pv2Voltage;
    final color = AppColors.orange;

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            context,
            icon: Icons.wb_sunny_outlined,
            color: color,
            title: l10n.str('pv'),
          ),
          _bigValue(context, _fmtPower(pv?.pvPower), l10n.str('realtime_power'), color),
          _kvRow(context, l10n.str('energy_pv1_voltage'), '${_fmt1(pv?.pvVoltage)} V'),
          _kvRow(context, l10n.str('energy_pv2_voltage'), '${_fmt1(pv2)} V'),
          _kvRow(
            context,
            l10n.str('today_generation'),
            _fmtKwh(energy?.dailyPV ?? 0),
          ),
          _kvRow(
            context,
            l10n.str('total_generation'),
            _fmtKwh(energy?.totalPV ?? 0),
          ),
        ],
      ),
    );
  }

  /// 🔋 电池卡片（青色）：SOC 圆环 + 电压/状态/功率/电流
  Widget _buildBatteryCard(
    BuildContext context,
    AppLocalizations l10n,
    _EnergyModel m,
  ) {
    final battery = data?.battery;
    final color = AppColors.teal;
    final state = battery == null
        ? _BatteryState.standby
        : _batteryStateOf(battery.chargeState);
    final stateText = switch (state) {
      _BatteryState.charging => l10n.str('energy_state_charging'),
      _BatteryState.discharging => l10n.str('energy_state_discharging'),
      _BatteryState.standby => l10n.str('energy_state_standby'),
    };
    final stateColor = switch (state) {
      _BatteryState.charging => AppColors.success,
      _BatteryState.discharging => AppColors.orange,
      _BatteryState.standby => AppColor.textHint(context),
    };

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            context,
            icon: Icons.battery_charging_full,
            color: color,
            title: l10n.str('battery_label'),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              // SOC 大圆环：SizedBox + Stack + CircularProgressIndicator 自绘
              SizedBox(
                width: 72.w,
                height: 72.w,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (m.soc / 100).clamp(0.0, 1.0),
                      strokeWidth: 6.w,
                      color: color,
                      backgroundColor: AppColor.divider(context),
                    ),
                    Center(
                      child: Text(
                        '${m.soc.round()}%',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvRow(
                      context,
                      l10n.str('voltage'),
                      '${_fmt1(battery?.voltage)} V',
                    ),
                    _kvRow(
                      context,
                      l10n.str('charge_discharge_status'),
                      stateText,
                      valueColor: stateColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 功率：充电 +W / 放电 -W
          _kvRow(
            context,
            l10n.str('energy_battery_power'),
            _fmtSignedPower(m.battW),
          ),
          _kvRow(context, l10n.str('current'), '${_fmt1(battery?.current)} A'),
        ],
      ),
    );
  }

  /// 🏠 负载卡片（紫色）
  Widget _buildLoadCard(BuildContext context, AppLocalizations l10n) {
    final ac = data?.ac;
    final color = AppColors.purple;

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            context,
            icon: Icons.home_rounded,
            color: color,
            title: l10n.str('load_label'),
          ),
          _bigValue(context, _fmtPower(ac?.power), l10n.str('realtime_power'), color),
          _kvRow(
            context,
            l10n.str('load_rate'),
            '${_fmt1(ac?.loadPercent)} %',
          ),
          _kvRow(context, l10n.str('current'), '${_fmt1(ac?.current)} A'),
        ],
      ),
    );
  }

  /// 🌐 市电卡片（蓝色）：状态按 gridW 方向判定
  Widget _buildGridCard(
    BuildContext context,
    AppLocalizations l10n,
    _EnergyModel m,
  ) {
    final ac = data?.ac;
    final color = AppColors.blue;

    // gridRawW > 0 购电（输入）；< 0 馈电；±20W 内视为待机
    final String stateText;
    final Color stateColor;
    if (m.gridRawW > 20) {
      stateText = l10n.str('energy_grid_importing');
      stateColor = color;
    } else if (m.gridRawW < -20) {
      stateText = l10n.str('energy_grid_feeding');
      stateColor = AppColors.successLight;
    } else {
      stateText = l10n.str('energy_state_standby');
      stateColor = AppColor.textHint(context);
    }

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            context,
            icon: Icons.electrical_services_rounded,
            color: color,
            title: l10n.str('grid_label'),
          ),
          SizedBox(height: 8.h),
          _kvRow(context, l10n.str('status_prefix'), stateText, valueColor: stateColor),
          _kvRow(context, l10n.str('energy_power_label'), _fmtPower(m.gridRawW.abs())),
          _kvRow(
            context,
            l10n.str('voltage'),
            '${_fmt1(ac?.voltage)} V · ${_fmt1(ac?.frequency)} Hz',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ Tab2 实时数据 ═══════════════════════════

/// Tab2：实时数据（安装商视角）
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
            _kvRow(context, l10n.str('mos_temp'), num1(sys?.tempMos, '℃')),
            _kvRow(
              context,
              l10n.str('energy_ambient_temp'),
              num1(sys?.ambientTemperature, '℃'),
            ),
            _kvRow(
              context,
              l10n.str('energy_dc_bus_voltage'),
              num1(sys?.dcBusVoltage, 'V'),
            ),
            _kvRow(context, l10n.str('efficiency'), num1(sys?.efficiency, '%')),
            _kvRow(
              context,
              l10n.str('energy_fan_speed'),
              num1(sys?.fanSpeedPercent, '%'),
            ),
            _kvRow(
              context,
              l10n.str('energy_runtime_hours'),
              sys == null ? '--' : '${sys.runtimeHours} h',
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
            _kvRow(context, l10n.str('load_rate'), num1(ac?.loadPercent, '%')),
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

// ═══════════════════════════ Tab3 能量统计 ═══════════════════════════

/// Tab3：能量统计（全部来自 EnergyData，无需新接口）
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
            _kvRow(context, l10n.str('energy_feed_energy'), kwh(energy?.dailyFeedEnergy)),
            _kvRow(context, l10n.str('energy_grid_import'), kwh(energy?.dailyGridImport)),
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
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════ Tab4 状态中心 ═══════════════════════════

/// Tab4：状态中心
/// 顶部系统状态大卡（故障/告警码映射描述）+ 历史告警列表
class StatusCenterTab extends StatefulWidget {
  final String sn;
  final InverterRealtime? data;

  const StatusCenterTab({super.key, required this.sn, required this.data});

  @override
  State<StatusCenterTab> createState() => _StatusCenterTabState();
}

class _StatusCenterTabState extends State<StatusCenterTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchAlarmEvents();
  }

  /// 拉取历史告警事件（GET /devices/by-sn/:sn/alarm-events?page_size=20）
  Future<void> _fetchAlarmEvents() async {
    if (mounted) setState(() => _loading = true);
    try {
      final dio = getIt<Dio>();
      final res = await dio
          .get(
            '/devices/by-sn/${widget.sn}/alarm-events',
            queryParameters: {'page_size': 20},
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final data = unwrapApiResponse<Map<String, dynamic>>(
        res.data,
        validate: (value) => value is Map<String, dynamic>,
        expected: 'an object',
      );
      final items = (data['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.str('load_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 40.h),
      children: [
        _buildSystemStatusCard(context),
        SizedBox(height: 16.h),
        _buildHistoryHeader(context),
        SizedBox(height: 8.h),
        _buildHistoryList(context),
      ],
    );
  }

  /// 顶部大状态卡：faultCode/alarmCode 均为 0 → 绿色「系统正常」
  Widget _buildSystemStatusCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sys = widget.data?.sysStatus;
    final battery = widget.data?.battery;
    final fault = sys?.faultCode ?? 0;
    final alarm = sys?.alarmCode ?? 0;

    final Color color;
    final String title;
    if (fault == 0 && alarm == 0) {
      color = AppColors.success;
      title = l10n.str('status_center_system_normal');
    } else if (fault != 0) {
      color = AppColors.error;
      title = l10n.str('status_center_system_fault');
    } else {
      color = AppColors.warning;
      title = l10n.str('status_center_system_alarm');
    }

    // 告警码映射描述（优先故障码，其次告警码）
    final lang = Localizations.localeOf(context).languageCode;
    final code = fault != 0 ? fault : alarm;
    final entry = AlarmCodeMapping.getEntry(code);
    final name = entry?.getLocalizedName(lang) ?? '--';
    final desc = entry?.getLocalizedDescription(lang) ?? '--';

    // 电池 BMS 告警 / 保护状态异常提示
    final hasBatteryAlarm = battery != null &&
        (battery.bmsFaultCode != 0 || battery.protectStatus != 0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fault == 0 && alarm == 0
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                size: 26.sp,
                color: color,
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            name,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            desc,
            style: TextStyle(
              fontSize: 12.sp,
              height: 1.5,
              color: AppColor.textSecondary(context),
            ),
          ),
          if (hasBatteryAlarm) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.battery_alert_rounded,
                    size: 16.sp,
                    color: AppColors.error,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      l10n.str('status_center_battery_alarm_hint'),
                      style: TextStyle(fontSize: 12.sp, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(
          Icons.history_rounded,
          size: 16.sp,
          color: AppColor.textSecondary(context),
        ),
        SizedBox(width: 6.w),
        Text(
          l10n.str('status_center_alarm_history'),
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: AppColor.textPrimary(context),
          ),
        ),
      ],
    );
  }

  /// 历史告警列表：加载中 / 空态 / 失败重试 / 列表 三态
  Widget _buildHistoryList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 40.h),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        child: Column(
          children: [
            Text(
              _error!,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColor.textSecondary(context),
              ),
            ),
            SizedBox(height: 12.h),
            OutlinedButton(
              onPressed: _fetchAlarmEvents,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 32.h),
        child: Center(
          child: Text(
            l10n.str('no_alarm_events'),
            style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final item in _items) _buildAlarmRow(context, item),
      ],
    );
  }

  /// 单条告警行：告警名 + 时间（本地时区）+ 状态徽标
  Widget _buildAlarmRow(BuildContext context, Map<String, dynamic> item) {
    final l10n = AppLocalizations.of(context)!;
    final lang = Localizations.localeOf(context).languageCode;

    // 后端 code 为字符串，解析为告警码查映射表
    final codeRaw = item['code']?.toString() ?? '';
    final code = int.tryParse(codeRaw);
    final name = code != null
        ? AlarmCodeMapping.getLocalizedName(code, lang)
        : (codeRaw.isEmpty ? l10n.str('unknown_alarm') : codeRaw);

    // 时间：优先 event_time，缺失时回退 active_at
    final timeRaw = (item['event_time'] ?? item['active_at']) as String?;
    final time = DateTime.tryParse(timeRaw ?? '');
    final timeStr = time == null
        ? '--'
        : DateFormat('yyyy-MM-dd HH:mm').format(time.toLocal());

    // 状态：state == 'active' → 激活中（红）；否则已恢复（绿）
    final active = item['state']?.toString() == 'active';
    final badgeText = active
        ? l10n.str('status_center_alarm_active')
        : l10n.str('status_center_alarm_recovered');
    final badgeColor = active ? AppColors.errorLight : AppColors.successLight;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: AppColor.card(context),
      child: Row(
        children: [
          Icon(
            active
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 18.sp,
            color: badgeColor,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ Tab5 设备健康 ═══════════════════════════

/// Tab5：设备健康
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
  /// （100 起，faultCode!=0 -40，tempInv>65 -20，fanSpeedPercent>80 -10，下限 0）
  int _estimateScore() {
    final derived = flat['derived_health_score'];
    if (derived is num) return derived.round().clamp(0, 100);

    final sys = data?.sysStatus;
    int score = 100;
    if (sys != null) {
      if (sys.faultCode != 0) score -= 40;
      if (sys.tempInv > 65) score -= 20;
      if (sys.fanSpeedPercent > 80) score -= 10;
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
    final battery = data?.battery;

    // 累计运行时长：优先 diag_work_time_total（秒），回退 runtimeHours
    final workTimeTotal = flat['diag_work_time_total'];
    final String workHours = workTimeTotal is num
        ? (workTimeTotal / 3600).toStringAsFixed(0)
        : (sys?.runtimeHours ?? 0).toString();

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
        // ── 温度卡片（2×2）──
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
                l10n.str('mos_temp'),
                sys?.tempMos,
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
                l10n.str('energy_ambient_temp'),
                sys?.ambientTemperature,
                Icons.thermostat_rounded,
                AppColors.blue,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _tempCard(
                context,
                l10n.str('energy_battery_temp_max'),
                battery?.tempMax,
                Icons.battery_std_rounded,
                AppColors.teal,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        // ── 风扇转速 + 累计运行时长 ──
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
              ClipRRect(
                borderRadius: BorderRadius.circular(4.r),
                child: LinearProgressIndicator(
                  value: ((sys?.fanSpeedPercent ?? 0) / 100).clamp(0.0, 1.0),
                  minHeight: 6.h,
                  color: AppColors.cyan,
                  backgroundColor: AppColor.divider(context),
                ),
              ),
              SizedBox(height: 6.h),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_fmt1(sys?.fanSpeedPercent)} %',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cyan,
                  ),
                ),
              ),
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
