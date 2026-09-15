import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/components/permission_gate.dart';

/// 全设备升级历史页（OTA 四卡片 Hub 的「升级历史」入口）
///
/// 数据源：GET /ota/history（支持 device/module/status/time 四类筛选）。
/// UI 选择本地时区时间，请求时转 ISO8601 UTC。
/// 回退：POST /ota/firmware/rollback `{device_sn, firmware_id}`。
class UpgradeHistoryPage extends StatefulWidget {
  /// 设备序列号：为空时展示全部设备
  final String deviceSN;

  const UpgradeHistoryPage({super.key, required this.deviceSN});

  @override
  State<UpgradeHistoryPage> createState() => _UpgradeHistoryPageState();
}

class _UpgradeHistoryPageState extends State<UpgradeHistoryPage> {
  final OtaRepository _repository = getIt<OtaRepository>();

  List<DeviceFirmwareHistory> _items = const [];
  int _page = 1;
  int _total = 0;
  final int _pageSize = 20;
  bool _loading = true;
  String? _error;
  bool _rollbackSubmitting = false;

  // 四类筛选
  String? _filterDeviceSn;
  String? _filterTargetChip;
  String? _filterStatus;
  DateTimeRange? _filterTimeRange;

  static const List<String> _statusOptions = [
    'pending',
    'downloading',
    'upgrading',
    'success',
    'failed',
    'cancelled',
  ];

  static const List<String> _moduleOptions = [
    'arm',
    'esp',
    'dsp',
    'bms',
  ];

  int get _totalPages => (_total / _pageSize).ceil();

  bool get _canRollback {
    return context.canControlDevices();
  }

