import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/presentation/widgets/device_guide_card.dart';
import 'package:inv_app/features/device/presentation/widgets/device_settings_group_card.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';

enum _ParameterGroup { solar, battery, output, status }

/// Common parameter overview for Bluetooth and cloud measurements.
class ModbusPanelOverview extends StatefulWidget {
  const ModbusPanelOverview({
    super.key,
    required this.telemetry,
    this.live = true,
    this.model,
  });

  final Map<String, dynamic> telemetry;
  final bool live;
  final String? model;

  @override
  State<ModbusPanelOverview> createState() => _ModbusPanelOverviewState();
}

class _ModbusPanelOverviewState extends State<ModbusPanelOverview> {
  _ParameterGroup? _expanded = _ParameterGroup.solar;

  String _label(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Object? _value(String group, String key) {
    final values = widget.telemetry[group];
    return values is Map ? values[key] : null;
  }

  String _metric(String group, String key, String unit) {
    final value = _value(group, key);
    if (value is! num || !value.isFinite) return '—';
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat('#,##0.##', locale).format(value);
    return unit.isEmpty ? number : '$number $unit';
  }

  String _operatingState() {
    final (zh, en) = switch (_value('sys_status', 'state')) {
      'boot' || 'initializing' => ('启动中', 'Starting'),
      'standby' => ('待机', 'Standby'),
      'grid' => ('市电供电', 'Grid supply'),
      'solar' => ('光伏供电', 'Solar supply'),
      'battery' => ('电池供电', 'Battery supply'),
      'generator' => ('发电机供电', 'Generator supply'),
      'fault' => ('故障', 'Fault'),
      'off' => ('关机', 'Off'),
      'test' => ('测试中', 'Testing'),
      'upgrading' => ('升级中', 'Updating'),
      _ => ('—', '—'),
    };
    return _label(zh, en);
  }

  List<(String, String)> _parameters(_ParameterGroup group) => switch (group) {
        _ParameterGroup.solar => [
            (_label('PV1 电压', 'PV1 voltage'), _metric('pv', 'pv_voltage', 'V')),
            (_label('PV1 电流', 'PV1 current'), _metric('pv', 'pv_current', 'A')),
            if (_value('pv', 'pv2_voltage') != null)
              (
                _label('PV2 电压', 'PV2 voltage'),
                _metric('pv', 'pv2_voltage', 'V')
              ),
            if (_value('pv', 'pv2_current') != null)
              (
                _label('PV2 电流', 'PV2 current'),
                _metric('pv', 'pv2_current', 'A')
              ),
            (_label('今日发电', 'Today'), _metric('energy', 'daily_pv', 'kWh')),
            (_label('累计发电', 'Lifetime'), _metric('energy', 'total_pv', 'kWh')),
          ],
        _ParameterGroup.battery => [
            (
              _label('电池电压', 'Battery voltage'),
              _metric('battery', 'voltage', 'V')
            ),
            (
              _label('电池电流', 'Battery current'),
              _metric('battery', 'current', 'A')
            ),
            (_label('电池功率', 'Battery power'), _metric('battery', 'power', 'W')),
            (
              _label('充放电状态', 'Charge status'),
              switch (_value('battery', 'charge_state')) {
                'charging' => _label('充电中', 'Charging'),
                'discharging' => _label('放电中', 'Discharging'),
                'standby' => _label('空闲', 'Idle'),
                _ => '—',
              },
            ),
          ],
        _ParameterGroup.output => [
            (_label('输出电压', 'Voltage'), _metric('ac', 'voltage', 'V')),
            (_label('输出电流', 'Current'), _metric('ac', 'current', 'A')),
            (_label('输出频率', 'Frequency'), _metric('ac', 'frequency', 'Hz')),
            (_label('负载率', 'Load'), _metric('ac', 'load_percent', '%')),
            if (_value('ac', 'grid_voltage') != null)
              (
                _label('市电电压', 'Grid voltage'),
                _metric('ac', 'grid_voltage', 'V')
              ),
            if (_value('ac', 'input_power') != null)
              (
                _label('市电输入功率', 'Grid input power'),
                _metric('ac', 'input_power', 'W')
              ),
          ],
        _ParameterGroup.status => [
            (_label('运行状态', 'Operating state'), _operatingState()),
            (
              _label('逆变器温度', 'Inverter temperature'),
              _metric('sys_status', 'temp_inv', '°C')
            ),
            (
              _label('故障码', 'Fault code'),
              _metric('sys_status', 'fault_code', '')
            ),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final solarPower = _metric('pv', 'pv_power', 'W');
    final outputPower = _metric('ac', 'power', 'W');
    final soc = _value('battery', 'soc');
    final batteryLevel = soc is num && soc.isFinite && soc >= 0 && soc <= 100
        ? _metric('battery', 'soc', '%')
        : '—';
    final dailyEnergy = _metric('energy', 'daily_pv', 'kWh');
    final operatingState = _operatingState();
    final hasSummary = [
      solarPower,
      outputPower,
      batteryLevel,
      dailyEnergy,
    ].any((value) => value != '—');
    final parameters = {
      for (final group in _ParameterGroup.values) group: _parameters(group),
    };
    final hasReadings = hasSummary ||
        parameters.values.any((rows) => rows.any((row) => row.$2 != '—'));
    final groups = [
      (
        _ParameterGroup.solar,
        _label('光伏', 'Solar'),
        solarPower,
        Icons.wb_sunny_outlined,
        AppColors.orange
      ),
      (
        _ParameterGroup.battery,
        _label('电池', 'Battery'),
        batteryLevel,
        Icons.battery_charging_full_rounded,
        AppColors.teal
      ),
      (
        _ParameterGroup.output,
        _label('交流输出', 'AC output'),
        outputPower,
        Icons.bolt_rounded,
        AppColors.purple
      ),
      (
        _ParameterGroup.status,
        _label('运行状态', 'Operating status'),
        _operatingState(),
        Icons.monitor_heart_outlined,
        AppColors.blue
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeviceGuideCard(
          title: _label('设备运行', 'Device overview'),
          subtitle: widget.model,
          description: !hasReadings
              ? _label('收到逆变器数据后，这里会显示发电、用电和电池状态。',
                  'Generation, output and battery readings appear after the inverter reports data.')
              : !widget.live
                  ? _label('以下是上次收到的读数。', 'Showing the last received readings.')
                  : operatingState == '—'
                      ? null
                      : operatingState,
          illustration: CsergyAssets.xiaoshuoDevice,
          details: hasSummary
              ? _OperatingSummary(
                  dailyLabel: _label('今日发电', 'Generated today'),
                  dailyEnergy: dailyEnergy,
                  readings: [
                    (
                      Icons.wb_sunny_outlined,
                      _label('光伏功率', 'Solar power'),
                      solarPower,
                    ),
                    (
                      Icons.bolt_outlined,
                      _label('输出功率', 'Output power'),
                      outputPower,
                    ),
                    (
                      Icons.battery_charging_full_outlined,
                      _label('电池电量', 'Battery SOC'),
                      batteryLevel,
                    ),
                  ],
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _label('运行参数', 'Operating parameters'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                _label('展开分类查看电压、电流等详细读数。',
                    'Expand a group for voltage, current and other readings.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColor.textSecondary(context),
                    ),
              ),
            ],
          ),
        ),
        for (final (group, title, summary, icon, accent) in groups)
          DeviceSettingsGroupCard(
            title: title,
            summary: summary,
            icon: icon,
            accent: accent,
            expanded: _expanded == group,
            onToggle: () =>
                setState(() => _expanded = _expanded == group ? null : group),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: ModbusPanelMetrics(
                values: parameters[group]!,
                inset: false,
              ),
            ),
          ),
      ],
    );
  }
}

