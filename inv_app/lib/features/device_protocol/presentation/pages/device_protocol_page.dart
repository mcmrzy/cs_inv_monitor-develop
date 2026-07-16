import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device_protocol/domain/entities/device_protocol_entities.dart';
import 'package:inv_app/features/device_protocol/domain/repositories/device_protocol_repository.dart';
import 'package:inv_app/features/device_protocol/presentation/bloc/device_protocol_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceProtocolPage extends StatelessWidget {
  const DeviceProtocolPage({super.key, required this.sn});

  final String sn;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DeviceProtocolBloc(
        repository: getIt<DeviceProtocolRepository>(),
      )..add(DeviceProtocolRequested(sn)),
      child: _DeviceProtocolView(sn: sn),
    );
  }
}

class _DeviceProtocolView extends StatelessWidget {
  const _DeviceProtocolView({required this.sn});

  final String sn;

  String _time(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.protocolTelemetry),
        actions: [
          IconButton(
            tooltip: l10n.refreshLabel,
            onPressed: () => context
                .read<DeviceProtocolBloc>()
                .add(DeviceProtocolRequested(sn)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: BlocBuilder<DeviceProtocolBloc, DeviceProtocolState>(
        builder: (context, state) {
          if (state is! DeviceProtocolLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async {
              context
                  .read<DeviceProtocolBloc>()
                  .add(DeviceProtocolRequested(sn));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(
                  context,
                  title: l10n.alarmLifecycle,
                  icon: Icons.notifications_active_outlined,
                  section: state.alarms,
                  emptyText: l10n.noAlarmEvents,
                  content: (events) => Column(
                    children: events
                        .map((event) => _alarmRow(context, event))
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: l10n.parallelCurrentState,
                  icon: Icons.hub_outlined,
                  section: state.parallel,
                  emptyText: l10n.parallelNotEnabled,
                  content: (parallel) => _parallelContent(context, parallel),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: l10n.threePhaseHistory,
                  icon: Icons.stacked_line_chart_rounded,
                  section: state.threePhase,
                  emptyText: l10n.noThreePhaseData,
                  content: (samples) => Column(
                    children: samples
                        .map((sample) => _threePhaseRow(context, sample))
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionCard<T>(
    BuildContext context, {
    required String title,
    required IconData icon,
    required ProtocolSection<T> section,
    required String emptyText,
    required Widget Function(T value) content,
  }) {
    final l10n = AppLocalizations.of(context)!;
    Widget body;
    switch (section.status) {
      case ProtocolSectionStatus.data:
        body = content(section.value as T);
      case ProtocolSectionStatus.empty:
        body = _message(
          Icons.inbox_outlined,
          emptyText,
          AppColors.textHint,
        );
      case ProtocolSectionStatus.forbidden:
        body = _message(
          Icons.lock_outline_rounded,
          section.message ?? l10n.noPermissionDevice,
          AppColors.warning,
        );
      case ProtocolSectionStatus.error:
        body = _message(
          Icons.error_outline_rounded,
          section.message ?? l10n.loadFailed,
          AppColors.error,
        );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            if (section.isFromCache) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${l10n.offlineCache} ${_time(section.cachedAt)}',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }

  Widget _alarmRow(BuildContext context, AlarmProtocolEvent event) {
    final l10n = AppLocalizations.of(context)!;
    final active = event.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (active ? AppColors.error : AppColors.success)
            .withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.alarmLabel} ${event.code} · ${l10n.sourceLabel} ${event.source}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                active ? l10n.eventOccurred : l10n.eventRecovered,
                style: TextStyle(
                  color: active ? AppColors.error : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${l10n.samplingTime}：${_time(event.eventTime)}'),
          Text('${l10n.receiveTime}：${_time(event.receivedAt)}'),
        ],
      ),
    );
  }

  Widget _parallelContent(
    BuildContext context,
    DeviceParallelState parallel,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${l10n.masterHost}：${parallel.masterSn}'),
        Text('${l10n.modeLabel}：${parallel.mode} · ${l10n.syncLabel}：${parallel.syncState}'),
        Text(
          '${l10n.deviceCount}：${parallel.count} · ${l10n.totalPower}：${parallel.totalActivePower.toStringAsFixed(1)} W',
        ),
        Text('${l10n.reportTime}：${_time(parallel.reportedAt)}'),
        if (parallel.machines.isNotEmpty) ...[
          const Divider(height: 24),
          ...parallel.machines.map(
            (machine) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '#${machine.id} ${machine.sn} · ${machine.role}'
                '${machine.phase == null ? '' : ' · ${machine.phase}'}'
                ' · ${machine.power.toStringAsFixed(1)} W',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _threePhaseRow(BuildContext context, ThreePhaseSample sample) {
    final l10n = AppLocalizations.of(context)!;
    String triple(List<double> values, String unit) {
      return '${values.map((value) => value.toStringAsFixed(1)).join(' / ')} $unit';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.samplingTime}：${_time(sample.eventTime)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('${l10n.receiveTime}：${_time(sample.receivedAt)}'),
          const SizedBox(height: 6),
          Text('${l10n.phaseVoltage}：${triple(sample.voltage, 'V')}'),
          Text('${l10n.phaseCurrent}：${triple(sample.current, 'A')}'),
          Text('${l10n.phaseActivePower}：${triple(sample.activePower, 'W')}'),
          Text(
            '${l10n.totalActiveLabel}：${sample.totalActivePower.toStringAsFixed(1)} W · '
            '${l10n.frequencyLabel}：${sample.frequency.toStringAsFixed(2)} Hz',
          ),
        ],
      ),
    );
  }
}
