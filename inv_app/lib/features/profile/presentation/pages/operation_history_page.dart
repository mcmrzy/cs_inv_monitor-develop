import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dio/dio.dart';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/pagination_bar.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

/// 用户操作历史页（需求 15）
///
/// 数据源：后端聚合端点 GET /op-logs（当前用户维度），
/// 统一聚合 user_operation_logs + device_cmd_logs + device_upgrades，
/// 按时间倒序分页返回统一结构（类型/操作/设备/结果/时间）。
///
/// 交互：
/// - 单击卡片：弹出操作详情（全字段展示）
/// - 长按卡片：弹出操作菜单（查看详情 / 复制设备序列号 / 复制时间）
class OperationHistoryPage extends StatefulWidget {
  const OperationHistoryPage({super.key});

  @override
  State<OperationHistoryPage> createState() => _OperationHistoryPageState();
}

class _OperationHistoryPageState extends State<OperationHistoryPage> {
  List<OpLogItem> _items = const [];
  int _page = 1;
  int _total = 0;
  final int _pageSize = 20;
  bool _loading = true;
  String? _error;

  int get _totalPages => (_total / _pageSize).ceil();

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
        '/op-logs',
        queryParameters: {'page': _page, 'page_size': _pageSize},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final payload = (data['data'] as Map<String, dynamic>?) ?? {};
        final items = (payload['items'] as List? ?? const [])
            .map((e) => OpLogItem.fromJson(Map<String, dynamic>.from(e as Map)))
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
      debugPrint('[OperationHistoryPage] load failed: $e');
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