class _OperatingSummary extends StatelessWidget {
  const _OperatingSummary({
    required this.dailyLabel,
    required this.dailyEnergy,
    required this.readings,
  });

  final String dailyLabel;
  final String dailyEnergy;
  final List<(IconData, String, String)> readings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dailyEnergy != '—') ...[
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                dailyEnergy,
                style: text.headlineSmall?.copyWith(
                  color: AppColor.primary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                dailyLabel,
                style: text.bodySmall
                    ?.copyWith(color: AppColor.textSecondary(context)),
              ),
            ],
          ),
          const Divider(height: 22),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 245 ||
                MediaQuery.textScalerOf(context).scale(14) >= 22;
            final items = [
              for (final (icon, label, value) in readings)
                _OperatingReading(
                    icon: icon, label: label, value: value, stacked: stacked),
            ];
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items) Expanded(child: item),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OperatingReading extends StatelessWidget {
  const _OperatingReading({
    required this.icon,
    required this.label,
    required this.value,
    required this.stacked,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = AppColor.textSecondary(context);
    final caption = Row(
      children: [
        Icon(icon, color: AppColor.primary(context), size: 15),
        const SizedBox(width: 5),
        Expanded(
            child: Text(label, style: text.bodySmall?.copyWith(color: muted))),
      ],
    );
    final number = Text(
      value,
      style: text.titleSmall?.copyWith(
        color: value == '—' ? muted : AppColor.textPrimary(context),
        fontWeight: FontWeight.w700,
      ),
    );
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: caption),
          const SizedBox(width: 8),
          Flexible(child: number),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [caption, const SizedBox(height: 5), number],
      ),
    );
  }
}
