import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

/// 全设备升级历史页（需求 16：OTA 四卡片 Hub 的“升级历史”入口）
///
/// 数据源：GET /ota/history（分页返回当前用户可见的全部设备升级记录，
/// 系统管理员返回全部，普通用户由后端按数据权限过滤）。
/// 回退：POST /ota/rollback `{sn, package_id}`，后端要求 `ota:control` 权限，
/// 终端用户无权限时按钮置灰并在点击时提示“联系代理商”，不伪造回退逻辑。
class UpgradeHistoryPage extends StatefulWidget {
  /// 设备序列号：仅为兼容旧路由保留，页面不再按设备过滤。
  final String deviceSN;

  const UpgradeHistoryPage({super.key, required this.deviceSN});

  @override
  State<UpgradeHistoryPage> createState() => _UpgradeHistoryPageState();
}

class _UpgradeHistoryPageState extends State<UpgradeHistoryPage> {
  List<UpgradeHistoryItem> _items = const [];
  int _page = 1;
  int _total = 0;
  final int _pageSize = 20;
  bool _loading = true;
  String? _error;
  bool _rollbackSubmitting = false;

  int get _totalPages => (_total / _pageSize).ceil();

  /// 是否具备回退权限（ota:control）
  bool get _canRollback {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) return false;
    return state.isSystemAdmin || state.permissions.contains('ota:control');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = getIt<Dio>();
      final response = await dio.get(
        '/ota/history',
        queryParameters: {'page': _page, 'page_size': _pageSize},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final payload = (data['data'] as Map<String, dynamic>?) ?? {};
        final items = (payload['items'] as List? ?? const [])
            .map(
              (e) => UpgradeHistoryItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
        if (!mounted) return;
        setState(() {
          _items = items;
          _total = (payload['total'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[UpgradeHistoryPage] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onPageChanged(int page) {
    _page = page;
    _load();
  }

  /// 回退入口：权限门控 + 确认弹窗 + POST /ota/rollback
  Future<void> _onRollback(UpgradeHistoryItem item) async {
    if (!_canRollback) {
      AppToast.show(
        context,
        AppLocalizations.of(context)!.str('upgrade_history_no_permission'),
        type: ToastType.info,
      );
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('upgrade_history_rollback')),
        content: Text(
          l10n.str(
            'upgrade_history_rollback_confirm',
            {'version': item.firmwareVersion},
          ),
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
    try {
      final dio = getIt<Dio>();
      final response = await dio.post(
        '/ota/rollback',
        data: {'sn': item.sn, 'package_id': item.upgradePackageId},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        if (!mounted) return;
        AppToast.show(
          context,
          l10n.str('upgrade_history_rollback_sent'),
          type: ToastType.success,
        );
        _load();
      } else {
        final message = data is Map ? data['message'] : 'bad response';
        throw Exception(message);
      }
    } catch (e) {
      debugPrint('[UpgradeHistoryPage] rollback failed: $e');
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('upgrade_history_rollback_failed', {'error': '$e'}),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _rollbackSubmitting = false);
    }
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
      ),
      body: _buildBody(context, l10n),
    );
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

/// 单条升级记录（对应后端 DeviceUpgrade）
class UpgradeHistoryItem {
  final String sn; // 设备序列号（json tag: device_sn）
  final String firmwareVersion;
  final String oldVersion;
  final String status; // pending/downloading/upgrading/success/failed/cancelled
  final int progress;
  final String errorMessage;
  final String source; // admin/app/local
  final int? upgradePackageId;
  final DateTime createdAt;

  const UpgradeHistoryItem({
    required this.sn,
    required this.firmwareVersion,
    required this.oldVersion,
    required this.status,
    required this.progress,
    required this.errorMessage,
    required this.source,
    required this.upgradePackageId,
    required this.createdAt,
  });

  factory UpgradeHistoryItem.fromJson(Map<String, dynamic> json) {
    return UpgradeHistoryItem(
      sn: (json['device_sn'] ?? '').toString(),
      firmwareVersion: json['firmware_version'] as String? ?? '',
      oldVersion: json['old_version'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message'] as String? ?? '',
      source: json['source'] as String? ?? '',
      upgradePackageId: (json['upgrade_package_id'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 成功且带升级包 ID 的记录才可回退
  bool get canRollback =>
      status == 'success' && upgradePackageId != null && upgradePackageId! > 0;
}

class _UpgradeTile extends StatelessWidget {
  final UpgradeHistoryItem item;
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
    final versionText = item.firmwareVersion.isEmpty
        ? l10n.unknown
        : 'v${item.firmwareVersion}';
    final showRollback = item.canRollback;
    return ListTile(
      leading: Icon(
        Icons.system_update_rounded,
        size: 22.sp,
        color: _statusColor(context, item.status),
      ),
      title: Text(
        versionText,
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
          if (item.sn.isNotEmpty) ...[
            Text(
              item.sn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: AppColor.textPrimary(context),
              ),
            ),
            SizedBox(height: 2.h),
          ],
          Text(
            '${_sourceLabel(l10n, item.source)}'
            ' · ${_formatTime(item.createdAt)}',
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
              '${l10n.str('upgrade_history_old_version')}: v${item.oldVersion}',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColor.textHint(context),
              ),
            ),
          ],
          if (item.errorMessage.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Text(
              item.errorMessage,
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
              message: l10n.str('upgrade_history_rollback_hint'),
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

  String _sourceLabel(AppLocalizations l10n, String source) {
    return switch (source) {
      'admin' => l10n.str('upgrade_history_source_admin'),
      'app' => l10n.str('upgrade_history_source_app'),
      'local' => l10n.str('upgrade_history_source_local'),
      _ => source,
    };
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