  /// 单击卡片：弹出操作详情 BottomSheet
  void _showDetailSheet(OpLogItem log) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColor.surfaceContainer(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：类型图标 + 标题
              Row(
                children: [
                  _TypeBadge(source: log.source),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      log.title,
                      style: TextStyle(
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.onSurface(context),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              _DetailRow(
                label: l10n.opLogType,
                value: OpLogItem.sourceLabel(l10n, log.source),
              ),
              if (log.deviceSn.isNotEmpty) ...[
                SizedBox(height: 12.h),
                _DetailRow(
                  label: l10n.opLogDevice,
                  value: log.deviceSn,
                  onCopy: () => _copy(log.deviceSn),
                ),
              ],
              SizedBox(height: 12.h),
              _DetailRow(
                label: l10n.opLogResult,
                value: OpLogItem.resultLabel(l10n, log.result),
                chipColor: OpLogItem.resultColor(context, log.result),
              ),
              SizedBox(height: 12.h),
              _DetailRow(
                label: l10n.opLogTime,
                value: _formatTime(log.opTime),
                onCopy: () => _copy(_formatTime(log.opTime)),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(l10n.str('close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按卡片：弹出操作菜单
  void _showActionSheet(OpLogItem log) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColor.surfaceContainer(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示条
              Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColor.outline(context),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 16.h),
              // 当前记录摘要
              Row(
                children: [
                  _TypeBadge(source: log.source),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      log.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.onSurface(context),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Divider(color: AppColor.outline(context).withValues(alpha: 0.5)),
              SizedBox(height: 4.h),
              _ActionSheetItem(
                icon: Icons.visibility_outlined,
                label: l10n.opLogViewDetail,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDetailSheet(log);
                },
              ),
              if (log.deviceSn.isNotEmpty)
                _ActionSheetItem(
                  icon: Icons.copy_rounded,
                  label: l10n.opLogCopySn,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _copy(log.deviceSn);
                  },
                ),
              _ActionSheetItem(
                icon: Icons.schedule_rounded,
                label: l10n.opLogCopyTime,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copy(_formatTime(log.opTime));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(String text) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      AppToast.show(context, l10n.opLogCopied, type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.operationHistory)),
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
              l10n.str('op_log_load_failed'),
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
          l10n.opLogEmpty,
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
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
              itemCount: _items.length,
              itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: _OpLogCard(
                  log: _items[index],
                  onTap: () => _showDetailSheet(_items[index]),
                  onLongPress: () => _showActionSheet(_items[index]),
                ),
              ),
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

/// 聚合端点返回的单项结构（后端 user_op_log_handler.go 统一五字段）
class OpLogItem {
  final String source; // operation / command / ota
  final String title;
  final String deviceSn;
  final String result; // success / failed / pending ...
  final DateTime opTime;

  const OpLogItem({
    required this.source,
    required this.title,
    required this.deviceSn,
    required this.result,
    required this.opTime,
  });

  factory OpLogItem.fromJson(Map<String, dynamic> json) {
    return OpLogItem(
      source: json['source'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      deviceSn: json['device_sn'] as String? ?? '',
      result: json['result'] as String? ?? 'pending',
      opTime: DateTime.tryParse(json['op_time'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 类型图标（operation / command / ota）
  static IconData sourceIcon(String source) {
    return switch (source) {
      'ota' => Icons.system_update_rounded,
      'command' => Icons.terminal_rounded,
      'operation' => Icons.touch_app_rounded,
      _ => Icons.history_rounded,
    };
  }

  /// 类型主题色
  static Color sourceColor(BuildContext context, String source) {
    return switch (source) {
      'ota' => AppColors.purple,
      'command' => AppColors.blue,
      'operation' => AppColors.teal,
      _ => AppColor.textSecondary(context),
    };
  }

  /// 类型显示文案
  static String sourceLabel(AppLocalizations l10n, String source) {
    return switch (source) {
      'ota' => l10n.opLogTypeOta,
      'command' => l10n.opLogTypeCommand,
      'operation' => l10n.opLogTypeOperation,
      _ => l10n.opLogTypeUnknown,
    };
  }

  /// 结果徽章色
  static Color resultColor(BuildContext context, String result) {
    return switch (result) {
      'success' => AppColors.successLight,
      'failed' => AppColors.errorLight,
      'pending' => AppColors.warning,
      'downloading' || 'upgrading' => AppColors.primary,
      _ => AppColor.textHint(context),
    };
  }

  /// 结果显示文案（无 i18n 键时用大写原文）
  static String resultLabel(AppLocalizations l10n, String result) {
    return switch (result) {
      'success' => l10n.str('op_log_result_success'),
      'failed' => l10n.str('op_log_result_failed'),
      'pending' => l10n.str('op_log_result_pending'),
      _ => result.toUpperCase(),
    };
  }
}

/// 卡片式操作记录项：图标圆底 + 标题 + 元信息 + 结果徽章
///
/// 单击 [onTap] 查看详情；长按 [onLongPress] 弹出操作菜单。
class _OpLogCard extends StatelessWidget {
  final OpLogItem log;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _OpLogCard({
    required this.log,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = OpLogItem.sourceColor(context, log.source);
    return Material(
      color: AppColor.surfaceContainer(context),
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: AppColor.outline(context).withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              // 类型图标圆底
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  OpLogItem.sourceIcon(log.source),
                  size: 20.sp,
                  color: accent,
                ),
              ),
              SizedBox(width: 12.w),
              // 标题 + 元信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColor.onSurface(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${OpLogItem.sourceLabel(l10n, log.source)}'
                      '${log.deviceSn.isEmpty ? '' : ' · ${log.deviceSn}'}'
                      ' · ${_formatTime(log.opTime)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.onSurfaceVariant(context),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _ResultChip(result: log.result),
            ],
          ),
        ),
      ),
    );
  }
}

/// 类型图标 + 圆底（详情/菜单头部复用）
class _TypeBadge extends StatelessWidget {
  final String source;

  const _TypeBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final accent = OpLogItem.sourceColor(context, source);
    return Container(
      width: 40.w,
      height: 40.w,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        OpLogItem.sourceIcon(source),
        size: 20.sp,
        color: accent,
      ),
    );
  }
}

/// 详情字段行：标签 + 值（可附带复制按钮）
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? chipColor;
  final VoidCallback? onCopy;

  const _DetailRow({
    required this.label,
    required this.value,
    this.chipColor,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor =
        chipColor ?? AppColor.onSurface(context);
    final valueWidget = chipColor != null
        ? Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: chipColor!.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: chipColor,
              ),
            ),
          )
        : Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64.w,
          child: Text(
            label,
            style: TextStyle(fontSize: 13.sp, color: AppColor.onSurfaceVariant(context)),
          ),
        ),
        Expanded(child: valueWidget),
        if (onCopy != null)
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(8.r),
            child: Padding(
              padding: EdgeInsets.all(4.w),
              child: Icon(
                Icons.copy_rounded,
                size: 16.sp,
                color: AppColor.onSurfaceVariant(context),
              ),
            ),
          ),
      ],
    );
  }
}

/// 长按操作菜单项
class _ActionSheetItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionSheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Row(
          children: [
            Icon(icon, size: 20.sp, color: AppColor.onSurfaceVariant(context)),
            SizedBox(width: 12.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColor.onSurface(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final String result;

  const _ResultChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = OpLogItem.resultColor(context, result);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        OpLogItem.resultLabel(l10n, result),
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 本地时间格式化：yyyy-MM-dd HH:mm
String _formatTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
