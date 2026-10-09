import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/bms_summary.dart';
import 'package:inv_app/core/utils/realtime_payload.dart';
import 'package:inv_app/core/utils/device_card_data.dart';
import 'package:inv_app/features/device/presentation/widgets/bms_summary_view.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 储能 BMS 页面
///
/// 数据源：GET /devices/by-sn/:sn/realtime，优先展示 ARM CMD08 的
/// bms_summary（100 字节完整快照、UTC 有效期）。缺少新组时仍使用原
/// bms 组及原有 45 字段 PC485 页面，不混用两种协议的状态位。
class DeviceStoragePage extends StatefulWidget {
  final String sn;

  const DeviceStoragePage({super.key, required this.sn});

  @override
  State<DeviceStoragePage> createState() => _DeviceStoragePageState();
}

class _DeviceStoragePageState extends State<DeviceStoragePage> {
  BmsData? _bms;
  BmsSummary? _summary;
  Map<String, dynamic> _bat = {};
  Map<String, dynamic> _bmsFields = {};
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
      final rt =
          payload['realtime'] is Map ? payload['realtime'] as Map : payload;
      dynamic group(String key) {
        final g = rt[key];
        if (g is Map && g['data'] is Map) return g['data'];
        return g is Map ? g : null;
      }

      final bmsRaw = group('bms') ?? (rt.containsKey('bms_online') ? rt : null);
      final summaryRaw = group('bms_summary');
      if (!mounted) return;
      setState(() {
        _summary = summaryRaw == null
            ? null
            : BmsSummary.fromJson(Map<String, dynamic>.from(summaryRaw));
        _bms = bmsRaw == null
            ? null
            : BmsData.fromJson(Map<String, dynamic>.from(bmsRaw));
        _bmsFields =
            bmsRaw == null ? const {} : Map<String, dynamic>.from(bmsRaw);
        _bat = normalizeRealtimePayload(Map<String, dynamic>.from(rt));
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

  String _value(Map<String, dynamic> fields, String key, String unit,
      {int decimals = 1}) {
    final value = deviceNumber(fields[key]);
    return value == null ? '--' : '${value.toStringAsFixed(decimals)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surfaceContainer(context),
      appBar: AppBar(
        title: Text(
          _t('storage_title'),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17.sp),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
        actions: [
          IconButton(
            tooltip: _t('storage_bms_refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _summary == null
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
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final summary = _summary;
    if (summary != null) {
      return BmsSummaryView(
        summary: summary,
        onRefresh: _fetch,
        refreshFailed: _error != null,
      );
    }
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
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
        children: [
          Text('SN ${widget.sn}',
              style: TextStyle(
                  fontSize: 12.sp, color: AppColor.textSecondary(context))),
          SizedBox(height: 16.h),
          _statusHeader(bms),
          SizedBox(height: 12.h),
          _metricsRow(bms),
          SizedBox(height: 12.h),
          _switchAndAlarmCard(bms),
          SizedBox(height: 20.h),
          _cellChartCard(bms),
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(_t('storage_summary_technical'),
                  style:
                      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              children: [
                _capacityCard(bms),
                SizedBox(height: 20.h),
                _tempCard(bms)
              ]),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  /* ── 状态头：SOC 仪表盘 + 工作模式 ── */
  Widget _statusHeader(BmsData bms) {
    final mode = _bmsFields['bms_battery_work_mode'] == null
        ? (_t('storage_bms_operating_unknown'), Colors.grey)
        : _workModeLabel(bms.workMode);
    final socColor =
        bms.soc <= 15 ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          SizedBox(
            width: 96.w,
            height: 96.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 96.w,
                  height: 96.w,
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
                    SizedBox(
                        width: 76.w,
                        child: FittedBox(
                            child: Text(
                          _value(_bmsFields, 'bms_soc', '%'),
                          style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColor.textPrimary(context),
                          ),
                        ))),
                    const Text(
                      'SOC',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
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
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: mode.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                  child: Text(
                    mode.$1,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: mode.$2,
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  'SOH ${_value(_bmsFields, 'bms_soh', '%')}',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textPrimary(context),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  '${_t('storage_cycle_count')}: ${_value(_bmsFields, 'bms_cycle_count', '', decimals: 0).trim()}',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textSecondary(context),
                  ),
                ),
                if (bms.cellVoltageDiff > 50)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(
                      '${_t('storage_diff')}: ${bms.cellVoltageDiff} mV',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
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
      case 0:
        return (_t('storage_idle'), Colors.grey);
      default:
        return (_t('storage_bms_operating_unknown'), Colors.grey);
    }
  }

  /* ── 指标行：总压 / 电流 / 充 / 放功率 ── */
  Widget _metricsRow(BmsData bms) {
    final v = deviceNumber(_bat['battery_voltage']);
    final i = deviceNumber(_bat['battery_current']);
    return LayoutBuilder(
        builder: (context, constraints) => Wrap(
              spacing: 16,
              runSpacing: 18,
              children: [
                SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: _metricCell(_t('storage_pack_voltage'),
                        _value(_bat, 'battery_voltage', 'V', decimals: 2))),
                SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: _metricCell(_t('storage_current'),
                        _value(_bat, 'battery_current', 'A'))),
                SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: _metricCell(
                        _t('storage_summary_power'),
                        v == null || i == null
                            ? '--'
                            : devicePowerLabel(v * i))),
                SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: _metricCell(
                        _t('storage_diff'),
                        _value(_bmsFields, 'bms_cell_voltage_diff', 'mV',
                            decimals: 0))),
              ],
            ));
  }

  Widget _metricCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12.sp, color: AppColor.textSecondary(context)),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: AppColor.textPrimary(context),
          ),
        ),
      ],
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
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _kv(_t('storage_remain_capacity'),
                  _value(_bmsFields, 'bms_capacity_remain', 'Ah')),
              _kv(_t('storage_full_capacity'),
                  _value(_bmsFields, 'bms_capacity_full', 'Ah')),
              _kv(_t('storage_design_capacity'),
                  _value(_bmsFields, 'bms_capacity_design', 'Ah')),
              _kv(_t('storage_charge_power'),
                  _value(_bat, 'battery_charge_power', 'W')),
              _kv(_t('storage_discharge_power'),
                  _value(_bat, 'battery_discharge_power', 'W')),
            ],
          ),
          SizedBox(height: 8.h),
          _kv(
            _t('storage_charge_request'),
            '${_value(_bmsFields, 'bms_chg_request_current', 'A')} / ${_value(_bmsFields, 'bms_chg_request_voltage', 'V')}',
          ),
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
        .where((i) =>
            (bms.balanceBitmap >> i) & 1 == 1 &&
            i < cells.length &&
            cells[i] > 0)
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
                    child: Text(
                      _t('storage_no_data'),
                      style: TextStyle(fontSize: 13.sp, color: Colors.grey),
                    ),
                  )
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
                          getTooltipItem: (group, gi, rod, ri) =>
                              BarTooltipItem(
                            '${_t('storage_cell')} ${group.x + 1}: ${rod.toY.toStringAsFixed(0)} mV',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                      barGroups: List.generate(cells.length, (i) {
                        final v = cells[i];
                        final isMax = v > 0 && v == vMax;
                        final isMin = v > 0 && v == vMin;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: v > 0 ? v : 0,
                              width: 13.w,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(3.w)),
                              color: isMax
                                  ? const Color(0xFFEF4444)
                                  : isMin
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF22C55E),
                            ),
                          ],
                        );
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.w,
          height: 8.w,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 4.w),
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /* ── 温度 ── */
  Widget _tempCard(BmsData bms) {
    return _card(
      _t('storage_temps'),
      Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          _kv(_t('storage_cell_temp_max'),
              _value(_bmsFields, 'bms_cell_temp_max', '°C')),
          _kv(_t('storage_cell_temp_min'),
              _value(_bmsFields, 'bms_cell_temp_min', '°C')),
          _kv('MOS', _value(_bmsFields, 'bms_mos_temp', '°C')),
          _kv(_t('storage_env_temp'), _value(_bmsFields, 'bms_env_temp', '°C')),
          _kv('PCB', _value(_bmsFields, 'bms_pcb_temp', '°C')),
        ],
      ),
    );
  }

  /* ── MOS 状态 + 告警/故障 ── */
  Widget _switchAndAlarmCard(BmsData bms) {
    final alarms = <Widget>[];
    // 故障位图（bit 序与 BMS pack_info fault_status 一致，见设计文档 §7.4）
    const faultDefs = {
      0: 'storage_fault_sc',
      1: 'storage_fault_reverse',
      2: 'storage_fault_ntc_break',
      3: 'storage_fault_wire_break',
      4: 'storage_fault_afe_comm',
      5: 'storage_fault_chg_mos_fault',
      6: 'storage_fault_dsg_mos_fault',
      7: 'storage_fault_fan_low',
      8: 'storage_fault_fan_stall',
      24: 'storage_fault_lock',
    };
    faultDefs.forEach((bit, key) {
      if ((bms.faultStatus >> bit) & 1 == 1) {
        alarms.add(_alarmChip(_t(key), Colors.red));
      }
    });
    // 告警等级字 w0/w1/w2：每类 2bit（0-3 级）
    const alarmDefs = [
      [0, 0, 'storage_alarm_cell_ov'],
      [0, 1, 'storage_alarm_pack_ov'],
      [0, 2, 'storage_alarm_chg_oc'],
      [0, 3, 'storage_alarm_chg_ot'],
      [0, 4, 'storage_alarm_chg_ut'],
      [0, 5, 'storage_alarm_cell_uv'],
      [0, 6, 'storage_alarm_pack_uv'],
      [0, 7, 'storage_alarm_dsg_oc'],
      [1, 0, 'storage_alarm_dsg_ot'],
      [1, 1, 'storage_alarm_dsg_ut'],
      [1, 2, 'storage_alarm_soc_low'],
      [1, 3, 'storage_alarm_env_ot'],
      [1, 4, 'storage_alarm_env_ut'],
      [1, 5, 'storage_alarm_pcb_ot'],
      [1, 6, 'storage_alarm_pcb_ut'],
      [1, 7, 'storage_alarm_mos_ot'],
      [2, 0, 'storage_alarm_mos_ut'],
      [2, 1, 'storage_alarm_dv'],
      [2, 2, 'storage_alarm_dt'],
    ];
    final words = [bms.alarmW0, bms.alarmW1, bms.alarmW2];
    for (final def in alarmDefs) {
      final word = def[0] as int;
      final bit = def[1] as int;
      final key = def[2] as String;
      final level = (words[word] >> (bit * 2)) & 0x3;
      if (level > 0) {
        alarms.add(
          _alarmChip(
            '${_t(key)} L$level',
            level >= 3
                ? Colors.deepOrange
                : level == 2
                    ? Colors.orange
                    : Colors.amber,
          ),
        );
      }
    }

    return _card(
      _t('storage_alarms'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _mosChip(
                  _t('storage_charge_mos'),
                  _bmsFields['bms_mos_status'] == null
                      ? null
                      : (bms.mosStatus & 0x01) == 1),
              _mosChip(
                  _t('storage_discharge_mos'),
                  _bmsFields['bms_mos_status'] == null
                      ? null
                      : (bms.mosStatus & 0x02) == 1),
            ],
          ),
          SizedBox(height: 10.h),
          alarms.isEmpty
              ? Row(
                  children: [
                    Icon(
                      [
                        'bms_fault_status',
                        'bms_alarm_w0',
                        'bms_alarm_w1',
                        'bms_alarm_w2'
                      ].every((key) => _bmsFields[key] != null)
                          ? Icons.check_circle_rounded
                          : Icons.help_outline,
                      color: AppColor.textSecondary(context),
                      size: 18,
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                        child: Text(
                      [
                        'bms_fault_status',
                        'bms_alarm_w0',
                        'bms_alarm_w1',
                        'bms_alarm_w2'
                      ].every((key) => _bmsFields[key] != null)
                          ? _t('storage_no_alarms')
                          : _t('storage_bms_flags_unknown'),
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColor.textSecondary(context),
                      ),
                    )),
                  ],
                )
              : Wrap(spacing: 8.w, runSpacing: 8.h, children: alarms),
        ],
      ),
    );
  }

  Widget _mosChip(String label, bool? on) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: on == true
            ? const Color(0xFF22C55E).withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.w),
      ),
      child: Text(
        '$label ${on == null ? '--' : on ? _t('storage_on') : _t('storage_off')}',
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: on == true ? const Color(0xFF16A34A) : Colors.grey,
        ),
      ),
    );
  }

  Widget _alarmChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.w),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /* ── 通用卡片 ── */
  Widget _card(String title, Widget child) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColor.border(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
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
        Text(
          label,
          style: TextStyle(
              fontSize: 11.sp, color: AppColor.textSecondary(context)),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: AppColor.textPrimary(context),
          ),
        ),
      ],
    );
  }
}
