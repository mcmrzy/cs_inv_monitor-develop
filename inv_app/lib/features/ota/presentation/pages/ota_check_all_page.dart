import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';

enum _CheckResult {
  pending,
  checking,
  updating,
  upToDate,
  failed,
  offline,
  unreported,
}

class _CheckEntry {
  final String sn;
  final String name;
  _CheckResult result;
  DeviceFirmwareOverview? overview;

  /// 按模块拆分的独立任务行（success/failed/blocked/skipped 语义）
  final List<_ModuleTaskRow> moduleRows;

  _CheckEntry({
    required this.sn,
    required this.name,
    this.result = _CheckResult.pending,
  }) : moduleRows = [];
}

/// 单模块任务行：服务端 tasks 的独立展示单元
class _ModuleTaskRow {
  final String target;
  final String currentVersion;
  final String latestVersion;
  final int latestFirmwareId;

  /// success=已最新 / failed=检查失败 / blocked=离线 / skipped=未上报
  /// updating=有更新可升级
  final String taskStatus;

  _ModuleTaskRow({
    required this.target,
    required this.currentVersion,
    required this.latestVersion,
    required this.latestFirmwareId,
    required this.taskStatus,
  });
}

/// 检查更新（全部设备）：对在线设备并发调用 firmware-overview
/// （并发上限 5），每模块独立任务行展示结果。
class OtaCheckAllPage extends StatefulWidget {
  const OtaCheckAllPage({super.key});

  @override
  State<OtaCheckAllPage> createState() => _OtaCheckAllPageState();
}

class _OtaCheckAllPageState extends State<OtaCheckAllPage> {
  static const int _concurrency = 5;

