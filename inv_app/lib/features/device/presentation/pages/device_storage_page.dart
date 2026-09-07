import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 储能 BMS 页面
///
/// 数据源：GET /devices/by-sn/:sn/realtime 的 bms 组（储能 BMS PC485 链路，
/// 45 字段，见 docs/design/储能BMS遥测扩展协议设计.md §7.7）。
/// 布局对标主流储能监控：SOC 仪表盘 → 指标网格 → 电芯电压柱状图 → 温度 → 告警。
class DeviceStoragePage extends StatefulWidget {
  final String sn;

  const DeviceStoragePage({super.key, required this.sn});

  @override
  State<DeviceStoragePage> createState() => _DeviceStoragePageState();
}

class _DeviceStoragePageState extends State<DeviceStoragePage> {
  BmsData? _bms;
  Map<String, dynamic> _bat = {};
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio
          .get('/devices/by-sn/${widget.sn}/realtime')
          .timeout(const Duration(seconds: 10));
      final body = res.data is Map ? res.data as Map : const {};
      final payload = body['data'] is Map ? body['data'] as Map : body;
      final rt = payload['realtime'] is Map ? payload['realtime'] as Map : const {};
      dynamic group(String key) {
        final g = rt[key];
        if (g is Map && g['data'] is Map) return g['data'];
        return g is Map ? g : null;
      }