  @override
  void initState() {
    super.initState();
    _filterDeviceSn = widget.deviceSN.isNotEmpty ? widget.deviceSN : null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repository.getHistory(
      deviceSn: _filterDeviceSn,
      targetChip: _filterTargetChip,
      status: _filterStatus,
      startTime: _filterTimeRange?.start,
      endTime: _filterTimeRange?.end,
      page: _page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _loading = false;
        _error = failure.message;
      }),
      (page) => setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
      }),
    );
  }

  void _onPageChanged(int page) {
    _page = page;
    _load();
  }

  void _resetAndLoad() {
    _page = 1;
    _load();
  }

  void _clearFilters() {
    setState(() {
      _filterDeviceSn =
          widget.deviceSN.isNotEmpty ? widget.deviceSN : null;
      _filterTargetChip = null;
      _filterStatus = null;
      _filterTimeRange = null;
    });
    _resetAndLoad();
  }

  Future<void> _pickTimeRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _filterTimeRange,
    );
    if (picked == null || !mounted) return;
    setState(() => _filterTimeRange = picked);
    _resetAndLoad();
  }

  void _applyQuickRange(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    setState(() {
      _filterTimeRange = DateTimeRange(start: start, end: now);
    });
    _resetAndLoad();
  }

  Future<void> _onRollback(DeviceFirmwareHistory item) async {
    if (!_canRollback) {
      AppToast.show(
        context,
        AppLocalizations.of(context)!.str('upgrade_history_no_permission'),
        type: ToastType.info,
      );
      return;
    }
    if (item.rollbackFirmwareId <= 0) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('firmware_rollback')),
        content: Text(
          l10n.str('firmware_rollback_confirm', {
            'version': item.oldVersion.isEmpty
                ? item.firmwareVersion
                : item.oldVersion,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _rollbackSubmitting = true);
    final key =
        'rollback-${item.deviceSn}-${item.rollbackFirmwareId}-${DateTime.now().millisecondsSinceEpoch}';
    final result = await _repository.rollbackFirmware(
      item.deviceSn,
      item.rollbackFirmwareId,
      idempotencyKey: key,
    );
    if (!mounted) return;
    setState(() => _rollbackSubmitting = false);
    result.match(
      (failure) => AppToast.show(
        context,
        l10n.str('firmware_rollback_failed', {'error': failure.message}),
        type: ToastType.error,
      ),
      (_) {
        AppToast.show(
          context,
          l10n.str('firmware_rollback_sent'),
          type: ToastType.success,
        );
        _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.str('ota_upgrade_history'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
        actions: [
          if (_filterTargetChip != null ||
              _filterStatus != null ||
              _filterTimeRange != null)
            TextButton(
              onPressed: _clearFilters,
              child: Text(l10n.str('upgrade_history_filter_clear')),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(l10n),
          Expanded(child: _buildBody(context, l10n)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      color: AppColor.surfaceContainer(context),
      child: Column(
        children: [
          SizedBox(
            height: 36.h,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // 模块筛选
                _filterChip(
                  label: _filterTargetChip == null
                      ? l10n.str('upgrade_history_filter_module')
                      : FirmwareModulePresentation.fromTarget(_filterTargetChip)
                          .displayLabel(l10n),
                  selected: _filterTargetChip != null,
                  onTap: () => _showModulePicker(l10n),
                ),
                SizedBox(width: 8.w),
                // 状态筛选
                _filterChip(
                  label: _filterStatus == null
                      ? l10n.str('upgrade_history_filter_status')
                      : _statusLabel(l10n, _filterStatus!),
                  selected: _filterStatus != null,
                  onTap: () => _showStatusPicker(l10n),
                ),
                SizedBox(width: 8.w),
                // 时间筛选
                _filterChip(
                  label: _filterTimeRange == null
                      ? l10n.str('upgrade_history_filter_time')
                      : _formatRange(_filterTimeRange!),
                  selected: _filterTimeRange != null,
                  onTap: _pickTimeRange,
                ),
                SizedBox(width: 8.w),
                _filterChip(
                  label: l10n.str('upgrade_history_filter_today'),
                  selected: false,
                  onTap: () => _applyQuickRange(1),
                ),
                SizedBox(width: 8.w),
                _filterChip(
                  label: l10n.str('upgrade_history_filter_7days'),
                  selected: false,
                  onTap: () => _applyQuickRange(7),
                ),
                SizedBox(width: 8.w),
                _filterChip(
                  label: l10n.str('upgrade_history_filter_30days'),
                  selected: false,
                  onTap: () => _applyQuickRange(30),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColor.surfaceHover(context),
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColor.border(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.primary
                    : AppColor.textSecondary(context),
              ),
            ),
            if (selected) ...[
              SizedBox(width: 4.w),
              Icon(Icons.close_rounded, size: 14.sp, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }

  void _showModulePicker(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.str('upgrade_history_filter_all')),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _filterTargetChip = null);
                _resetAndLoad();
              },
            ),
            for (final m in _moduleOptions)
              ListTile(
                leading: Icon(
                  FirmwareModulePresentation.fromTarget(m).icon,
                ),
                title: Text(
                  FirmwareModulePresentation.fromTarget(m).displayLabel(l10n),
                ),
                selected: _filterTargetChip == m,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _filterTargetChip = m);
                  _resetAndLoad();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showStatusPicker(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.str('upgrade_history_filter_all')),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _filterStatus = null);
                _resetAndLoad();
              },
            ),
            for (final s in _statusOptions)
              ListTile(
                title: Text(_statusLabel(l10n, s)),
                selected: _filterStatus == s,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _filterStatus = s);
                  _resetAndLoad();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    final key = 'upgrade_history_status_$status';
    final label = l10n.str(key);
    return label == key ? status : label;
  }

  String _formatRange(DateTimeRange range) {
    String two(int v) => v.toString().padLeft(2, '0');
    final s = range.start.toLocal();
    final e = range.end.toLocal();
    return '${s.month}/${s.day} - ${e.month}/${e.day}';
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const PageSkeleton();
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.str('upgrade_history_load_failed'),
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColor.textHint(context),
              ),
            ),
            SizedBox(height: 12.h),
            OutlinedButton(
              onPressed: _load,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          l10n.str('upgrade_history_empty'),
          style: TextStyle(
            fontSize: 14.sp,
            color: AppColor.textHint(context),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                return _UpgradeTile(
                  item: item,
                  canRollback: _canRollback,
                  rollbackSubmitting: _rollbackSubmitting,
                  onRollback: () => _onRollback(item),
                );
              },
            ),
          ),
          PaginationBar(
            currentPage: _page,
            totalPages: _totalPages,
            onPageChanged: _onPageChanged,
          ),
        ],
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  final DeviceFirmwareHistory item;
  final bool canRollback;
  final bool rollbackSubmitting;
  final VoidCallback onRollback;

  const _UpgradeTile({
    required this.item,
    required this.canRollback,
    required this.rollbackSubmitting,
    required this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final module = FirmwareModulePresentation.fromTarget(item.target);
    final versionText = item.firmwareVersion.isEmpty
        ? l10n.unknown
        : item.firmwareVersion;
    final showRollback = item.canRollback;
    final time = (item.updatedAt ?? item.createdAt)?.toLocal();
    return ListTile(
      onTap: null,
      leading: Icon(
        module.icon,
        size: 22.sp,
        color: _statusColor(context, item.status),
      ),
      title: Text(
        '${module.displayLabel(l10n)} · $versionText',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.sp,
          color: AppColor.textPrimary(context),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.deviceSn.isNotEmpty) ...[
            Text(
              item.deviceSn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: AppColor.textPrimary(context),
              ),
            ),
            SizedBox(height: 2.h),
          ],
          Text(
            time == null ? '—' : _formatTime(time),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textHint(context),
            ),
          ),
          if (item.oldVersion.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Text(
              '${l10n.str('upgrade_history_old_version')}: ${item.oldVersion}',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColor.textHint(context),
              ),
            ),
          ],
          if (item.errorMessage.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Text(
              FirmwareModulePresentation.sanitizeCustomerCopy(
                item.errorMessage,
                l10n,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.sp, color: AppColors.error),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusChip(status: item.status),
          if (showRollback) ...[
            SizedBox(width: 6.w),
            Tooltip(
              message: l10n.str('firmware_rollback'),
              child: IconButton(
                icon: const Icon(Icons.restore_rounded, size: 20),
                color: canRollback
                    ? AppColors.primary
                    : AppColor.textHint(context),
                onPressed: canRollback && !rollbackSubmitting
                    ? onRollback
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _statusColor(context, status);
    final labelKey = switch (status) {
      'pending' => 'upgrade_history_status_pending',
      'downloading' => 'upgrade_history_status_downloading',
      'upgrading' => 'upgrade_history_status_upgrading',
      'success' => 'upgrade_history_status_success',
      'failed' => 'upgrade_history_status_failed',
      'cancelled' => 'upgrade_history_status_cancelled',
      _ => '',
    };
    final label = labelKey.isEmpty ? status.toUpperCase() : l10n.str(labelKey);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  return switch (status) {
    'success' => AppColors.success,
    'failed' => AppColors.error,
    'pending' => AppColors.warning,
    'downloading' || 'upgrading' => AppColors.primary,
    _ => AppColor.textHint(context),
  };
}

/// 本地时间格式化：yyyy-MM-dd HH:mm
String _formatTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