  List<_CheckEntry> _entries = const [];
  bool _running = false;
  bool _started = false;
  DeviceListLoaded? _cached;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(const DeviceListRequested(pageSize: 200));
  }

  String _str(dynamic device, List<String> keys) {
    for (final k in keys) {
      final v = device is Map ? device[k] : null;
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  void _startChecks(List<dynamic> devices) {
    if (_running) return;
    final entries = <_CheckEntry>[];
    for (final d in devices) {
      final sn = _str(d, ['sn', 'device_sn']);
      if (sn.isEmpty) continue;
      final name = _str(d, ['name', 'device_name', 'alias']);
      final status = d is Map ? (d['status'] ?? 0) : 0;
      final online = status == 1 || status == 2;
      entries.add(_CheckEntry(
        sn: sn,
        name: name.isEmpty ? sn : name,
        result: online ? _CheckResult.pending : _CheckResult.offline,
      ));
      if (!online) {
        // 离线设备：所有模块标记为 blocked
        for (final target in const ['arm', 'dsp', 'bms', 'esp']) {
          entries.last.moduleRows.add(_ModuleTaskRow(
            target: target,
            currentVersion: '',
            latestVersion: '',
            latestFirmwareId: 0,
            taskStatus: 'blocked',
          ));
        }
      }
    }
    setState(() {
      _entries = entries;
      _started = true;
    });
    _runChecks(entries.where((e) => e.result == _CheckResult.pending).toList());
  }

  Future<void> _runChecks(List<_CheckEntry> targets) async {
    if (targets.isEmpty) return;
    setState(() => _running = true);
    final repo = getIt<OtaRepository>();
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final i = index;
        index += 1;
        if (i >= targets.length || !mounted) return;
        final entry = targets[i];
        _mark(entry, _CheckResult.checking);
        final result = await repo.getFirmwareOverview(entry.sn);
        if (!mounted) return;
        result.fold(
          (failure) {
            entry.moduleRows
              ..clear()
              ..addAll(const ['arm', 'dsp', 'bms', 'esp'].map(
                (t) => _ModuleTaskRow(
                  target: t,
                  currentVersion: '',
                  latestVersion: '',
                  latestFirmwareId: 0,
                  taskStatus: 'failed',
                ),
              ));
            _mark(entry, _CheckResult.failed);
          },
          (overview) {
            entry.overview = overview;
            entry.moduleRows
              ..clear()
              ..addAll(overview.modules.map((m) => _ModuleTaskRow(
                    target: m.target,
                    currentVersion: m.currentVersion,
                    latestVersion: m.latestVersion,
                    latestFirmwareId: m.latestFirmwareId,
                    taskStatus: m.isUnreported
                        ? 'skipped'
                        : m.updateAvailable
                            ? 'updating'
                            : 'success',
                  )));
            final hasUpdate =
                overview.modules.any((m) => m.updateAvailable);
            _mark(
              entry,
              hasUpdate ? _CheckResult.updating : _CheckResult.upToDate,
            );
          },
        );
      }
    }

    await Future.wait(
      List.generate(math.min(_concurrency, targets.length), (_) => worker()),
    );
    if (!mounted) return;
    setState(() => _running = false);
  }

  void _mark(_CheckEntry entry, _CheckResult result) {
    if (!mounted) return;
    setState(() => entry.result = result);
  }

  List<_CheckEntry> get _updating =>
      _entries.where((e) => e.result == _CheckResult.updating).toList();
  List<_CheckEntry> get _upToDate =>
      _entries.where((e) => e.result == _CheckResult.upToDate).toList();
  List<_CheckEntry> get _unavailable => _entries
      .where((e) =>
          e.result == _CheckResult.offline || e.result == _CheckResult.failed)
      .toList();

  int get _checkedCount => _entries
      .where((e) =>
          e.result == _CheckResult.updating ||
          e.result == _CheckResult.upToDate ||
          e.result == _CheckResult.failed ||
          e.result == _CheckResult.offline)
      .length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.str('ota_check_update'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          if (state is DeviceListLoaded) _cached = state;
          final cached = _cached;

          if (cached == null) {
            if (state is DeviceError) {
              return XiaoshuoStatePanel(
                asset: CsergyAssets.xiaoshuoOffline,
                title: l10n.translateError(state.message),
                message: l10n.loadFailed,
                size: 160,
                action: OutlinedButton(
                  onPressed: () => context
                      .read<DeviceBloc>()
                      .add(const DeviceListRequested(pageSize: 200)),
                  child: Text(l10n.retry),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          if (cached.devices.isEmpty) {
            return XiaoshuoStatePanel(
              asset: CsergyAssets.emptyDevice,
              title: l10n.str('ota_picker_empty'),
              size: 160,
            );
          }

          // 首次进入自动开始检查
          if (!_started) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startChecks(cached.devices);
            });
          }

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 96.h),
            children: [
              _buildProgressHeader(l10n),
              SizedBox(height: 12.h),
              if (_updating.isNotEmpty) ...[
                _groupTitle(
                  l10n.str('ota_check_all_has_update'),
                  AppColors.primary,
                  _updating.length,
                ),
                for (final e in _updating) _updateCard(e, l10n),
              ],
              if (_upToDate.isNotEmpty) ...[
                _groupTitle(
                  l10n.str('ota_check_all_up_to_date'),
                  AppColors.success,
                  _upToDate.length,
                ),
                for (final e in _upToDate)
                  _deviceCard(e, Icons.check_circle_rounded, AppColors.success,
                      l10n),
              ],
              if (_unavailable.isNotEmpty) ...[
                _groupTitle(
                  l10n.str('ota_check_all_unavailable'),
                  AppColor.textHint(context),
                  _unavailable.length,
                ),
                for (final e in _unavailable)
                  _deviceCard(
                    e,
                    e.result == _CheckResult.offline
                        ? Icons.cloud_off_rounded
                        : Icons.error_outline_rounded,
                    AppColor.textHint(context),
                    l10n,
                  ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: _started
          ? FloatingActionButton.extended(
              onPressed: _running
                  ? null
                  : () {
                      final cached = _cached;
                      if (cached != null) _startChecks(cached.devices);
                    },
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(l10n.str('ota_check_all_again')),
            )
          : null,
    );
  }

  Widget _buildProgressHeader(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          if (_running)
            SizedBox(
              width: 20.w,
              height: 20.w,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              Icons.system_update_rounded,
              size: 20.sp,
              color: AppColors.primary,
            ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              _running
                  ? l10n
                      .str('ota_check_all_progress')
                      .replaceAll('{checked}', '$_checkedCount')
                      .replaceAll('{total}', '${_entries.length}')
                  : l10n
                      .str('ota_check_all_done')
                      .replaceAll('{total}', '${_entries.length}')
                      .replaceAll('{updating}', '${_updating.length}'),
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColor.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String title, Color color, int count) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 14.h, 4.w, 8.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 14.h,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            '$title ($count)',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 有更新卡片：设备名 + 模块独立任务行 + 去升级
  Widget _updateCard(_CheckEntry entry, AppLocalizations l10n) {
    final updatingRows =
        entry.moduleRows.where((r) => r.taskStatus == 'updating').toList();
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  size: 20.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      entry.sn,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  minimumSize: Size(0, 34.h),
                ),
                onPressed: () => context.push('/ota/${entry.sn}'),
                child: Text(
                  l10n.str('ota_check_all_go_upgrade'),
                  style: TextStyle(fontSize: 13.sp),
                ),
              ),
            ],
          ),
          // 模块独立任务行
          if (updatingRows.isNotEmpty) ...[
            SizedBox(height: 10.h),
            for (final row in updatingRows)
              Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Row(
                  children: [
                    Icon(
                      FirmwareModulePresentation.fromTarget(row.target).icon,
                      size: 14.sp,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      FirmwareModulePresentation.fromTarget(row.target)
                          .displayLabel(l10n),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        row.currentVersion.isEmpty
                            ? row.latestVersion
                            : '${row.currentVersion} → ${row.latestVersion}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _taskStatusChip(row.taskStatus, l10n),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 普通设备卡片（含独立模块任务行：success/failed/blocked/skipped）
  Widget _deviceCard(
    _CheckEntry entry,
    IconData icon,
    Color color,
    AppLocalizations l10n,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.sp, color: color),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textPrimary(context),
                  ),
                ),
              ),
              Text(
                entry.sn,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: AppColor.textHint(context),
                ),
              ),
            ],
          ),
          if (entry.moduleRows.isNotEmpty) ...[
            SizedBox(height: 6.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 4.h,
              children: [
                for (final row in entry.moduleRows)
                  _moduleTaskBadge(row, l10n),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _moduleTaskBadge(_ModuleTaskRow row, AppLocalizations l10n) {
    final module = FirmwareModulePresentation.fromTarget(row.target);
    final color = switch (row.taskStatus) {
      'success' => AppColors.success,
      'updating' => AppColors.primary,
      'failed' => AppColors.error,
      'blocked' => AppColor.textHint(context),
      'skipped' => AppColors.warning,
      _ => AppColor.textHint(context),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        '${module.displayLabel(l10n)} · ${_taskStatusLabel(row.taskStatus, l10n)}',
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _taskStatusChip(String status, AppLocalizations l10n) {
    final color = switch (status) {
      'updating' => AppColors.primary,
      'success' => AppColors.success,
      _ => AppColor.textHint(context),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        _taskStatusLabel(status, l10n),
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _taskStatusLabel(String status, AppLocalizations l10n) {
    return switch (status) {
      'success' => l10n.str('ota_task_status_success'),
      'failed' => l10n.str('ota_task_status_failed'),
      'blocked' => l10n.str('ota_task_status_blocked'),
      'skipped' => l10n.str('ota_task_status_skipped'),
      'updating' => l10n.str('ota_task_status_running'),
      'pending' => l10n.str('ota_task_status_pending'),
      _ => status,
    };
  }
}
