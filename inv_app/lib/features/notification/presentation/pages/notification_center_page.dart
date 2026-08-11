import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/core/services/notification_stream_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  AlarmState? _cachedAlarmState;
  final NotificationStreamService _streamService = NotificationStreamService();
  StreamSubscription<Map<String, dynamic>>? _sseSubscription;
  // 系统通知批量管理模式（长按菜单进入）：按后端通知 id 勾选
  bool _batchMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    context.read<AlarmBloc>().add(const AlarmListRequested());
    context.read<NotificationBloc>().add(const SystemNotificationsRequested());

    // 先注册 SSE listener
    _sseSubscription =
        _streamService.notificationStream.listen(_onSseNotification);

    // 再启动 SSE 连接
    _startSSEConnection();
  }

  void _onSseNotification(Map<String, dynamic> notificationData) {
    debugPrint(
      '[NotificationCenter] Received real-time notification: $notificationData',
    );
    if (!mounted) return;
    // 同时刷新 BLoC 数据
    _refreshAll();
  }

  Future<void> _startSSEConnection() async {
    try {
      final storageService = getIt<StorageService>();
      final token = await storageService.getToken();
      if (token != null && token.isNotEmpty) {
        await _streamService.start(token: token);
      }
    } catch (e) {
      debugPrint('[NotificationCenter] Failed to start SSE connection: $e');
    }
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _streamService.stop();
    super.dispose();
  }

  void _refreshAll() {
    context.read<AlarmBloc>().add(const AlarmListRequested());
    context.read<NotificationBloc>().add(const SystemNotificationsRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _batchMode ? l10n.str('notif_batch_select') : l10n.notificationCenter,
        ),
        actions: [
          if (_batchMode)
            TextButton(
              onPressed: _exitBatchMode,
              child: Text(
                l10n.str('notif_done'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<AlarmBloc, AlarmState>(
            listener: (context, state) {
              if (state is AlarmListLoaded) {
                _cachedAlarmState = state;
              }
              if (state is AlarmError && _cachedAlarmState == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.translateError(state.message)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
        child: BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, alarmState) {
            return BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, notifState) {
                final isLoading = (alarmState is AlarmLoading ||
                        alarmState is AlarmInitial) &&
                    (notifState is NotificationInitial);
                final hasError = alarmState is AlarmError &&
                    _cachedAlarmState == null &&
                    notifState is NotificationError;

                if (isLoading && _cachedAlarmState == null) {
                  return _buildSkeletonList();
                }

                if (hasError) {
                  return _buildErrorState(
                    l10n.translateError(alarmState.message),
                    _refreshAll,
                    l10n,
                  );
                }

                // 合并告警和系统通知，按时间倒序
                final items = _mergeItems(alarmState, notifState);

                if (items.isEmpty) {
                  return _buildEmptyState(
                    l10n.noNotifications,
                  );
                }

                return Column(
                  children: [
                    if (_cachedAlarmState is AlarmListLoaded &&
                        (_cachedAlarmState as AlarmListLoaded).isFromCache)
                      OfflineDataBanner(onRetry: _refreshAll),
                    Expanded(
                      child: StyledRefreshIndicator(
                        onRefresh: () async => _refreshAll(),
                        child: ListView.builder(
                          padding: EdgeInsets.all(12.w),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _buildItemCard(context, items[index], l10n),
                        ),
                      ),
                    ),
                    if (_batchMode)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
                          child: FilledButton.icon(
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () => _deleteSelected(notifState),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.error,
                              minimumSize: Size.fromHeight(48.h),
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(
                              l10n.str(
                                'notif_delete_selected',
                                {'count': '${_selectedIds.length}'},
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ==================== 数据合并 ====================

  List<_NotificationItem> _mergeItems(
    AlarmState alarmState,
    NotificationState notifState,
  ) {
    final items = <_NotificationItem>[];

    // 添加告警
    if (alarmState is AlarmListLoaded) {
      for (final alarm in alarmState.alarms) {
        final occurredAt = alarm['occurred_at'] as String? ?? '';
        DateTime? timestamp = DateTime.tryParse(occurredAt);
        timestamp ??= DateTime.now();
        items.add(
          _NotificationItem(
            type: _ItemType.alarm,
            timestamp: timestamp,
            data: alarm,
          ),
        );
      }
    } else if (_cachedAlarmState is AlarmListLoaded) {
      for (final alarm in (_cachedAlarmState as AlarmListLoaded).alarms) {
        final occurredAt = alarm['occurred_at'] as String? ?? '';
        DateTime? timestamp = DateTime.tryParse(occurredAt);
        timestamp ??= DateTime.now();
        items.add(
          _NotificationItem(
            type: _ItemType.alarm,
            timestamp: timestamp,
            data: alarm,
          ),
        );
      }
    }

    // 添加系统通知
    if (notifState is SystemNotificationsLoaded) {
      for (final notif in notifState.notifications) {
        items.add(
          _NotificationItem(
            type: _ItemType.system,
            timestamp: notif.timestamp,
            data: notif,
          ),
        );
      }
    }

    // 按时间倒序排列
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  // ==================== 通用组件 ====================

  Widget _buildEmptyState(String message) {
    // 空告警插画：无通知引导态（美术路由 empty-alarms）
    return ListView(
      children: [
        SizedBox(height: 48.h),
        XiaoshuoStatePanel(
          asset: CsergyAssets.emptyAlarm,
          title: message,
          size: 176,
        ),
      ],
    );
  }

  Widget _buildErrorState(
    String message,
    VoidCallback onRetry,
    AppLocalizations l10n,
  ) {
    // 小烁警告动作插画：加载失败态（美术路由 C6/network-error）
    return XiaoshuoStatePanel(
      asset: CsergyAssets.xiaoshuoWarning,
      title: message,
      message: l10n.loadFailed,
      size: 176,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: Text(l10n.retry),
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: 8,
      itemBuilder: (context, index) => const SkeletonListItem(),
    );
  }

  // ==================== 长按操作菜单 ====================

  /// 进入批量管理模式：清空勾选，AppBar 显示完成按钮
  void _enterBatchMode() {
    setState(() {
      _batchMode = true;
      _selectedIds.clear();
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11.r),
                ),
                child: Icon(icon, color: color, size: 20.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet(List<Widget> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        // 小屏/大字体下可滚动，避免操作项溢出（内容不超限时视觉不变）
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tiles,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 系统通知长按菜单：删除单条 / 清空全部 / 批量管理
  void _showSystemNotificationMenu(SystemNotification notification) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _buildBottomSheet([
        _buildMenuTile(
          icon: Icons.delete_outline,
          color: AppColors.error,
          title: l10n.str('notif_delete'),
          onTap: () {
            Navigator.pop(ctx);
            _confirmDeleteNotification(notification);
          },
        ),
        _buildMenuTile(
          icon: Icons.delete_sweep_outlined,
          color: AppColors.error,
          title: l10n.str('notif_clear_all'),
          onTap: () {
            Navigator.pop(ctx);
            _confirmClearAll();
          },
        ),
        _buildMenuTile(
          icon: Icons.delete_sweep_outlined,
          color: AppColors.error,
          title: l10n.str('notif_batch_manage'),
          onTap: () {
            Navigator.pop(ctx);
            _enterBatchMode();
          },
        ),
      ]),
    );
  }

  /// 告警长按菜单：仅标记已处理（后端无 DELETE /alarms/:id，不提供删除）
  void _showAlarmMenu(dynamic alarm) {
    final l10n = AppLocalizations.of(context)!;
    final alarmId = alarm['id'];
    if (alarmId is! int) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _buildBottomSheet([
        _buildMenuTile(
          icon: Icons.done_all,
          color: AppColors.success,
          title: l10n.str('notif_mark_handled'),
          onTap: () {
            Navigator.pop(ctx);
            context.read<AlarmBloc>().add(
                  AlarmMarkReadRequested(alarmIds: [alarmId]),
                );
          },
        ),
      ]),
    );
  }

  Future<void> _confirmDeleteNotification(
    SystemNotification notification,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('notif_delete')),
        content: Text(l10n.str('notif_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<NotificationBloc>().add(
            SystemNotificationDeleteRequested(notification: notification),
          );
    }
  }

  Future<void> _confirmClearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('notif_clear_all')),
        content: Text(l10n.str('notif_clear_all_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.str('notif_clear_all'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context
          .read<NotificationBloc>()
          .add(const SystemNotificationsClearRequested());
    }
  }

  /// 批量删除所选：逐条调删除事件（通知量小，pageSize 50 内可接受）
  Future<void> _deleteSelected(NotificationState notifState) async {
    // 批量勾选仅针对后端通知（本地通知无 id），此处必须已加载完成
    if (notifState is! SystemNotificationsLoaded) return;
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.str('notif_delete_selected', {'count': '$count'})),
        content: Text(
          l10n.str(
            'notif_delete_selected_confirm',
            {'count': '$count'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      for (final id in _selectedIds) {
        final matches =
            notifState.notifications.where((n) => n.id == id).toList();
        if (matches.isNotEmpty) {
          context.read<NotificationBloc>().add(
                SystemNotificationDeleteRequested(
                  notification: matches.first,
                ),
              );
        }
      }
      _exitBatchMode();
    }
  }

  // ==================== 统一卡片 ====================

  String _levelToSeverity(dynamic level) {
    switch (level) {
      case 3:
        return 'fault';
      case 2:
        return 'warning';
      case 1:
        return 'info';
      default:
        return 'normal'; // code=0, normal/恢复
    }
  }

  Widget _buildItemCard(
    BuildContext context,
    _NotificationItem item,
    AppLocalizations l10n,
  ) {
    if (item.type == _ItemType.alarm) {
      return _buildAlarmCard(
        context,
        item.data as Map<String, dynamic>,
        l10n,
        item.timestamp,
      );
    } else {
      return _buildSystemCard(
        context,
        item.data as SystemNotification,
        l10n,
        item.timestamp,
      );
    }
  }

  Widget _buildAlarmCard(
    BuildContext context,
    dynamic alarm,
    AppLocalizations l10n,
    DateTime timestamp,
  ) {
    final faultCode = alarm['fault_code'];
    int parsedCode = -1;
    if (faultCode is int) {
      parsedCode = faultCode;
    } else if (faultCode != null) {
      final str = faultCode.toString();
      if (str.startsWith('0x') || str.startsWith('0X')) {
        parsedCode = int.tryParse(str.substring(2), radix: 16) ?? -1;
      } else {
        parsedCode = int.tryParse(str) ?? -1;
      }
    }
    final alarmEntry =
        parsedCode >= 0 ? AlarmCodeMapping.getEntry(parsedCode) : null;
    final severity =
        alarmEntry?.severity ?? _levelToSeverity(alarm['alarm_level']);

    Color levelColor;
    String levelText;
    IconData iconData;
    switch (severity) {
      case 'fault':
        levelColor = AppColors.errorLight;
        levelText = l10n.severe;
        iconData = Icons.error_outline;
        break;
      case 'warning':
        levelColor = AppColors.warning;
        levelText = l10n.warningLevel;
        iconData = Icons.warning_amber_rounded;
        break;
      case 'info':
        levelColor = AppColors.blue;
        levelText = l10n.infoLevel;
        iconData = Icons.info_outline;
        break;
      case 'normal':
        levelColor = AppColors.success;
        levelText = l10n.normal;
        iconData = Icons.check_circle_outline;
        break;
      default:
        levelColor = AppColors.textHint;
        levelText = l10n.general;
        iconData = Icons.notifications_none;
    }

    final isRead = alarm['status'] == 1;

    return Opacity(
      // 批量删除模式：告警不支持批量删除，置灰并提示
      opacity: _batchMode ? 0.45 : 1,
      child: _LongPressFeedbackCard(
        margin: EdgeInsets.only(bottom: 8.h),
        baseColor: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        onTap: () {
          if (_batchMode) {
            // 告警不支持批量删除，点击仅提示
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.str('notif_alarm_no_batch_delete')),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          context.push('/alarm/${alarm['id']}');
        },
        onLongPress: () => _showAlarmMenu(alarm),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: (isRead ? AppColors.textHint : levelColor)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  isRead ? Icons.notifications_none : iconData,
                  size: 18.sp,
                  color: isRead ? AppColors.textHint : levelColor,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alarm['fault_message'] ?? l10n.alarm,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight:
                                  isRead ? FontWeight.w500 : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            levelText,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: levelColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${l10n.deviceLabel}: ${alarm['device_sn'] ?? '-'}  ${l10n.faultCodeLabel}: ${alarm['fault_code'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                        Text(
                          _formatTime(timestamp, l10n),
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textHint, size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemCard(
    BuildContext context,
    SystemNotification notification,
    AppLocalizations l10n,
    DateTime timestamp,
  ) {
    final IconData icon;
    final Color iconColor;

    switch (notification.type) {
      case SystemNotificationType.deviceOnline:
        icon = Icons.check_circle_outline;
        iconColor = AppColors.success;
        break;
      case SystemNotificationType.deviceOffline:
        icon = Icons.highlight_off;
        iconColor = AppColors.errorLight;
        break;
      case SystemNotificationType.deviceFault:
        icon = Icons.error_outline;
        iconColor = AppColors.errorLight;
        break;
      case SystemNotificationType.alarmCleared:
        icon = Icons.check_circle_outline;
        iconColor = AppColors.success;
        break;
      case SystemNotificationType.otaAvailable:
        icon = Icons.system_update;
        iconColor = AppColors.primary;
        break;
      case SystemNotificationType.appUpdate:
        icon = Icons.download;
        iconColor = AppColors.purple;
        break;
    }

    return _LongPressFeedbackCard(
      margin: EdgeInsets.only(bottom: 8.h),
      baseColor: AppColor.surfaceContainer(context),
      borderRadius: BorderRadius.circular(14.r),
      // 批量模式：选中整卡高亮（背景过渡 + 主色描边，替代右侧勾选圆圈）
      selected: _batchMode &&
          notification.id != null &&
          _selectedIds.contains(notification.id),
      // 批量模式：点击切换勾选（仅后端通知可勾选）；长按弹操作菜单
      onTap: _batchMode && notification.id != null
          ? () => _toggleSelect(notification.id!)
          : null,
      onLongPress: () => _showSystemNotificationMenu(notification),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, size: 18.sp, color: iconColor),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _notificationTitle(notification, l10n),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _notificationSubtitle(notification, l10n),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Text(
                        _formatTime(timestamp, l10n),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 批量模式选中态已由整卡高亮表达，右侧不再显示勾选圆圈
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time, AppLocalizations l10n) {
    return TimezoneUtils.formatRelativeTime(
      time.toUtc().toIso8601String(),
      l10n: l10n,
    );
  }

  String _notificationTitle(
    SystemNotification notification,
    AppLocalizations l10n,
  ) {
    if (notification.type == SystemNotificationType.otaAvailable) {
      return l10n.firmwareUpgrade;
    }
    if (notification.type == SystemNotificationType.appUpdate) {
      final version = notification.version ??
          RegExp(r'v([^\s]+)').firstMatch(notification.title)?.group(1) ??
          '';
      return version.isEmpty
          ? l10n.newVersionFound
          : l10n.notifyAppUpdate(version);
    }
    return notification.title;
  }

  String _notificationSubtitle(
    SystemNotification notification,
    AppLocalizations l10n,
  ) {
    if (notification.type == SystemNotificationType.otaAvailable) {
      return l10n.notifyOtaAvailable(notification.deviceSn ?? l10n.device);
    }
    if (notification.type == SystemNotificationType.appUpdate &&
        notification.subtitle.isEmpty) {
      return l10n.updateDetailsHint;
    }
    return notification.subtitle;
  }
}

// ==================== 长按反馈卡片 ====================
//
// 按下立即缩放 + 主色高亮，长按达成回弹加深形成"确认脉冲"，
// 让用户明确感知正在长按的是哪一条通知；点击/长按复用同一按压反馈。
class _LongPressFeedbackCard extends StatefulWidget {
  const _LongPressFeedbackCard({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.baseColor,
    this.margin,
    this.selected = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? baseColor;
  final EdgeInsetsGeometry? margin;
  /// 批量选中态：整卡主色背景 + 描边高亮（优先于按压高亮）
  final bool selected;
  final BorderRadiusGeometry borderRadius;

  @override
  State<_LongPressFeedbackCard> createState() =>
      _LongPressFeedbackCardState();
}

class _LongPressFeedbackCardState extends State<_LongPressFeedbackCard> {
  /// 手指按下（按压中缩放 + 高亮）
  bool _pressed = false;

  /// 长按达成（回弹 + 高亮加深，提示菜单即将弹出）
  bool _confirmed = false;

  void _reset() {
    if (!_pressed && !_confirmed) return;
    setState(() {
      _pressed = false;
      _confirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? AppColor.surfaceContainer(context);
    return GestureDetector(
      // onTapDown 独立注册：点击与长按按下瞬间即反馈
      onTapDown: (_) {
        if (!_pressed) setState(() => _pressed = true);
      },
      onTapUp: (_) {
        _reset();
        widget.onTap?.call();
      },
      onTapCancel: () {
        // 长按达成后 tap 竞技场失败会触发 cancel，此时保持按压态直至松手
        if (!_confirmed) _reset();
      },
      onLongPress: () {
        setState(() {
          _pressed = true;
          _confirmed = true;
        });
        widget.onLongPress?.call();
      },
      onLongPressCancel: _reset,
      onLongPressUp: _reset,
      child: AnimatedScale(
        // 长按达成回弹：0.97 -> 1.0，动画略慢形成"确认脉冲"
        scale: _confirmed ? 1.0 : (_pressed ? 0.97 : 1.0),
        duration: Duration(milliseconds: _confirmed ? 220 : 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: widget.margin,
          decoration: BoxDecoration(
            // 选中态优先于按压高亮；长按达成提示保留最高优先级
            color: _confirmed
                ? AppColors.primary.withValues(alpha: 0.12)
                : (widget.selected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : (_pressed
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : baseColor)),
            borderRadius: widget.borderRadius,
            // 选中态整卡主色描边 1.5px
            border: widget.selected
                ? Border.all(color: AppColors.primary, width: 1.5)
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ==================== 内部数据模型 ====================

enum _ItemType { alarm, system }

class _NotificationItem {
  final _ItemType type;
  final DateTime timestamp;
  final dynamic data;

  const _NotificationItem({
    required this.type,
    required this.timestamp,
    required this.data,
  });
}
