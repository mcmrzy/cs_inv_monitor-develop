import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/data/device_telemetry_api.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:timezone/timezone.dart' as tz;

class DeviceTelemetryHistoryPage extends StatefulWidget {
  const DeviceTelemetryHistoryPage(
      {super.key,
      required this.sn,
      this.api,
      this.timezone = TimezoneUtils.defaultTimezone});
  final String sn;
  final DeviceTelemetryApi? api;
  final String timezone;

  @override
  State<DeviceTelemetryHistoryPage> createState() => _HistoryState();
}

class _HistoryState extends State<DeviceTelemetryHistoryPage> {
  late final DeviceTelemetryApi _api;
  DateTime _day = DateTime.now();
  String _granularity = 'raw';
  int _page = 1;
  int _request = 0;
  bool _loading = true;
  bool _failed = false;
  bool _chart = false;
  String _metric = 'pv_total_power';
  DeviceTelemetryPage? _data;

  @override
  void initState() {
    super.initState();
    _api = widget.api ??
        DeviceTelemetryApi(getIt<Dio>(), timezone: widget.timezone);
    _day = tz.TZDateTime.now(_api.location);
    _fetch();
  }

  Future<void> _fetch() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await _api.getHistory(widget.sn, _day,
          page: _page, pageSize: _chart ? 500 : 20, granularity: _granularity);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime(2020),
        lastDate: tz.TZDateTime.now(_api.location));
    if (date == null || !mounted) return;
    _day = date;
    _page = 1;
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.str('telemetry_history')), actions: [
        IconButton(
            tooltip: _chart ? l10n.str('telemetry_samples') : l10n.historyCurve,
            onPressed: () {
              _chart = !_chart;
              _page = 1;
              _fetch();
            },
            icon: Icon(
                _chart ? Icons.list_alt_rounded : Icons.show_chart_rounded)),
        IconButton(
            tooltip: l10n.refreshLabel,
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${widget.sn}  ·  ${_api.timezone}',
                    style: Theme.of(context).textTheme.bodySmall))),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(DateFormat('yyyy-MM-dd').format(_day))),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'raw',
                        label: Text(l10n.str('telemetry_samples'))),
                    ButtonSegment(
                        value: 'hour',
                        label: Text(l10n.str('telemetry_hourly'))),
                  ],
                  selected: {_granularity},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    _granularity = selection.single;
                    _page = 1;
                    _fetch();
                  },
                ),
              ],
            )),
        const Divider(height: 1),
        if (_chart)
          Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pv_total_power', label: Text('PV (W)')),
                  ButtonSegment(value: 'output_power', label: Text('AC (W)')),
                  ButtonSegment(value: 'battery_soc', label: Text('SOC (%)')),
                ],
                selected: {_metric},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _metric = selection.single),
              )),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(l10n.loadFailed),
                      TextButton.icon(
                          onPressed: _fetch,
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.retry)),
                    ]))
                  : (_data?.items.isEmpty ?? true)
                      ? Center(child: Text(l10n.noData))
                      : _chart
                          ? _buildChart(l10n)
                          : RefreshIndicator(
                              onRefresh: _fetch,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _data!.items.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) =>
                                    _sample(_data!.items[index], l10n),
                              )),
        ),
        SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                IconButton(
                    tooltip: l10n.str('telemetry_previous'),
                    onPressed: _loading || _page <= 1
                        ? null
                        : () {
                            _page--;
                            _fetch();
                          },
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: Text(
                        _failed || _loading
                            ? '--'
                            : l10n.str('telemetry_page', {
                                'page': '$_page',
                                'total': '${_data?.total ?? 0}'
                              }),
                        textAlign: TextAlign.center)),
                IconButton(
                    tooltip: l10n.str('telemetry_next'),
                    onPressed: _loading ||
                            _failed ||
                            _page * (_chart ? 500 : 20) >= (_data?.total ?? 0)
                        ? null
                        : () {
                            _page++;
                            _fetch();
                          },
                    icon: const Icon(Icons.chevron_right)),
              ]),
            )),
      ]),
    );
  }

  Widget _buildChart(AppLocalizations l10n) {
    final samples = <(DateTime, double?)>[];
    for (final row in _data!.items) {
      final time =
          DateTime.tryParse('${row['time'] ?? row['event_time'] ?? ''}');
      if (time == null) continue;
      final raw = row[_metric];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      samples.add((time, value?.isFinite == true ? value : null));
    }
    samples.sort((a, b) => a.$1.compareTo(b.$1));
    if (!samples.any((sample) => sample.$2 != null)) {
      return Center(child: Text(l10n.noData));
    }
    final start = tz.TZDateTime(_api.location, _day.year, _day.month, _day.day);
    final end =
        tz.TZDateTime(_api.location, _day.year, _day.month, _day.day + 1);
    final spots = samples
        .map((sample) => sample.$2 == null
            ? FlSpot.nullSpot
            : FlSpot(sample.$1.difference(start).inSeconds / 3600, sample.$2!))
        .toList();
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: end.difference(start).inSeconds / 3600,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                barWidth: 2,
                color: _metric == 'pv_total_power'
                    ? Colors.orange
                    : _metric == 'battery_soc'
                        ? Colors.teal
                        : AppColors.primary,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(show: false),
              )
            ],
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 11)))),
              bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true,
                      interval: 6,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '${value.toInt().toString().padLeft(2, '0')}:00',
                              style: const TextStyle(fontSize: 11))))),
            ),
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
          ),
        ));
  }

  static const _fields = <(String, String, String)>[
    ('pv1_voltage', 'energy_pv1_voltage', 'V'),
    ('pv1_current', 'energy_pv1_current', 'A'),
    ('pv1_power', 'energy_pv1_power', 'W'),
    ('pv2_voltage', 'energy_pv2_voltage', 'V'),
    ('pv2_current', 'energy_pv2_current', 'A'),
    ('pv2_power', 'energy_pv2_power', 'W'),
    ('pv_total_power', 'telemetry_pv_total_power', 'W'),
    ('mppt_state', 'energy_mppt_state', ''),
    ('battery_soc', 'telemetry_soc', '%'),
    ('battery_voltage', 'telemetry_battery_voltage', 'V'),
    ('battery_current', 'telemetry_battery_current', 'A'),
    ('battery_power', 'telemetry_battery_power', 'W'),
    ('battery_temperature', 'telemetry_battery_temp', 'C'),
    ('output_power', 'ac_output_power', 'W'),
    ('ac_output_voltage', 'telemetry_ac_voltage', 'V'),
    ('output_current', 'telemetry_ac_current', 'A'),
    ('ac_output_frequency', 'frequency', 'Hz'),
    ('inverter_temperature', 'inverter_temp', 'C'),
    ('dc_bus_voltage', 'energy_dc_bus_voltage', 'V'),
    ('work_state', 'telemetry_work_state', ''),
    ('daily_pv_energy', 'telemetry_daily_pv', 'kWh'),
    ('total_pv_energy', 'telemetry_total_pv', 'kWh'),
    ('fault_code', 'telemetry_fault', ''),
    ('alarm_code', 'telemetry_alarm', ''),
  ];

  String _value(dynamic value, String unit) {
    if (value == null) return '--';
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return '${number?.toStringAsFixed(1) ?? value}${unit.isEmpty ? '' : ' $unit'}';
  }

  Widget _sample(Map<String, dynamic> row, AppLocalizations l10n) {
    final time = DateTime.tryParse('${row['time'] ?? row['event_time'] ?? ''}');
    return ExpansionTile(
      key: ValueKey(
          '$_day-$_granularity-$_page-${row['time']}-${row['data_hash']}'),
      title: Text(
          time == null
              ? '--'
              : DateFormat('HH:mm:ss')
                  .format(tz.TZDateTime.from(time, _api.location)),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('PV ${_value(row['pv_total_power'], 'W')}'),
              Text('AC ${_value(row['output_power'], 'W')}'),
              Text('SOC ${_value(row['battery_soc'], '%')}'),
            ],
          )),
      children: _fields
          .map((field) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: Row(children: [
                  Expanded(
                      child: Text(l10n.str(field.$2),
                          style: TextStyle(
                              color: AppColor.textSecondary(context)))),
                  const SizedBox(width: 12),
                  Text(_value(row[field.$1], field.$3)),
                ]),
              ))
          .toList(growable: false),
    );
  }
}
