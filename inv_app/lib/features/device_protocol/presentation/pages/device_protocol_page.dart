import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device_protocol/domain/entities/device_protocol_entities.dart';
import 'package:inv_app/features/device_protocol/domain/repositories/device_protocol_repository.dart';
import 'package:inv_app/features/device_protocol/presentation/bloc/device_protocol_bloc.dart';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('协议遥测'),
        actions: [
          IconButton(
            tooltip: '刷新',
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
                  title: '告警事件生命周期',
                  icon: Icons.notifications_active_outlined,
                  section: state.alarms,
                  emptyText: '暂无告警事件',
                  content: (events) => Column(
                    children: events
                        .map((event) => _alarmRow(context, event))
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: '并机当前态',
                  icon: Icons.hub_outlined,
                  section: state.parallel,
                  emptyText: '当前设备未启用并机',
                  content: (parallel) => _parallelContent(context, parallel),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: '三相历史（3 分钟采样）',
                  icon: Icons.stacked_line_chart_rounded,
                  section: state.threePhase,
                  emptyText: '暂无三相历史数据',
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
          section.message ?? '无权限访问该设备',
          AppColors.warning,
        );
      case ProtocolSectionStatus.error:
        body = _message(
          Icons.error_outline_rounded,
          section.message ?? '加载失败',
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
                  '离线缓存 · 缓存时间 ${_time(section.cachedAt)}',
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
                  '告警 ${event.code} · 来源 ${event.source}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                active ? '发生' : '恢复',
                style: TextStyle(
                  color: active ? AppColors.error : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('采样时间：${_time(event.eventTime)}'),
          Text('接收时间：${_time(event.receivedAt)}'),
        ],
      ),
    );
  }

  Widget _parallelContent(
    BuildContext context,
    DeviceParallelState parallel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('主机：${parallel.masterSn}'),
        Text('模式：${parallel.mode} · 同步：${parallel.syncState}'),
        Text(
          '设备数：${parallel.count} · 总功率：${parallel.totalActivePower.toStringAsFixed(1)} W',
        ),
        Text('上报时间：${_time(parallel.reportedAt)}'),
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
            '采样时间：${_time(sample.eventTime)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('接收时间：${_time(sample.receivedAt)}'),
          const SizedBox(height: 6),
          Text('相电压 L1/L2/L3：${triple(sample.voltage, 'V')}'),
          Text('相电流 L1/L2/L3：${triple(sample.current, 'A')}'),
          Text('有功功率 L1/L2/L3：${triple(sample.activePower, 'W')}'),
          Text(
            '总有功：${sample.totalActivePower.toStringAsFixed(1)} W · '
            '频率：${sample.frequency.toStringAsFixed(2)} Hz',
          ),
        ],
      ),
    );
  }
}
