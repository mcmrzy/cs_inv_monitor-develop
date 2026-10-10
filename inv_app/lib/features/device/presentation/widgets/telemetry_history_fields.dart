import 'package:flutter/material.dart';
import 'package:inv_app/l10n/app_localizations.dart';

typedef HistoryField = (String, String, String);

const historyFieldGroups = <String, List<HistoryField>>{
  'pv': [
    ('pv1_voltage', 'energy_pv1_voltage', 'V'),
    ('pv1_current', 'energy_pv1_current', 'A'),
    ('pv1_power', 'energy_pv1_power', 'W'),
    ('pv2_voltage', 'energy_pv2_voltage', 'V'),
    ('pv2_current', 'energy_pv2_current', 'A'),
    ('pv2_power', 'energy_pv2_power', 'W'),
    ('pv_total_power', 'telemetry_pv_total_power', 'W'),
    ('mppt_state', 'energy_mppt_state', ''),
    ('daily_pv_energy', 'telemetry_daily_pv', 'kWh'),
    ('total_pv_energy', 'telemetry_total_pv', 'kWh'),
  ],
  'battery': [
    ('battery_soc', 'telemetry_soc', '%'),
    ('battery_voltage', 'telemetry_battery_voltage', 'V'),
    ('battery_current', 'telemetry_battery_current', 'A'),
    ('battery_power', 'telemetry_battery_power', 'W'),
    ('battery_temperature', 'telemetry_battery_temp', 'C'),
    ('bms_soc', 'storage_summary_soc', '%'),
    ('bms_soh', 'storage_soh', '%'),
    ('bms_voltage', 'storage_pack_voltage', 'V'),
    ('bms_current', 'storage_current', 'A'),
    ('bms_capacity_remain', 'storage_remain_capacity', 'Ah'),
    ('bms_capacity_full', 'storage_full_capacity', 'Ah'),
    ('bms_cycle_count', 'storage_cycle_count', ''),
    ('bms_temp_max', 'storage_summary_temp_max', 'C'),
    ('bms_temp_min', 'storage_summary_temp_min', 'C'),
    ('bms_mos_temp', 'storage_mos_temp', 'C'),
    ('bms_pcb_temp', 'storage_pcb_temp', 'C'),
    ('bms_env_temp', 'storage_env_temp', 'C'),
    ('bms_charge_request_current', 'storage_summary_request_current', 'A'),
    ('bms_charge_request_voltage', 'storage_summary_request_voltage', 'V'),
    ('bms_charging_voltage', 'storage_summary_charging_voltage', 'V'),
  ],
  'ac': [
    ('output_power', 'ac_output_power', 'W'),
    ('ac_output_voltage', 'telemetry_ac_voltage', 'V'),
    ('output_current', 'telemetry_ac_current', 'A'),
    ('ac_output_frequency', 'frequency', 'Hz'),
  ],
  'system': [
    ('inverter_temperature', 'inverter_temp', 'C'),
    ('dc_bus_voltage', 'energy_dc_bus_voltage', 'V'),
    ('work_state', 'telemetry_work_state', ''),
    ('fault_code', 'telemetry_fault', ''),
    ('alarm_code', 'telemetry_alarm', ''),
  ],
};

const commonHistoryFields = {
  'pv_total_power',
  'pv1_voltage',
  'output_power',
  'battery_soc',
  'battery_voltage',
  'daily_pv_energy',
  'total_pv_energy',
};

Set<String> validHistoryFields(Iterable<String>? saved) {
  final known = historyFieldGroups.values
      .expand((fields) => fields)
      .map((f) => f.$1)
      .toSet();
  final valid = saved?.where(known.contains).toSet() ?? <String>{};
  return valid.isEmpty ? {...commonHistoryFields} : valid;
}

class TelemetryHistoryFieldPicker extends StatefulWidget {
  const TelemetryHistoryFieldPicker({super.key, required this.selected});
  final Set<String> selected;

  @override
  State<TelemetryHistoryFieldPicker> createState() => _FieldPickerState();
}

class _FieldPickerState extends State<TelemetryHistoryFieldPicker> {
  late Set<String> _selected = {...widget.selected};
  String _group = 'common';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fields = (_group == 'common'
            ? historyFieldGroups.values
                .expand((fields) => fields)
                .where((f) => commonHistoryFields.contains(f.$1))
            : historyFieldGroups[_group]!)
        .where((f) => '${l10n.str(f.$2)} ${f.$1} ${f.$3}'
            .toLowerCase()
            .contains(_search.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4, top: 4),
            child: Row(children: [
              Expanded(
                  child: Text(
                      l10n.str('history_fields_title',
                          {'count': '${_selected.length}'}),
                      style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                  tooltip: l10n.str('history_fields_reset'),
                  onPressed: () =>
                      setState(() => _selected = {...commonHistoryFields}),
                  icon: const Icon(Icons.restart_alt)),
              IconButton(
                  tooltip: l10n.cancel,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                  onChanged: (value) => setState(() => _search = value.trim()),
                  decoration: InputDecoration(
                      labelText: l10n.str('history_fields_search'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder()))),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                  children: ['common', ...historyFieldGroups.keys]
                      .map((group) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(l10n.str('history_group_$group')),
                                selected: _group == group,
                                onSelected: (_) =>
                                    setState(() => _group = group)),
                          ))
                      .toList())),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
              child: fields.isEmpty
                  ? Center(child: Text(l10n.noData))
                  : ListView(
                      children: fields
                          .map((field) => CheckboxListTile(
                                value: _selected.contains(field.$1),
                                title: Text(l10n.str(field.$2)),
                                subtitle:
                                    field.$3.isEmpty ? null : Text(field.$3),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (checked) => setState(() {
                                  if (checked == true) {
                                    _selected.add(field.$1);
                                  } else {
                                    _selected.remove(field.$1);
                                  }
                                }),
                              ))
                          .toList())),
          Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, _selected),
                      icon: const Icon(Icons.check),
                      label: Text(l10n.str('history_fields_apply'))))),
        ]),
      ),
    );
  }
}
