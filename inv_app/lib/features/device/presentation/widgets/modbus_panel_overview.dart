import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/features/device/presentation/widgets/modbus_panel_metrics.dart';

enum _ParameterGroup { solar, battery, output, status }

/// Operating measurements from the panel's authenticated BLE telemetry.
class ModbusPanelOverview extends StatefulWidget {
  const ModbusPanelOverview({super.key, required this.telemetry});

  final Map<String, dynamic> telemetry;

  @override
  State<ModbusPanelOverview> createState() => _ModbusPanelOverviewState();
}

class _ModbusPanelOverviewState extends State<ModbusPanelOverview> {
  _ParameterGroup _selected = _ParameterGroup.solar;

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

  List<(String, String)> _parameters() => switch (_selected) {
        _ParameterGroup.solar => [
            (_label('PV1 电压', 'PV1 voltage'), _metric('pv', 'pv_voltage', 'V')),
            (_label('PV1 电流', 'PV1 current'), _metric('pv', 'pv_current', 'A')),
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
    final theme = Theme.of(context);
    final groups = {
      _ParameterGroup.solar: _label('光伏', 'Solar'),
      _ParameterGroup.battery: _label('电池', 'Battery'),
      _ParameterGroup.output: _label('交流输出', 'AC output'),
      _ParameterGroup.status: _label('温度与故障', 'Temperature & faults'),
    };
    final soc = _value('battery', 'soc');
    final hasSoc = soc is num && soc.isFinite && soc >= 0 && soc <= 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF142F48),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _label('光伏总功率', 'Solar power'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFBDDBE6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _metric('pv', 'pv_power', 'W'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _SummaryMetric(
                      icon: Icons.electrical_services_outlined,
                      label: _label('输出功率', 'Output power'),
                      value: _metric('ac', 'power', 'W'),
                    ),
                    _SummaryMetric(
                      icon: Icons.battery_charging_full_outlined,
                      label: _label('电池电量', 'Battery SOC'),
                      value: hasSoc ? _metric('battery', 'soc', '%') : '—',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final group in groups.entries)
              ChoiceChip(
                label: Text(group.value),
                selected: _selected == group.key,
                onSelected: (_) => setState(() => _selected = group.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ModbusPanelMetrics(values: _parameters()),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF78DABF), size: 19),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    text.labelMedium?.copyWith(color: const Color(0xFFBDDBE6)),
              ),
              Text(
                value,
                style: text.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