      final bmsRaw = group('bms');
      if (!mounted) return;
      setState(() {
        _bms = bmsRaw == null ? null : BmsData.fromJson(Map<String, dynamic>.from(bmsRaw));
        final batRaw = group('bat');
        _bat = batRaw == null ? const {} : Map<String, dynamic>.from(batRaw);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _t(String key) => AppLocalizations.of(context)!.str(key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surfaceContainer(context),
      appBar: AppBar(
        title: Text(_t('storage_title'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _fetch),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildEmpty(_t('storage_load_failed'))
              : _buildBody(),
    );
  }

  Widget _buildEmpty(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.battery_alert_rounded, size: 56.w, color: Colors.grey),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14.sp, color: AppColors.textSecondary,),),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final bms = _bms;
    if (bms == null) {
      return _buildEmpty(_t('storage_not_connected'));
    }
    if (!bms.online) {
      return _buildEmpty(_t('storage_bms_offline'));
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: EdgeInsets.all(12.w),
        children: [
          _statusHeader(bms),
          SizedBox(height: 12.h),
          _metricsRow(bms),
          SizedBox(height: 12.h),
          _capacityCard(bms),
          SizedBox(height: 12.h),
          _cellChartCard(bms),
          SizedBox(height: 12.h),
          _tempCard(bms),
          SizedBox(height: 12.h),
          _switchAndAlarmCard(bms),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  /* ── 状态头：SOC 仪表盘 + 工作模式 ── */
  Widget _statusHeader(BmsData bms) {
    final mode = _workModeLabel(bms.workMode);
    final socColor = bms.soc <= 15 ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColor.surface(context),
        borderRadius: BorderRadius.circular(16.w),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            height: 120.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120.w,
                  height: 120.w,
                  child: CircularProgressIndicator(
                    value: (bms.soc / 100).clamp(0.0, 1.0),
                    strokeWidth: 10.w,
                    backgroundColor: Colors.grey.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(socColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${bms.soc.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,),),
                    const Text('SOC',
                        style: TextStyle(fontSize: 11, color: Colors.grey),),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 20.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: mode.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                  child: Text(mode.$1,
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: mode.$2,),),
                ),
                SizedBox(height: 10.h),
                Text('SOH ${bms.soh.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,),),
                SizedBox(height: 4.h),
                Text('${_t('storage_cycle_count')}: ${bms.cycleCount}',
                    style: TextStyle(
                        fontSize: 13.sp, color: AppColors.textSecondary,),),
                if (bms.cellVoltageDiff > 50)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text('${_t('storage_diff')}: ${bms.cellVoltageDiff} mV',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFFF59E0B),),),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _workModeLabel(int mode) {
    switch (mode) {
      case 1:
        return (_t('storage_charging'), const Color(0xFF22C55E));
      case 2:
        return (_t('storage_discharging'), const Color(0xFFF59E0B));
      case 3:
        return (_t('storage_init'), const Color(0xFF3B82F6));
      case 4:
        return (_t('storage_recharge'), const Color(0xFF8B5CF6));
      default:
        return (_t('storage_idle'), Colors.grey);
    }
  }

  /* ── 指标行：总压 / 电流 / 充 / 放功率 ── */
  Widget _metricsRow(BmsData bms) {
    final v = _bat['battery_voltage'] is num ? (_bat['battery_voltage'] as num).toDouble() : 0.0;
    final i = _bat['battery_current'] is num ? (_bat['battery_current'] as num).toDouble() : 0.0;
    final chg = _bat['battery_charge_power'] is num
        ? (_bat['battery_charge_power'] as num).toDouble()
        : 0.0;
    final dsg = _bat['battery_discharge_power'] is num
        ? (_bat['battery_discharge_power'] as num).toDouble()
        : 0.0;
    String kw(num w) => w >= 1000 ? '${(w / 1000).toStringAsFixed(2)} kW' : '${w.toStringAsFixed(0)} W';
    return Row(
      children: [
        _metricCell(_t('storage_pack_voltage'), '${v.toStringAsFixed(2)} V'),
        _metricCell(_t('storage_current'), '${i.toStringAsFixed(1)} A'),
        _metricCell(_t('storage_charge_power'), kw(chg)),
        _metricCell(_t('storage_discharge_power'), kw(dsg)),
      ],
    );
  }

  Widget _metricCell(String label, String value) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: 8.w),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: AppColor.surface(context),
          borderRadius: BorderRadius.circular(12.w),
        ),
        child: Column(
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),),
            SizedBox(height: 4.h),
            Text(value,
                style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,),),
          ],
        ),
      ),
    );
  }

  /* ── 容量卡：剩余/满充/额定 + 充电请求 ── */
  Widget _capacityCard(BmsData bms) {
    final pct = bms.capacityDesign > 0
        ? (bms.capacityRemain / bms.capacityDesign * 100).clamp(0.0, 100.0)
        : 0.0;
    return _card(
      _t('storage_capacity'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: pct / 100,
            minHeight: 8.h,
            borderRadius: BorderRadius.circular(4.w),
            backgroundColor: Colors.grey.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _kv(_t('storage_remain_capacity'), '${bms.capacityRemain.toStringAsFixed(1)} Ah'),
              _kv(_t('storage_full_capacity'), '${bms.capacityFull.toStringAsFixed(1)} Ah'),
              _kv(_t('storage_design_capacity'), '${bms.capacityDesign.toStringAsFixed(1)} Ah'),
            ],
          ),
          SizedBox(height: 8.h),
          _kv(_t('storage_charge_request'),
              '${bms.chgRequestCurrent.toStringAsFixed(1)} A / ${bms.chgRequestVoltage.toStringAsFixed(1)} V',),
        ],
      ),
    );
  }

  /* ── 电芯电压柱状图 ── */
  Widget _cellChartCard(BmsData bms) {
    final cells = bms.cellVoltages;
    final valid = cells.where((v) => v > 0).toList();
    final vMax = valid.isEmpty ? 0.0 : valid.reduce((a, b) => a > b ? a : b);
    final vMin = valid.isEmpty ? 0.0 : valid.reduce((a, b) => a < b ? a : b);
    final balancingCount = List<int>.generate(16, (i) => i)
        .where((i) => (bms.balanceBitmap >> i) & 1 == 1 && i < cells.length && cells[i] > 0)
        .length;

    return _card(
      '${_t('storage_cell_voltages')}  Δ${bms.cellVoltageDiff.toStringAsFixed(0)} mV'
      '${balancingCount > 0 ? '  ⚡$balancingCount' : ''}',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190.h,
            child: valid.isEmpty
                ? Center(
                    child: Text(_t('storage_no_data'),
                        style: TextStyle(fontSize: 13.sp, color: Colors.grey),),)
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      minY: (vMin - 30).clamp(0.0, 9999.0),
                      maxY: vMax + 30,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(),
                        rightTitles: AxisTitles(),
                        topTitles: AxisTitles(),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => const Color(0xE6111827),
                          getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                              '${_t('storage_cell')} ${group.x + 1}: ${rod.toY.toStringAsFixed(0)} mV',
                              const TextStyle(color: Colors.white, fontSize: 11),),
                        ),
                      ),
                      barGroups: List.generate(cells.length, (i) {
                        final v = cells[i];
                        final isMax = v > 0 && v == vMax;
                        final isMin = v > 0 && v == vMin;
                        return BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: v > 0 ? v : 0,
                            width: 13.w,
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(3.w)),
                            color: isMax
                                ? const Color(0xFFEF4444)
                                : isMin
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF22C55E),
                          ),
                        ],);
                      }),
                    ),
                  ),
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 12.w,
            children: [
              _legendDot(const Color(0xFFEF4444), _t('storage_max')),
              _legendDot(const Color(0xFF3B82F6), _t('storage_min')),
              _legendDot(const Color(0xFF22C55E), _t('storage_cell')),
              if (balancingCount > 0)
                _legendDot(const Color(0xFFF59E0B), _t('storage_balancing')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8.w, height: 8.w,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),),
      SizedBox(width: 4.w),
      Text(label,
          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),),
    ],);
  }

  /* ── 温度 ── */
  Widget _tempCard(BmsData bms) {
    Color tempColor(double v) {
      if (v == 0) return Colors.grey;
      if (v >= 55) return const Color(0xFFEF4444);
      if (v >= 45) return const Color(0xFFF59E0B);
      if (v <= 0) return const Color(0xFF3B82F6);
      return const Color(0xFF22C55E);
    }

    Widget chip(String label, double v) {
      return Expanded(
        child: Container(
          margin: EdgeInsets.only(right: 8.w),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: AppColor.surface(context),
            borderRadius: BorderRadius.circular(12.w),
          ),
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.sp, color: AppColors.textSecondary,),),
              SizedBox(height: 4.h),
              Text(v == 0 ? '--' : '${v.toStringAsFixed(1)}°C',
                  style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: tempColor(v),),),
            ],
          ),
        ),
      );
    }

    return _card(
      _t('storage_temps'),
      Row(
        children: [
          chip(_t('storage_cell_temp_max'), bms.cellTempMax),
          chip(_t('storage_cell_temp_min'), bms.cellTempMin),
          chip('MOS', bms.mosTemp),
          chip(_t('storage_env_temp'), bms.envTemp),
          chip('PCB', bms.pcbTemp),
        ],
      ),
    );
  }

  /* ── MOS 状态 + 告警/故障 ── */
  Widget _switchAndAlarmCard(BmsData bms) {
    final alarms = <Widget>[];
    // 故障位图（bit 序与 BMS pack_info fault_status 一致，见设计文档 §7.4）
    const faultDefs = {
      0: 'storage_fault_sc', 1: 'storage_fault_reverse',
      2: 'storage_fault_ntc_break', 3: 'storage_fault_wire_break',
      4: 'storage_fault_afe_comm', 5: 'storage_fault_chg_mos_fault',
      6: 'storage_fault_dsg_mos_fault', 7: 'storage_fault_fan_low',
      8: 'storage_fault_fan_stall', 24: 'storage_fault_lock',
    };
    faultDefs.forEach((bit, key) {
      if ((bms.faultStatus >> bit) & 1 == 1) {
        alarms.add(_alarmChip(_t(key), Colors.red));
      }
    });
    // 告警等级字 w0/w1/w2：每类 2bit（0-3 级）
    const alarmDefs = [
      [0, 0, 'storage_alarm_cell_ov'], [0, 1, 'storage_alarm_pack_ov'],
      [0, 2, 'storage_alarm_chg_oc'], [0, 3, 'storage_alarm_chg_ot'],
      [0, 4, 'storage_alarm_chg_ut'], [1, 0, 'storage_alarm_cell_uv'],
      [1, 1, 'storage_alarm_pack_uv'], [1, 2, 'storage_alarm_dsg_oc'],
      [1, 3, 'storage_alarm_dsg_ot'], [1, 4, 'storage_alarm_dsg_ut'],
      [1, 5, 'storage_alarm_soc_low'], [2, 0, 'storage_alarm_env_ot'],
      [2, 1, 'storage_alarm_env_ut'], [2, 2, 'storage_alarm_pcb_ot'],
      [2, 3, 'storage_alarm_pcb_ut'], [3, 0, 'storage_alarm_mos_ot'],
      [3, 1, 'storage_alarm_mos_ut'], [4, 0, 'storage_alarm_dv'],
      [4, 1, 'storage_alarm_dt'],
    ];
    final words = [bms.alarmW0, bms.alarmW1, bms.alarmW2];
    for (final def in alarmDefs) {
      final word = def[0] as int;
      final bit = def[1] as int;
      final key = def[2] as String;
      final level = (words[word] >> (bit * 2)) & 0x3;
      if (level > 0) {
        alarms.add(_alarmChip(
            '${_t(key)} L$level',
            level >= 3
                ? Colors.deepOrange
                : level == 2
                    ? Colors.orange
                    : Colors.amber,),);
      }
    }

    return _card(
      _t('storage_alarms'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _mosChip(_t('storage_charge_mos'), (bms.mosStatus & 0x01) == 1),
              SizedBox(width: 8.w),
              _mosChip(_t('storage_discharge_mos'), (bms.mosStatus & 0x02) == 1),
            ],
          ),
          SizedBox(height: 10.h),
          alarms.isEmpty
              ? Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF22C55E), size: 18,),
                  SizedBox(width: 6.w),
                  Text(_t('storage_no_alarms'),
                      style: TextStyle(
                          fontSize: 13.sp, color: const Color(0xFF22C55E),),),
                ],)
              : Wrap(spacing: 8.w, runSpacing: 8.h, children: alarms),
        ],
      ),
    );
  }

  Widget _mosChip(String label, bool on) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: on
            ? const Color(0xFF22C55E).withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.w),
      ),
      child: Text('$label ${on ? _t('storage_on') : _t('storage_off')}',
          style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: on ? const Color(0xFF16A34A) : Colors.grey,),),
    );
  }

  Widget _alarmChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.w),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12.sp, fontWeight: FontWeight.w600, color: color,),),
    );
  }

  /* ── 通用卡片 ── */
  Widget _card(String title, Widget child) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surface(context),
        borderRadius: BorderRadius.circular(16.w),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,),),
          SizedBox(height: 10.h),
          child,
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),),
        SizedBox(height: 2.h),
        Text(value,
            style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,),),
      ],
    );
  }
}
