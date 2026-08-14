import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/widgets/jiggle_once.dart';
import 'package:inv_app/core/widgets/pressable_gesture_detector.dart';
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

class _NotificationCenterPageState extends State<NotificationCenterPage>
    with SingleTickerProviderStateMixin {
  AlarmState? _cachedAlarmState;
  final NotificationStreamService _streamService = NotificationStreamService();
  StreamSubscription<Map<String, dynamic>>? _sseSubscription;
  // 系统通知批量管理模式（长按菜单进入）：告警与通知分别按 id 勾选（两类 id 可能冲突）
  bool _batchMode = false;
  final Set<int> _selectedNotifIds = {};
  final Set<int> _selectedAlarmIds = {};
  // t02 批量删除动画：缩小淡出驱动 + 正在移除的条目 key（'alarm:<id>' / 'notif:<id>'）
  late final AnimationController _removeCtl;
  final Set<String> _removingKeys = {};
  // 待删除快照（缩小淡出动画结束后再发删除请求）：告警 id + 系统通知实体
  List<int> _pendingDeleteAlarmIds = const [];
  List<SystemNotification> _pendingDeleteNotifications = const [];

  @override
  void initState() {
    super.initState();
    _removeCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addStatusListener(_handleRemoveStatus);
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
    _removeCtl.dispose();
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
                          itemBuilder: (context, index) => _buildItemCard(
                            context,
                            items[index],
                            l10n,
                            index: index,
                            batchMode: _batchMode,
                          ),
                        ),
                      ),
                    ),
                    if (_batchMode)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
                          child: FilledButton.icon(
                            onPressed: _selectedNotifIds.isEmpty &&
                                    _selectedAlarmIds.isEmpty
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
                                {
                                  'count':
                                      '${_selectedNotifIds.length + _selectedAlarmIds.length}',
                                },
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
      _selectedNotifIds.clear();
      _selectedAlarmIds.clear();
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedNotifIds.clear();
      _selectedAlarmIds.clear();
    });
  }

  void _toggleSelect(int id, {required bool isAlarm}) {
    setState(() {
      if (isAlarm) {
        if (!_selectedAlarmIds.add(id)) _selectedAlarmIds.remove(id);
      } else {
        if (!_selectedNotifIds.add(id)) _selectedNotifIds.remove(id);
      }
    });
  }

  /// 菜单操作项（样式对齐电站/设备长按弹窗 DeviceActionSheet：
  /// 44w 纯色图标容器 + 标题/副标题 + 右箭头，无渐变阴影）
  Widget _buildMenuTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  color: color.withValues(alpha: 0.1),
                ),
                child: Icon(icon, color: color, size: 22.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14.sp,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet({
    Widget? header,
    required List<Widget Function(int)> tileBuilders,
  }) {
    return _AnimatedMenuSheet(header: header, tileBuilders: tileBuilders);
  }

  /// 弹窗顶部消息头：左图标 + 右大SN + 下方通知标题（与菜单项左缘对齐）
  Widget _buildSheetHeader({
    required String title,
    String? subtitle,
    String? deviceSn,
    bool isAlarm = false,
  }) {
    // 图标按通知类型选：告警→warning(error色)；系统→notifications(primary色)
    final iconData = isAlarm ? Icons.warning_amber_rounded : Icons.notifications_rounded;
    final iconColor = isAlarm ? AppColors.error : AppColors.primary;
    // 上行显示文本：优先 SN，无 SN 回退 title（不拼设备前缀）
    final hasSn = deviceSn != null && deviceSn.isNotEmpty;
    final primaryText = hasSn ? deviceSn : title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // 与菜单项图标左缘对齐：sheet 20.w + header 4.w = 24.w，图标尺寸/间距同 _buildMenuTile
          padding: EdgeInsets.fromLTRB(4.w, 14.h, 4.w, 10.h),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  color: iconColor.withValues(alpha: 0.1),
                ),
                child: Icon(iconData, size: 22.sp, color: iconColor),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryText,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        SizedBox(height: 6.h),
      ],
    );
  }

  /// 系统通知长按菜单：删除单条 / 清空全部 / 批量管理
  void _showSystemNotificationMenu(SystemNotification notification) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _buildBottomSheet(
        header: _buildSheetHeader(
          title: _notificationTitle(notification, l10n),
          subtitle: _notificationTitle(notification, l10n),
          deviceSn: notification.deviceSn,
        ),
        tileBuilders: [
          (_) => _buildMenuTile(
            icon: Icons.delete_outline,
            color: AppColors.error,
            title: l10n.str('notif_delete'),
            subtitle: l10n.str('notif_delete_hint'),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDeleteNotification(notification);
            },
          ),
          (_) => _buildMenuTile(
            icon: Icons.delete_sweep_outlined,
            color: AppColors.error,
            title: l10n.str('notif_clear_all'),
            subtitle: l10n.str('notif_clear_all_hint'),
            onTap: () {
              Navigator.pop(ctx);
              _confirmClearAll();
            },
          ),
          (_) => _buildMenuTile(
            // 批量管理是模式入口而非删除操作：主题色 + 多选图标（与设备弹窗语义色一致）
            icon: Icons.checklist_rounded,
            color: AppColors.primary,
            title: l10n.str('notif_batch_manage'),
            subtitle: l10n.str('notif_batch_manage_hint'),
            onTap: () {
              Navigator.pop(ctx);
              _enterBatchMode();
            },
          ),
        ],
      ),
    );
  }

  /// 告警长按菜单：标记已处理 / 删除单条（后端 DELETE /alarms/:id）
  void _showAlarmMenu(dynamic alarm) {
    final l10n = AppLocalizations.of(context)!;
    final alarmId = alarm['id'];
    if (alarmId is! int) return;
    final alarmTitle = (alarm['fault_message'] ?? l10n.alarm).toString();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _buildBottomSheet(
        header: _buildSheetHeader(
          title: alarmTitle,
          subtitle: (alarm['fault_message'] ?? '').toString() != alarmTitle
              ? (alarm['fault_message'] ?? '').toString()
              : null,
          deviceSn: (alarm['device_sn'] ?? '').toString(),
          isAlarm: true,
        ),
        tileBuilders: [
          (_) => _buildMenuTile(
            icon: Icons.done_all,
            color: AppColors.success,
            title: l10n.str('notif_mark_handled'),
            subtitle: l10n.str('notif_mark_handled_hint'),
            onTap: () {
              Navigator.pop(ctx);
              context.read<AlarmBloc>().add(
                    AlarmMarkReadRequested(alarmIds: [alarmId]),
                  );
            },
          ),
          (_) => _buildMenuTile(
            icon: Icons.delete_outline,
            color: AppColors.error,
            title: l10n.str('notif_delete'),
            subtitle: l10n.str('notif_delete_hint'),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDeleteAlarm(alarmId);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAlarm(int alarmId) async {
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
      context.read<AlarmBloc>().add(AlarmDeleteRequested(alarmId: alarmId));
    }
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

  /// 批量删除所选：先播放卡片缩小淡出动画，动画结束后再逐条删除
  /// （告警与通知分别删除，量小，pageSize 50 内可接受）
  Future<void> _deleteSelected(NotificationState notifState) async {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedNotifIds.length + _selectedAlarmIds.length;
    if (count == 0) return;
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
      // 动画前快照：防止动画期间退出批量模式导致待删集合被清空
      _pendingDeleteAlarmIds = List<int>.of(_selectedAlarmIds);
      _pendingDeleteNotifications = notifState is SystemNotificationsLoaded
          ? notifState.notifications
              .where((n) => _selectedNotifIds.contains(n.id))
              .toList()
          : const [];
      setState(() {
        for (final id in _pendingDeleteAlarmIds) {
          _removingKeys.add('alarm:$id');
        }
        for (final n in _pendingDeleteNotifications) {
          _removingKeys.add('notif:${n.id}');
        }
      });
      // 卡片缩小淡出移除动画，结束后在 _finishRemoveAnimation 里发删除请求
      _removeCtl.forward(from: 0);
    }
  }

  /// 缩小淡出动画结束：清空移除标记、退出批量模式并真正发送删除请求
  void _finishRemoveAnimation() {
    if (!mounted) return;
    final alarmIds = _pendingDeleteAlarmIds;
    final notifications = _pendingDeleteNotifications;
    _pendingDeleteAlarmIds = const [];
    _pendingDeleteNotifications = const [];
    setState(() => _removingKeys.clear());
    _exitBatchMode();
    // 告警逐条删除（按 id，无需完整实体）
    for (final id in alarmIds) {
      context.read<AlarmBloc>().add(AlarmDeleteRequested(alarmId: id));
    }
    // 通知逐条删除（从动画前快照取完整实体）
    for (final n in notifications) {
      context.read<NotificationBloc>().add(
            SystemNotificationDeleteRequested(notification: n),
          );
    }
  }

  /// 缩小淡出动画结束回调
  void _handleRemoveStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishRemoveAnimation();
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
    AppLocalizations l10n, {
    required int index,
    required bool batchMode,
  }) {
    Widget card;
    if (item.type == _ItemType.alarm) {
      card = _buildAlarmCard(
        context,
        item.data as Map<String, dynamic>,
        l10n,
        item.timestamp,
      );
    } else {
      card = _buildSystemCard(
        context,
        item.data as SystemNotification,
        l10n,
        item.timestamp,
      );
    }
    // 进入批量模式：卡片错相位持续抖动，提示可多选
    if (batchMode) {
      card = JiggleOnce(active: batchMode, index: index, child: card);
    }
    // 批量删除：卡片缩小 + 淡出移除动画
    if (_removingKeys.contains(_itemKey(item))) {
      card = AnimatedBuilder(
        animation: _removeCtl,
        builder: (context, child) => Opacity(
          opacity: 1 - _removeCtl.value,
          child: Transform.scale(
            scale: 1 - 0.2 * _removeCtl.value,
            child: child,
          ),
        ),
        child: card,
      );
    }
    return card;
  }

  /// 条目唯一 key：告警/通知 id 类型不同可能冲突，加前缀区分
  String _itemKey(_NotificationItem item) {
    if (item.type == _ItemType.alarm) {
      return 'alarm:${(item.data as Map<String, dynamic>)['id']}';
    }
    return 'notif:${(item.data as SystemNotification).id}';
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
    final alarmId = alarm['id'];

    return _LongPressFeedbackCard(
      margin: EdgeInsets.only(bottom: 8.h),
      baseColor: AppColor.surfaceContainer(context),
      borderRadius: BorderRadius.circular(14.r),
      // 批量模式：选中整卡高亮（与系统通知卡片一致），告警与通知均参与勾选
      selected:
          _batchMode && alarmId is int && _selectedAlarmIds.contains(alarmId),
      // 批量模式：点击切换勾选；非批量：进入告警详情
      onTap: _batchMode
          ? (alarmId is int
              ? () => _toggleSelect(alarmId, isAlarm: true)
              : null)
          : () => context.push('/alarm/$alarmId'),
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
          _selectedNotifIds.contains(notification.id),
      // 批量模式：点击切换勾选（仅后端通知可勾选）；长按弹操作菜单
      onTap: _batchMode && notification.id != null
          ? () => _toggleSelect(notification.id!, isAlarm: false)
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
    return PressableGestureDetector(
      // 长按 300ms 达成（与电站/设备卡片手感一致，比默认 500ms 更灵敏）
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
            color: widget.selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : baseColor,
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

// ==================== 弹窗逐项入场动画 ====================
//
// 长按菜单底部弹窗：操作项逐项淡入 + 上移（与设备弹窗动画一致）

class _AnimatedMenuSheet extends StatefulWidget {
  final Widget? header;
  final List<Widget Function(int)> tileBuilders;

  const _AnimatedMenuSheet({this.header, required this.tileBuilders});

  @override
  State<_AnimatedMenuSheet> createState() => _AnimatedMenuSheetState();
}

class _AnimatedMenuSheetState extends State<_AnimatedMenuSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  // 逐项入场动画（淡入 + 上移），间隔 0.15
  Widget _animatedItem(int i, Widget child) {
    final start = i * 0.15;
    final end = (start + 0.7).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _ctl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              // 与设备弹窗一致：左右 20w、底部 20h（含取消按钮区）
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.header != null) widget.header!,
                  ...List.generate(
                    widget.tileBuilders.length,
                    (i) => _animatedItem(i, widget.tileBuilders[i](i)),
                  ),
                  SizedBox(height: 14.h),
                  // 取消按钮（样式对齐设备弹窗：48h 圆角底 + 次级文字）
                  _animatedItem(
                    widget.tileBuilders.length,
                    Material(
                      color: AppColor.surfaceHover(context),
                      borderRadius: BorderRadius.circular(14.r),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14.r),
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          height: 48.h,
                          alignment: Alignment.center,
                          child: Text(
                            AppLocalizations.of(context)!.cancel,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
