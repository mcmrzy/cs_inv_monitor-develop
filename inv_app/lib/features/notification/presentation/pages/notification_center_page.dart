import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
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
  int _sseNotificationCount = 0; // 用于强制触发 UI 重建

  @override
  void initState() {
    super.initState();
    context.read<AlarmBloc>().add(const AlarmListRequested());
    context.read<NotificationBloc>().add(const SystemNotificationsRequested());
    
    // 先注册 SSE listener
    _sseSubscription = _streamService.notificationStream.listen(_onSseNotification);
    
    // 再启动 SSE 连接
    _startSSEConnection();
  }

  void _onSseNotification(Map<String, dynamic> notificationData) {
    debugPrint('[NotificationCenter] Received real-time notification: $notificationData');
    if (!mounted) return;
    // 递增计数器并 setState，强制触发 UI 重建
    setState(() {
      _sseNotificationCount++;
    });
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
        title: Text(l10n.notificationCenter),
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
                  SnackBar(content: Text(l10n.translateError(state.message)), duration: const Duration(seconds: 2)),
                );
              }
            },
          ),
        ],
        child: BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, alarmState) {
            return BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, notifState) {
                final isLoading = (alarmState is AlarmLoading || alarmState is AlarmInitial) &&
                    (notifState is NotificationInitial);
                final hasError = alarmState is AlarmError && _cachedAlarmState == null &&
                    notifState is NotificationError;

                if (isLoading && _cachedAlarmState == null) {
                  return _buildSkeletonList();
                }

                if (hasError) {
                  return _buildErrorState(
                    l10n.translateError((alarmState as AlarmError).message),
                    _refreshAll,
                    l10n,
                  );
                }

                // 合并告警和系统通知，按时间倒序
                final items = _mergeItems(alarmState, notifState);

                if (items.isEmpty) {
                  return _buildEmptyState(Icons.notifications_none, l10n.noNotifications);
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
                          itemBuilder: (context, index) => _buildItemCard(context, items[index], l10n),
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

  List<_NotificationItem> _mergeItems(AlarmState alarmState, NotificationState notifState) {
    final items = <_NotificationItem>[];

    // 添加告警
    if (alarmState is AlarmListLoaded) {
      for (final alarm in alarmState.alarms) {
        final occurredAt = alarm['occurred_at'] as String? ?? '';
        DateTime? timestamp = DateTime.tryParse(occurredAt);
        timestamp ??= DateTime.now();
        items.add(_NotificationItem(
          type: _ItemType.alarm,
          timestamp: timestamp,
          data: alarm,
        ));
      }
    } else if (_cachedAlarmState is AlarmListLoaded) {
      for (final alarm in (_cachedAlarmState as AlarmListLoaded).alarms) {
        final occurredAt = alarm['occurred_at'] as String? ?? '';
        DateTime? timestamp = DateTime.tryParse(occurredAt);
        timestamp ??= DateTime.now();
        items.add(_NotificationItem(
          type: _ItemType.alarm,
          timestamp: timestamp,
          data: alarm,
        ));
      }
    }

    // 添加系统通知
    if (notifState is SystemNotificationsLoaded) {
      for (final notif in notifState.notifications) {
        items.add(_NotificationItem(
          type: _ItemType.system,
          timestamp: notif.timestamp,
          data: notif,
        ));
      }
    }

    // 按时间倒序排列
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  // ==================== 通用组件 ====================

  Widget _buildEmptyState(IconData icon, String message) {
    return ListView(
      children: [
        SizedBox(height: 120.h),
        Center(
          child: Column(
            children: [
              Icon(icon, size: 64.sp, color: AppColors.textHint),
              SizedBox(height: 16.h),
              Text(message, style: TextStyle(color: AppColors.textHint, fontSize: 16.sp)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48.sp, color: AppColors.textHint),
          SizedBox(height: 12.h),
          Text(message, style: TextStyle(color: AppColors.textSecondary)),
          SizedBox(height: 12.h),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ],
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

  Widget _buildItemCard(BuildContext context, _NotificationItem item, AppLocalizations l10n) {
    if (item.type == _ItemType.alarm) {
      return _buildAlarmCard(context, item.data as Map<String, dynamic>, l10n, item.timestamp);
    } else {
      return _buildSystemCard(context, item.data as SystemNotification, l10n, item.timestamp);
    }
  }

  Widget _buildAlarmCard(BuildContext context, dynamic alarm, AppLocalizations l10n, DateTime timestamp) {
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
    final alarmEntry = parsedCode >= 0 ? AlarmCodeMapping.getEntry(parsedCode) : null;
    final severity = alarmEntry?.severity ?? _levelToSeverity(alarm['alarm_level']);

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
        levelText = '正常';
        iconData = Icons.check_circle_outline;
        break;
      default:
        levelColor = AppColors.textHint;
        levelText = l10n.general;
        iconData = Icons.notifications_none;
    }

    final isRead = alarm['status'] == 1;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: InkWell(
        onTap: () => context.push('/alarm/${alarm['id']}'),
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  color: (isRead ? AppColors.textHint : levelColor).withValues(alpha: 0.1),
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
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(levelText, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: levelColor)),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${l10n.deviceLabel}: ${alarm['device_sn'] ?? '-'}  ${l10n.faultCodeLabel}: ${alarm['fault_code'] ?? '-'}',
                            style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                          ),
                        ),
                        Text(
                          _formatTime(timestamp, l10n),
                          style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
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

  Widget _buildSystemCard(BuildContext context, SystemNotification notification, AppLocalizations l10n, DateTime timestamp) {
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

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14.r),
      ),
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
                    notification.title,
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
                          notification.subtitle,
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                        ),
                      ),
                      Text(
                        _formatTime(timestamp, l10n),
                        style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
