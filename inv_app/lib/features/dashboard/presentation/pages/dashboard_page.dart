import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/device_model_field.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/widgets/power_gauge.dart';
import 'package:inv_app/core/widgets/status_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/animated_value.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DashboardPage extends StatefulWidget {
  final InverterRealtime? data;
  final bool isOnline;
  final VoidCallback? onRefresh;
  final List<DeviceModelField>? fields;

  const DashboardPage({
    super.key,
    this.data,
    this.isOnline = false,
    this.onRefresh,
    this.fields,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _lastUpdate = '';
  List<DeviceModelField>? _autoFields;

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
    _fetchFieldsIfNeeded();
  }

  void _fetchFieldsIfNeeded() {
    if (widget.fields != null) return;
    final model = widget.data?.deviceInfo?.model;
    if (model == null || model.isEmpty) return;
    _fetchModelFields(model);
  }

  Future<void> _fetchModelFields(String modelCode) async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/models/by-code/$modelCode/fields');
      if (res.statusCode == 200 && mounted) {
        final data = res.data;
        List? list;
        if (data is Map) list = data['data'] ?? data['items'];
        if (list is List && list.isNotEmpty) {
          final fields = list
              .map((e) => DeviceModelField.fromJson(e as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              _autoFields = fields;
            });
          }
        }
      }
    } catch (_) {}
  }

  List<DeviceModelField>? get _effectiveFields => widget.fields ?? _autoFields;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
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
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data?.deviceInfo?.model ?? data?.deviceSN ?? '--',
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
                  status: widget.isOnline
                      ? 1
                      : (data?.sysStatus?.faultCode != 0 ? 2 : 0),
                  label: '',
                ),
                SizedBox(width: 8.w),
                Text(
                  widget.isOnline
                      ? (data?.sysStatus?.state ?? l10n.online)
                      : l10n.offline,
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
              '${l10n.lastUpdate} $_lastUpdate',
              style:
                  TextStyle(fontSize: 11.sp, color: AppColor.outline(context)),
            ),
            SizedBox(height: 4.h),
            Text(
              data?.deviceSN ?? '',
              style:
                  TextStyle(fontSize: 12.sp, color: AppColor.outline(context)),
            ),
          ],
        ),
      ],
    );
  }

  /// Hero section with power gauge and gradient background.
  Widget _buildPowerHero(BuildContext context, InverterRealtime? data) {
    final l10n = AppLocalizations.of(context)!;
    final activePower = (data?.ac?.power ?? 0) / 1000.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 24.w, horizontal: 20.w),
      decoration: AppColor.heroCard(context),
      child: Column(
        children: [
          Text(
            l10n.acOutputPower,
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
    final l10n = AppLocalizations.of(context)!;
    final loadPercent = data?.ac?.loadPercent ?? 0;
    final frequency = data?.ac?.frequency ?? 0;
    final pf = data?.ac?.pf ?? 0;

    return Row(
      children: [
        _quickStatChip(
            context,
            l10n.loadRate,
            '${loadPercent.toStringAsFixed(1)}%',
            Icons.speed,
            AppColors.success),
        SizedBox(width: 8.w),
        _quickStatChip(
            context,
            l10n.frequency,
            '${frequency.toStringAsFixed(1)}Hz',
            Icons.electrical_services,
            AppColors.warning),
        SizedBox(width: 8.w),
        _quickStatChip(
            context, 'PF', pf.toStringAsFixed(2), Icons.tune, AppColors.blue),
      ],
    );
  }

  Widget _quickStatChip(BuildContext context, String label, String value,
      IconData icon, Color color) {
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
              style:
                  TextStyle(fontSize: 10.sp, color: AppColor.outline(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// All data sections - uses dynamic fields if available, otherwise hardcoded.
  Widget _buildDataSection(BuildContext context, InverterRealtime? data) {
    if (_effectiveFields != null && _effectiveFields!.isNotEmpty) {
      return _buildDynamicSections(context, data);
    }
    return _buildStaticSections(context, data);
  }

  List<Map<String, dynamic>> _getDynamicSectionDefs(AppLocalizations l10n) => [
        {
          'title': l10n.acOutput,
          'icon': Icons.power,
          'color': AppColors.success,
          'prefix': 'ac_'
        },
        {
          'title': l10n.batteryBms,
          'icon': Icons.battery_charging_full,
          'color': AppColors.success,
          'prefix': 'batt_'
        },
        {
          'title': l10n.pvMppt,
          'icon': Icons.wb_sunny,
          'color': AppColors.orange,
          'prefix': 'pv_'
        },
        {
          'title': l10n.loadLabel,
          'icon': Icons.home,
          'color': AppColors.blue,
          'prefix': 'load_'
        },
        {
          'title': l10n.electricMeter,
          'icon': Icons.electric_meter,
          'color': AppColors.warning,
          'prefix': 'meter_'
        },
        {
          'title': l10n.energyStatsLabel,
          'icon': Icons.battery_charging_full,
          'color': AppColors.primary,
          'prefix': 'energy_'
        },
        {
          'title': l10n.systemStatusLabel,
          'icon': Icons.info_outline,
          'color': AppColors.primary,
          'prefix': 'sys_'
        },
      ];

  Widget _buildDynamicSections(BuildContext context, InverterRealtime? data) {
    final l10n = AppLocalizations.of(context)!;
    final fields = _effectiveFields!;
    final realtimeMap = _buildRealtimeMapForFields(data);

    final widgets = <Widget>[];

    for (final def in _getDynamicSectionDefs(l10n)) {
      final prefix = def['prefix'] as String;
      final sectionFields = fields
          .where((f) => f.isShow && f.fieldKey.startsWith(prefix))
          .toList()
        ..sort((a, b) => a.sort.compareTo(b.sort));

      if (sectionFields.isNotEmpty) {
        if (widgets.isNotEmpty) widgets.add(_divider(context));
        widgets.add(
          _sectionHeader(
            context,
            def['title'] as String,
            def['icon'] as IconData,
            def['color'] as Color,
          ),
        );
        final items = sectionFields.map((f) {
          final val = realtimeMap[f.fieldKey];
          return _dataItem(f.fieldName, _fmtValue(val, f.fieldType, f.unit),
              def['color'] as Color);
        }).toList();
        widgets.add(_dataGrid(context, items));
      }
    }

    return Container(
      decoration: AppColor.card(context),
      child: Column(children: widgets),
    );
  }

  Map<String, dynamic> _buildRealtimeMapForFields(InverterRealtime? data) {
    final map = <String, dynamic>{};
    if (data == null) return map;

    map['load_power'] = data.loadPower;

    if (data.ac != null) {
      map.addAll({
        'ac_voltage': data.ac!.voltage,
        'ac_current': data.ac!.current,
        'ac_power': data.ac!.power,
        'ac_frequency': data.ac!.frequency,
        'ac_load_percent': data.ac!.loadPercent,
        'ac_pf': data.ac!.pf
      });
    }
    if (data.battery != null) {
      map.addAll({
        'batt_soc': data.battery!.soc,
        'batt_soh': data.battery!.soh,
        'batt_voltage': data.battery!.voltage,
        'batt_current': data.battery!.current,
        'batt_charge_state': data.battery!.chargeState
      });
    }
    if (data.pv != null) {
      map.addAll({
        'pv_voltage': data.pv!.pvVoltage,
        'pv_current': data.pv!.pvCurrent,
        'pv_power': data.pv!.pvPower,
        'mppt_state': data.pv!.mpptState
      });
    }
    if (data.sysStatus != null) {
      map.addAll({
        'state': data.sysStatus!.state,
        'fault_code': data.sysStatus!.faultCode,
        'alarm_code': data.sysStatus!.alarmCode,
        'temp_inv': data.sysStatus!.tempInv,
        'temp_mos': data.sysStatus!.tempMos,
        'efficiency': data.sysStatus!.efficiency
      });
    }
    if (data.energy != null) {
      map.addAll({
        'daily_pv': data.energy!.dailyPV,
        'total_pv': data.energy!.totalPV,
        'runtime_hours': data.energy!.runtimeHours,
        'daily_feed_energy': data.energy!.dailyFeedEnergy,
        'total_feed_energy': data.energy!.totalFeedEnergy,
        'daily_grid_import': data.energy!.dailyGridImport,
        'total_grid_import': data.energy!.totalGridImport
      });
    }
    if (data.meter != null) {
      map.addAll({
        'meter_total_power': data.meter!.totalPower,
        'meter_phase_a_power': data.meter!.phaseAPower,
        'meter_phase_b_power': data.meter!.phaseBPower,
        'meter_phase_c_power': data.meter!.phaseCPower
      });
    }
    return map;
  }

  String _fmtValue(dynamic val, String fieldType, String unit) {
    if (val == null) return '--';
    if (fieldType == 'float' && val is num) {
      final s = val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(1);
      return unit.isNotEmpty ? '$s $unit' : s;
    }
    if (val is double) {
      final s = val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(1);
      return unit.isNotEmpty ? '$s $unit' : s;
    }
    return unit.isNotEmpty ? '$val $unit' : '$val';
  }

  /// Original hardcoded sections - used as fallback.
  Widget _buildStaticSections(BuildContext context, InverterRealtime? data) {
    final l10n = AppLocalizations.of(context)!;
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
            _sectionHeader(context, l10n.batteryBms,
                Icons.battery_charging_full, AppColors.success),
            _dataGrid(context, [
              _dataItem(
                  'SOC', '${batt.soc.toStringAsFixed(1)}%', AppColors.success),
              _dataItem(l10n.voltage, '${batt.voltage.toStringAsFixed(1)}V',
                  AppColors.blue),
              _dataItem(l10n.current, '${batt.current.toStringAsFixed(2)}A',
                  AppColors.warning),
              _dataItem(
                  'SOH', '${batt.soh.toStringAsFixed(1)}%', AppColors.teal),
              _dataItem(
                  l10n.chargeDischargeStatus, batt.chargeState, AppColors.teal),
            ]),
          ],

          // PV MPPT
          if (pv != null) ...[
            _divider(context),
            _sectionHeader(
                context, l10n.pvMppt, Icons.wb_sunny, AppColors.orange,
                trailing: pv.mpptState),
            _dataGrid(context, [
              _dataItem(l10n.pvVoltage, '${pv.pvVoltage.toStringAsFixed(1)}V',
                  AppColors.orange),
              _dataItem(l10n.pvCurrent, '${pv.pvCurrent.toStringAsFixed(2)}A',
                  AppColors.warning),
              _dataItem(
                  l10n.pvPower,
                  '${(pv.pvPower / 1000).toStringAsFixed(2)}kW',
                  AppColors.success),
            ]),
          ],

          // AC Output
          if (ac != null) ...[
            _divider(context),
            _sectionHeader(
                context, l10n.acOutput, Icons.power, AppColors.success),
            _dataGrid(context, [
              _dataItem(l10n.voltage, '${ac.voltage.toStringAsFixed(1)}V',
                  AppColors.success),
              _dataItem(l10n.current, '${ac.current.toStringAsFixed(2)}A',
                  AppColors.warning),
              _dataItem(l10n.activePower, '${ac.power.toStringAsFixed(0)}W',
                  AppColors.success),
              _dataItem(l10n.frequency, '${ac.frequency.toStringAsFixed(2)}Hz',
                  AppColors.orange),
              _dataItem(l10n.loadRate, '${ac.loadPercent.toStringAsFixed(1)}%',
                  AppColors.blue),
            ]),
          ],

          // Energy
          if (energy != null) ...[
            _divider(context),
            _sectionHeader(context, l10n.energyStatsLabel,
                Icons.battery_charging_full, AppColors.primary),
            _dataGrid(context, [
              _dataItem(l10n.dailyPvGeneration,
                  '${energy.dailyPV.toStringAsFixed(2)}kWh', AppColors.success),
              _dataItem(l10n.totalPvGeneration,
                  '${energy.totalPV.toStringAsFixed(1)}kWh', AppColors.blue),
              _dataItem(
                  l10n.runningTime, '${energy.runtimeHours}h', AppColors.teal),
            ]),
          ],

          // System Status
          if (sysStatus != null) ...[
            _divider(context),
            _sectionHeader(context, l10n.systemStatusLabel, Icons.info_outline,
                AppColors.primary),
            _statusGrid(context, sysStatus),
          ],

          SizedBox(height: 4.h),
        ],
      ),
    );
  }

  Widget _sectionHeader(
      BuildContext context, String title, IconData icon, Color color,
      {String? trailing}) {
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
          Text(title,
              style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColor.onSurface(context))),
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing,
                style: TextStyle(
                    fontSize: 12.sp, color: AppColor.outline(context))),
          ],
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Divider(
          height: 1, color: AppColor.outline(context).withValues(alpha: 0.15)),
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
  Widget _statusGrid(BuildContext context, SystemStatus sysStatus) {
    final l10n = AppLocalizations.of(context)!;
    final isRunning = sysStatus.state == 'inverting';
    final hasFault = sysStatus.faultCode != 0;
    final hasAlarm = sysStatus.alarmCode != 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _statusCell(context, l10n.workStatus, sysStatus.state,
                      isRunning ? AppColors.success : AppColors.warning)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _statusCell(
                      context,
                      l10n.faultCode,
                      '${sysStatus.faultCode}',
                      hasFault ? AppColors.error : AppColors.success)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _statusCell(
                      context,
                      l10n.alarmCodeLabel,
                      '${sysStatus.alarmCode}',
                      hasAlarm ? AppColors.warning : AppColors.success)),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                  child: _statusCell(
                      context,
                      l10n.efficiency,
                      '${sysStatus.efficiency.toStringAsFixed(1)}%',
                      AppColors.blue)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _statusCell(
                      context,
                      l10n.inverterTemp,
                      '${sysStatus.tempInv.toStringAsFixed(1)}°C',
                      AppColors.warning)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _statusCell(
                      context,
                      l10n.mosTemp,
                      '${sysStatus.tempMos.toStringAsFixed(1)}°C',
                      AppColors.errorLight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCell(
      BuildContext context, String label, String value, Color color) {
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
            style: TextStyle(
                fontSize: 13.sp, fontWeight: FontWeight.w700, color: color),
          ),
          SizedBox(height: 2.h),
          Text(label,
              style:
                  TextStyle(fontSize: 10.sp, color: AppColor.outline(context))),
        ],
      ),
    );
  }

  _DataItem _dataItem(String label, String value, Color color) =>
      _DataItem(label, value, color);
}

class _DataItem {
  final String label;
  final String value;
  final Color color;
  _DataItem(this.label, this.value, this.color);
}
