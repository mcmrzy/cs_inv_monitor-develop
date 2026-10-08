import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/entities/bms_summary.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

import 'bms_summary_components.dart';

class BmsSummaryView extends StatefulWidget {
  final BmsSummary summary;
  final Future<void> Function() onRefresh;
  final bool refreshFailed;
  final DateTime Function()? clock;

  const BmsSummaryView({
    super.key,
    required this.summary,
    required this.onRefresh,
    this.refreshFailed = false,
    this.clock,
  });

  @override
  State<BmsSummaryView> createState() => _BmsSummaryViewState();
}

class _BmsSummaryViewState extends State<BmsSummaryView>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  Timer? _expiryTimer;
  int _tab = 0, _selected = 0;

  BmsSummary get b => widget.summary;
  DateTime get now => widget.clock?.call() ?? DateTime.now();
  bool? get online => b.onlineAt(now);
  bool get live => online == true;
  Color get green => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF72CBB0)
      : bmsGreen;
  Color get red => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFF9B92)
      : bmsRed;
  Color get amber => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFEFC067)
      : const Color(0xFF8B620F);
  bool get flagsUnknown =>
      b.warningFlag == null ||
      b.protectionFlag == null ||
      b.statusFaultFlag == null ||
      (b.warningFlag! & 0x00C0) != 0 ||
      (b.protectionFlag! & 0x8000) != 0 ||
      (b.statusFaultFlag! & 0x20C8) != 0;
  String t(String key, [Map<String, String>? args]) =>
      AppLocalizations.of(context)!.str(key, args);
  String number(num? n, String unit, [int digits = 1]) => !live || n == null
      ? '--'
      : '${n.toStringAsFixed(digits)}${unit.isEmpty ? '' : ' $unit'}';
  String integer(int? n) => n?.toString() ?? '--';
  String raw(int? n) => n == null ? '--' : '$n ${t('storage_summary_raw')}';
  String hex(int? n) => n == null
      ? '--'
      : '0x${n.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  String date(DateTime? value) => value == null
      ? '--'
      : DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());
  List<String> get warningKeys =>
      b.warningKeys.where((k) => !k.contains(':')).toList();
  List<String> get protectionKeys =>
      b.protectionKeys.where((k) => !k.contains(':')).toList();
  static const _faultNames = {
    'storage_fault_chg_mos_fault',
    'storage_fault_dsg_mos_fault',
    'storage_fault_ntc_break',
    'storage_summary_cell_fault',
    'storage_fault_afe_comm',
  };
  List<String> get faultKeys =>
      b.statusFaultKeys.where(_faultNames.contains).toList();
  List<String> get stateKeys => b.statusFaultKeys
      .where((k) => !_faultNames.contains(k) && !k.contains(':'))
      .toList();
  List<double> get validCells => b.cellVoltages.whereType<double>().toList();
  double? get cellMax =>
      validCells.isEmpty ? null : validCells.reduce(math.max);
  double? get cellMin =>
      validCells.isEmpty ? null : validCells.reduce(math.min);
  double? get cellDelta => cellMax == null ? null : cellMax! - cellMin!;
  bool balancing(int i) =>
      live && b.balanceStatus != null && b.balanceStatus! & (1 << i) != 0;
  Color get severity => !live
      ? AppColor.textSecondary(context)
      : protectionKeys.isNotEmpty || faultKeys.isNotEmpty
          ? red
          : warningKeys.isNotEmpty
              ? amber
              : flagsUnknown
                  ? AppColor.textSecondary(context)
                  : green;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Freshness advances even when a request fails or no new sample arrives.
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  void selectTab(int value) {
    setState(() => _tab = value);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String labels(List<String> keys) => keys.isEmpty
      ? t('storage_bms_none')
      : keys
          .map(
            (key) => key.contains(':')
                ? t(
                    'storage_summary_reserved_bit',
                    {'bit': key.split(':').last},
                  )
                : t(key),
          )
          .join(' · ');

  String operating({bool summary = false}) {
    if (b.statusFaultFlag == null || (b.statusFaultFlag! & 0x20C8) != 0) {
      return t('storage_bms_operating_unknown');
    }
    final keys = summary
        ? stateKeys
            .where(
              (k) => k == 'storage_charging' || k == 'storage_discharging',
            )
            .toList()
        : stateKeys;
    return keys.isEmpty ? t('storage_bms_no_operating') : labels(keys);
  }

  @override
  Widget build(BuildContext context) {
    final state = online == true
        ? 'storage_summary_online'
        : online == false
            ? b.online == true
                ? 'storage_bms_expired'
                : 'storage_summary_offline'
            : 'storage_summary_unknown';
    return Material(
      color: AppColor.surfaceContainer(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        live ? Icons.check_circle_outline : Icons.link_off,
                        size: 16,
                        color: severity,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t(state),
                          style: TextStyle(fontSize: 12, color: severity),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    date(b.updatedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Semantics(
                    selected: _tab == i,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: _tab == i
                                ? green
                                : AppColor.outline(context)
                                    .withValues(alpha: .3),
                          ),
                        ),
                      ),
                      child: TextButton(
                        key: ValueKey('bms-tab-$i'),
                        onPressed: () => selectTab(i),
                        style: TextButton.styleFrom(
                          foregroundColor: _tab == i
                              ? green
                              : AppColor.textSecondary(context),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 4,
                          ),
                          shape: const RoundedRectangleBorder(),
                        ),
                        child: navigationLabel(i),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.refreshFailed)
                      _notice(
                        t('storage_bms_refresh_failed'),
                        Icons.cloud_off,
                        false,
                      ),
                    if (!live)
                      _notice(
                        t('storage_bms_unavailable'),
                        Icons.link_off,
                        false,
                      )
                    else if (faultKeys.isNotEmpty ||
                        protectionKeys.isNotEmpty ||
                        warningKeys.isNotEmpty)
                      _notice(
                        labels(
                          protectionKeys.isNotEmpty
                              ? protectionKeys
                              : faultKeys.isNotEmpty
                                  ? faultKeys
                                  : warningKeys,
                        ),
                        Icons.warning_amber,
                        true,
                      )
                    else if (flagsUnknown)
                      _notice(
                        t('storage_bms_flags_unknown'),
                        Icons.help_outline,
                        false,
                      ),
                    if (_tab == 0) ...overview(),
                    if (_tab == 1) ...cells(),
                    if (_tab == 2) ...diagnostics(),
                    const SizedBox(height: 20),
                    const Divider(),
                    Text(
                      'ARM · CMD 0x08',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text, IconData icon, bool active) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
        decoration: BoxDecoration(
          color: active
              ? severity.withValues(alpha: .08)
              : AppColor.surfaceHover(context),
          border: Border(
            left: BorderSide(
              width: 3,
              color: active ? severity : AppColor.outline(context),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? severity : AppColor.textSecondary(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: active ? severity : AppColor.textSecondary(context),
                ),
              ),
            ),
            IconButton(
              tooltip: t('storage_bms_diagnostics'),
              onPressed: () => selectTab(2),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );

  Widget provisional() => Tooltip(
        message: t('storage_bms_provisional'),
        triggerMode: TooltipTriggerMode.tap,
        child: Semantics(
          label: t('storage_bms_provisional'),
          child: const Icon(Icons.info_outline, size: 16),
        ),
      );

  Widget navigationLabel(int i) {
    final icon = Icon(
      [Icons.speed, Icons.grid_view_outlined, Icons.shield_outlined][i],
      size: 17,
    );
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        t(
          [
            'storage_bms_overview',
            'storage_bms_cells',
            'storage_bms_diagnostics',
          ][i],
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
    final large = MediaQuery.textScalerOf(context).scale(13) > 18;
    return SizedBox(
      height: large ? 52 : 22,
      child: large
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 5),
                Expanded(child: label),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 6),
                Flexible(child: label),
              ],
            ),
    );
  }

  List<Widget> overview() => [
        Row(
          children: [
            Flexible(
              child: Text(
                t('storage_bms_soc'),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColor.textSecondary(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            provisional(),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              number(b.soc, '%'),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w600,
                color: AppColor.textPrimary(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'SOC ${number(b.soc, '%')}',
          child: LinearProgressIndicator(
            value: live && b.soc != null ? (b.soc! / 100).clamp(0, 1) : 0,
            minHeight: 8,
            borderRadius: BorderRadius.circular(2),
            color: green,
            backgroundColor: AppColor.surfaceHover(context),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 6,
          spacing: 12,
          children: [
            Text(
              live ? operating(summary: true) : t('storage_bms_unavailable'),
              style: TextStyle(fontSize: 12, color: severity),
            ),
            Text(
              '${t('storage_summary_count')}: ${integer(b.batteryCount)}',
              style: TextStyle(
                fontSize: 12,
                color: AppColor.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        BmsMetricGrid(
          columns: 2,
          children: [
            BmsMetric(
              label: t('storage_pack_voltage'),
              value: number(b.voltage, 'V', 2),
            ),
            BmsMetric(
              label: t('storage_current'),
              value: number(b.current, 'A', 2),
              detail: !live || b.current == null || b.current == 0
                  ? null
                  : t(
                      b.current! < 0
                          ? 'storage_bms_negative_current'
                          : 'storage_bms_positive_current',
                    ),
            ),
            BmsMetric(
              label: 'SOH',
              value: number(b.soh, '%'),
              trailing: provisional(),
            ),
            BmsMetric(
              label: t('storage_cycle_count'),
              value: live ? integer(b.cycleCount) : '--',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        flags(),
        const Divider(),
        temperatures(),
        const Divider(),
        BmsSection(
          title: t('storage_capacity'),
          detail: 'Ah',
          children: [
            BmsMetricGrid(
              children: [
                BmsMetric(
                  label: t('storage_remain_capacity'),
                  value: number(b.capacityRemain, '', 3),
                  compact: true,
                ),
                BmsMetric(
                  label: t('storage_full_capacity'),
                  value: number(b.capacityFull, '', 3),
                  compact: true,
                ),
                BmsMetric(
                  label: t('storage_design_capacity'),
                  value: number(b.capacityDesign, '', 3),
                  compact: true,
                ),
              ],
            ),
          ],
        ),
        const Divider(),
        ListTile(
          key: const ValueKey('bms-cell-jump'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            t('storage_bms_consistency'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(number(cellDelta, 'mV', 0)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => selectTab(1),
        ),
      ];

  Widget flags() => BmsSection(
        title: t(live ? 'storage_bms_flags' : 'storage_summary_history'),
        children: [
          for (final item in [
            (
              t('storage_summary_warning'),
              b.warningFlag,
              warningKeys,
              amber,
              0x00C0
            ),
            (
              t('storage_summary_protection'),
              b.protectionFlag,
              protectionKeys,
              red,
              0x8000
            ),
            (
              t('storage_bms_faults'),
              b.statusFaultFlag,
              faultKeys,
              red,
              0x20C8
            ),
          ]) ...[
            BmsReadout(
              label: item.$1,
              value: item.$2 == null
                  ? t('storage_bms_flags_unknown')
                  : item.$2! & item.$5 != 0
                      ? '${item.$3.isEmpty ? '' : '${labels(item.$3)} · '}${t('storage_bms_unknown_bits')}'
                      : labels(item.$3),
              color: live && item.$3.isNotEmpty ? item.$4 : null,
            ),
            const Divider(height: 1),
          ],
          BmsReadout(
            label: t('storage_bms_operating'),
            value: operating(),
          ),
        ],
      );

  Widget temperatures() => BmsSection(
        title: t('storage_temps'),
        children: [
          BmsMetricGrid(
            children: [
              BmsMetric(
                label: 'MOS',
                value: number(b.mosTemp, '°C'),
                compact: true,
              ),
              BmsMetric(
                label: 'PCB',
                value: number(b.pcbTemp, '°C'),
                compact: true,
              ),
              BmsMetric(
                label: t('storage_env_temp'),
                value: number(b.envTemp, '°C'),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < 4; i++)
            BmsReadout(
              label:
                  t('storage_summary_cell_temperature', {'index': '${i + 1}'}),
              value: number(b.cellTemperatures[i], '°C'),
            ),
        ],
      );

  Color cellColor(double? value) => !live || value == null
      ? AppColor.textSecondary(context)
      : value == cellMax
          ? bmsAmber
          : value == cellMin
              ? bmsBlue
              : green.withValues(alpha: .58);

  List<Widget> cells() => [
        BmsSection(
          title: t('storage_bms_consistency'),
          detail:
              '${live ? validCells.length : '--'} / 16 ${t('storage_bms_valid')}',
          children: [
            BmsMetricGrid(
              children: [
                BmsMetric(
                  label: t('storage_max'),
                  value: number(cellMax, 'mV', 0),
                  compact: true,
                  detail: live && cellMax != null
                      ? 'C${(b.cellVoltages.indexOf(cellMax) + 1).toString().padLeft(2, '0')}'
                      : null,
                ),
                BmsMetric(
                  label: t('storage_min'),
                  value: number(cellMin, 'mV', 0),
                  compact: true,
                  detail: live && cellMin != null
                      ? 'C${(b.cellVoltages.indexOf(cellMin) + 1).toString().padLeft(2, '0')}'
                      : null,
                ),
                BmsMetric(
                  label: t('storage_bms_delta'),
                  value: number(cellDelta, 'mV', 0),
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final legend in [
                  (bmsAmber, t('storage_max')),
                  (bmsBlue, t('storage_min')),
                  (green, t('storage_balancing')),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.square, size: 8, color: legend.$1),
                      const SizedBox(width: 5),
                      Text(
                        legend.$2,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColor.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: live && validCells.isNotEmpty
                  ? chart()
                  : Center(
                      child: Text(
                        t('storage_bms_no_reading'),
                        style: TextStyle(
                          color: AppColor.textSecondary(context),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                final height = math.max(64.0, 34 * scale + 30);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 16,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: height,
                  ),
                  itemBuilder: (context, i) {
                    final name = 'C${(i + 1).toString().padLeft(2, '0')}';
                    return Semantics(
                      key: ValueKey('bms-cell-$i'),
                      selected: _selected == i,
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selected = i),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _selected == i
                              ? green.withValues(alpha: .08)
                              : AppColor.surfaceHover(context),
                          foregroundColor: AppColor.textPrimary(context),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          side: BorderSide(
                            color: _selected == i ? green : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              child: Text(
                                '$name${balancing(i) ? ' ·' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: balancing(i)
                                      ? green
                                      : AppColor.textSecondary(
                                          context,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              child: Text(
                                number(b.cellVoltages[i], '', 0),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('bms-selected-cell'),
              padding: const EdgeInsets.all(12),
              color: AppColor.surfaceHover(context),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    'C${(_selected + 1).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(number(b.cellVoltages[_selected], 'mV', 0)),
                  Text(
                    !live ||
                            b.cellVoltages[_selected] == null ||
                            b.balanceStatus == null
                        ? t('storage_bms_unavailable')
                        : t(
                            balancing(_selected)
                                ? 'storage_balancing'
                                : 'storage_bms_not_balancing',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(),
        temperatures(),
      ];

  Widget chart() {
    final padding = math.max(10.0, (cellMax! - cellMin!) * .15);
    final low = math.max(0.0, cellMin! - padding);
    final high = cellMax! + padding;
    return BarChart(
      duration: Duration.zero,
      BarChartData(
        minY: low,
        maxY: high,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (high - low) / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColor.outline(context).withValues(alpha: .4),
            strokeWidth: .5,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 43,
              interval: (high - low) / 4,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 9,
                  color: AppColor.textSecondary(context),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt() + 1}',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColor.textSecondary(context),
                ),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.spot != null) {
              setState(() => _selected = response!.spot!.touchedBarGroupIndex);
            }
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              'C${group.x + 1} ${b.cellVoltages[group.x]!.toStringAsFixed(0)} mV',
              TextStyle(color: AppColor.textPrimary(context), fontSize: 12),
            ),
            getTooltipColor: (_) => AppColor.surfaceHover(context),
          ),
        ),
        barGroups: [
          for (var i = 0; i < 16; i++)
            BarChartGroupData(
              x: i,
              barRods: b.cellVoltages[i] == null
                  ? []
                  : [
                      BarChartRodData(
                        fromY: low,
                        toY: b.cellVoltages[i]!,
                        width: 10,
                        color: cellColor(b.cellVoltages[i]),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                        borderSide: balancing(i)
                            ? BorderSide(color: green, width: 1.5)
                            : BorderSide.none,
                      ),
                    ],
            ),
        ],
      ),
    );
  }

  Widget read(String key, String value) =>
      BmsReadout(label: t(key), value: value);
  Widget expansion(String key, List<Widget> children, {bool open = false}) =>
      ExpansionTile(
        key: PageStorageKey(key),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: open,
        maintainState: true,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(
          t(key),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        children: children,
      );

  List<Widget> diagnostics() => [
        flags(),
        const Divider(),
        BmsSection(
          title: t('storage_bms_diagnostics'),
          detail: 'ARM CMD 0x08',
          children: [
            if (!live)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  t('storage_bms_historical'),
                  style: TextStyle(
                    color: AppColor.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ),
            expansion(
              'storage_bms_sampling',
              [
                read('storage_summary_count', integer(b.batteryCount)),
                read('storage_summary_updated', date(b.updatedAt)),
                read(
                  'storage_summary_age',
                  b.ageMs == null ? '--' : '${b.ageMs} ms',
                ),
                read('storage_summary_reported', date(b.reportedAt)),
                read('storage_summary_expires', date(b.expiresAt)),
                read('storage_summary_layout', integer(b.layout)),
                read(
                  'storage_summary_reported_online',
                  integer(b.bmsOnline),
                ),
              ],
              open: true,
            ),
            expansion('storage_bms_status_words', [
              read(
                'storage_summary_warning',
                '${hex(b.warningFlag)} · ${b.warningFlag == null ? '--' : labels(b.warningKeys)}',
              ),
              read(
                'storage_summary_protection',
                '${hex(b.protectionFlag)} · ${b.protectionFlag == null ? '--' : labels(b.protectionKeys)}',
              ),
              read(
                'storage_summary_status_fault',
                '${hex(b.statusFaultFlag)} · ${b.statusFaultFlag == null ? '--' : labels(b.statusFaultKeys)}',
              ),
              read('storage_balancing', hex(b.balanceStatus)),
              read('storage_summary_battery_mode', raw(b.batteryMode)),
              read('storage_summary_battery_status', raw(b.batteryStatus)),
              read('storage_summary_system_mode', raw(b.systemMode)),
            ]),
            expansion('storage_bms_measurements', [
              read('storage_pack_voltage', number(b.voltage, 'V', 2)),
              read('storage_current', number(b.current, 'A', 2)),
              BmsReadout(label: 'SOC', value: number(b.soc, '%')),
              BmsReadout(label: 'SOH', value: number(b.soh, '%')),
              read(
                'storage_cycle_count',
                live ? integer(b.cycleCount) : '--',
              ),
              read(
                'storage_remain_capacity',
                number(b.capacityRemain, 'Ah', 3),
              ),
              read('storage_full_capacity', number(b.capacityFull, 'Ah', 3)),
              read(
                'storage_design_capacity',
                number(b.capacityDesign, 'Ah', 3),
              ),
              read(
                'storage_bms_reported_max',
                number(b.maxCellVoltage, 'mV', 0),
              ),
              read(
                'storage_bms_reported_min',
                number(b.minCellVoltage, 'mV', 0),
              ),
              read('storage_cell_temp_max', number(b.maxCellTemp, '°C')),
              read('storage_cell_temp_min', number(b.minCellTemp, '°C')),
              read('storage_mos_temp', number(b.mosTemp, '°C')),
              read('storage_pcb_temp', number(b.pcbTemp, '°C')),
              read('storage_env_temp', number(b.envTemp, '°C')),
              for (var i = 0; i < 16; i++)
                BmsReadout(
                  label: '${t('storage_cell')} ${i + 1}',
                  value: number(b.cellVoltages[i], 'mV', 0),
                ),
              for (var i = 0; i < 4; i++)
                BmsReadout(
                  label: t(
                    'storage_summary_cell_temperature',
                    {'index': '${i + 1}'},
                  ),
                  value: number(b.cellTemperatures[i], '°C'),
                ),
              read('storage_summary_charging_voltage', '--'),
            ]),
            expansion('storage_summary_raw_quantities', [
              Text(
                t('storage_bms_units_unknown'),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColor.textSecondary(context),
                ),
              ),
              if (!live) Text(t('storage_summary_historical_raw')),
              read(
                'storage_summary_total_charge',
                raw(b.totalChgCapacityRaw),
              ),
              read(
                'storage_summary_total_discharge',
                raw(b.totalDsgCapacityRaw),
              ),
              read(
                'storage_summary_request_current',
                raw(b.chgRequestCurrentRaw),
              ),
              read(
                'storage_summary_request_voltage',
                raw(b.chgRequestVoltageRaw),
              ),
              BmsReadout(
                label: 'SOC ${t('storage_summary_raw')}',
                value: raw(b.socRaw),
              ),
              BmsReadout(
                label: 'SOH ${t('storage_summary_raw')}',
                value: raw(b.sohRaw),
              ),
            ]),
            ExpansionTile(
              key: const PageStorageKey('bms-payload'),
              tilePadding: EdgeInsets.zero,
              maintainState: true,
              title: Text(
                t('storage_summary_payload', {
                  'count': b.rawBytes == null ? '--' : '${b.rawBytes!.length}',
                }),
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                Container(
                  width: double.infinity,
                  color: AppColor.surfaceHover(context),
                  padding: const EdgeInsets.all(12),
                  child: b.rawBytes == null
                      ? const Text('--')
                      : SelectableText(
                          b.rawBytes!
                              .map(
                                (v) => v
                                    .toRadixString(16)
                                    .padLeft(2, '0')
                                    .toUpperCase(),
                              )
                              .join(' '),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.9,
                            color: AppColor.textSecondary(context),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ];
}
