import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/widget_update_service.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/notification/data/datasources/notification_remote_data_source.dart';

part 'notification_event.dart';
part 'notification_state.dart';

enum SystemNotificationType {
  deviceOnline,
  deviceOffline,
  deviceFault, // 设备故障
  alarmCleared, // 告警清除/故障恢复
  otaAvailable,
  appUpdate,
}

class SystemNotification {
  final SystemNotificationType type;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String? deviceSn;
  final String? version;
  final int? id; // 后端通知ID
  final bool fromBackend; // 是否来自后端

  const SystemNotification({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.deviceSn,
    this.version,
    this.id,
    this.fromBackend = false,
  });

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'title': title,
        'subtitle': subtitle,
        'timestamp': timestamp.toIso8601String(),
        'deviceSn': deviceSn,
        'version': version,
      };

  factory SystemNotification.fromJson(Map<String, dynamic> json) {
    // type 是枚举 index：历史版本写入了已删除的枚举值时，
    // 直接取 values[...] 会 RangeError，越界回退 deviceOnline（上线通知语义最中性）
    final typeIndex = json['type'] is int ? json['type'] as int : -1;
    final type = typeIndex >= 0 &&
            typeIndex < SystemNotificationType.values.length
        ? SystemNotificationType.values[typeIndex]
        : SystemNotificationType.deviceOnline;
    final title = json['title'] as String? ?? '';
    final legacyVersion = type == SystemNotificationType.appUpdate
        ? RegExp(r'v([^\s]+)').firstMatch(title)?.group(1)
        : null;
    return SystemNotification(
      type: type,
      title: title,
      subtitle: json['subtitle'] as String? ?? '',
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)?.toLocal() ??
              DateTime.now()
          : DateTime.now(),
      deviceSn: json['deviceSn'] as String?,
      version: json['version'] as String? ?? legacyVersion,
    );
  }

  /// 从后端通知API响应创建
  factory SystemNotification.fromBackendJson(Map<String, dynamic> json) {
    final notifyType = json['notify_type'] as String? ?? '';
    SystemNotificationType type;
    switch (notifyType) {
      case 'device_online':
        type = SystemNotificationType.deviceOnline;
        break;
      case 'device_offline':
        type = SystemNotificationType.deviceOffline;
        break;
      case 'device_fault':
        type = SystemNotificationType.deviceFault;
        break;
      case 'alarm_cleared':
        type = SystemNotificationType.alarmCleared;
        break;
      case 'ota_available':
        type = SystemNotificationType.otaAvailable;
        break;
      default:
        type = SystemNotificationType.deviceOnline;
    }

    return SystemNotification(
      id: json['id'] as int?,
      type: type,
      title: json['title'] as String? ?? '',
      subtitle: json['content'] as String? ?? '',
      timestamp: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : DateTime.now(),
      deviceSn: json['device_sn'] as String?,
      fromBackend: true,
    );
  }
}

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final DeviceRepository deviceRepository;
  final RealtimeDataService? realtimeDataService;
  final NotificationRemoteDataSource? notificationDataSource;
  static const _localNotifKey = 'local_notifications'; // 仅存储OTA/APP更新等本地通知

  StreamSubscription<dynamic>? _realtimeSub;
  StreamSubscription<dynamic>? _alarmSub;
  StreamSubscription<dynamic>? _otaSub;
  Timer? _debounceTimer;

  /// 各设备上次的在线状态：实时数据流是周期轮询（约 3s 一条），
  /// 状态未变化时重复触发通知列表刷新纯属浪费，只有翻转时才 add 事件
  final Map<String, bool> _lastOnlineStatus = {};

  NotificationBloc({
    required this.deviceRepository,
    this.realtimeDataService,
    this.notificationDataSource,
  }) : super(NotificationInitial()) {
    on<SystemNotificationsRequested>(_onSystemNotificationsRequested);
    on<SystemNotificationDeleteRequested>(_onSystemNotificationDeleteRequested);
    on<SystemNotificationsClearRequested>(_onSystemNotificationsClearRequested);
    on<_MqttStatusUpdate>(_onMqttStatusUpdate);
    on<JPushNotificationReceived>(_onJPushNotificationReceived);
    on<JPushNotificationTapped>(_onJPushNotificationTapped);
    _subscribeToMqtt();
  }

  void _subscribeToMqtt() {
    // 监听设备实时数据流，触发刷新（后端已自动插入通知）
    _realtimeSub = realtimeDataService?.realtimeDataStream.listen((rt) {
      final online = rt.onlineStatus?.online ?? false;
      // 状态相对上次未变化（轮询流约 3s 一条）不重复刷新，仅翻转时触发
      if (_lastOnlineStatus[rt.deviceSN] == online) return;
      _lastOnlineStatus[rt.deviceSN] = online;
      add(
        _MqttStatusUpdate(
          deviceSn: rt.deviceSN,
          isOnline: online,
        ),
      );
    });

    // 监听告警，触发通知列表刷新
    _alarmSub = realtimeDataService?.alarmStream.listen((_) {
      _debouncedRefresh();
    });

    // OTA 通知通过 JPush 推送，不再需要本地监听
  }

  void _debouncedRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      add(const SystemNotificationsRequested());
    });
  }

  /// MQTT 状态更新时，不再本地生成通知（后端已处理），仅触发刷新
  Future<void> _onMqttStatusUpdate(
    _MqttStatusUpdate event,
    Emitter<NotificationState> emit,
  ) async {
    // 后端 DeviceStatus handler 已自动插入通知记录
    // 这里只触发刷新，从后端拉取最新通知
    _debouncedRefresh();
  }

  /// JPush 推送消息到达时，触发通知列表刷新
  Future<void> _onJPushNotificationReceived(
    JPushNotificationReceived event,
    Emitter<NotificationState> emit,
  ) async {
    debugPrint(
      '[NotificationBloc] JPush received: ${event.notifyType}, deviceSn=${event.deviceSn}',
    );
    _debouncedRefresh();
  }

  /// 用户点击 JPush 通知时，触发通知列表刷新
  Future<void> _onJPushNotificationTapped(
    JPushNotificationTapped event,
    Emitter<NotificationState> emit,
  ) async {
    debugPrint(
      '[NotificationBloc] JPush tapped: ${event.notifyType}, deviceSn=${event.deviceSn}',
    );
    _debouncedRefresh();
  }

  Future<void> _onSystemNotificationsRequested(
    SystemNotificationsRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final List<SystemNotification> allNotifications = [];

    // 1. 从后端获取设备通知（上线/离线等）
    // 首次加载使用较小的pageSize，减少请求数据量
    if (notificationDataSource != null) {
      try {
        final response =
            await notificationDataSource!.getList(page: 1, pageSize: 20);
        final data = response.data;
        if (data != null) {
          final responseData = data['data'] ?? data;
          final items = responseData is Map
              ? (responseData['items'] ?? [])
              : (responseData is List ? responseData : []);
          if (items is List) {
            for (final item in items) {
              if (item is Map<String, dynamic>) {
                allNotifications.add(SystemNotification.fromBackendJson(item));
              }
            }
          }
        }
      } catch (_) {
        // 后端请求失败，继续加载本地通知
      }
    }

    // 2. 加载本地存储的 OTA/APP 更新通知
    // 单条解析失败（版本升级后字段变化等）只跳过该条，不再整批丢弃
    final storage = getIt<StorageService>();
    final storedJson = await storage.getString(_localNotifKey);
    List<SystemNotification> localStored = [];
    if (storedJson != null && storedJson.isNotEmpty) {
      try {
        final decoded = json.decode(storedJson) as List;
        localStored = decoded
            .whereType<Map<String, dynamic>>()
            .map(_tryParseStoredNotification)
            .whereType<SystemNotification>()
            .toList();
      } catch (_) {}
    }

    // 3. 检查 App 更新（首载或手动刷新时检查，见 SystemNotificationsRequested.manual）
    if (event.manual || state is! SystemNotificationsLoaded) {
      try {
        final updateService = getIt<AppUpdateService>();
        final info = await updateService.checkUpdate(AppConfig.versionCode);
        if (info.hasUpdate) {
          final appUpdateNotif = SystemNotification(
            type: SystemNotificationType.appUpdate,
            title: '',
            subtitle: info.changelog,
            timestamp: DateTime.now(),
            version: info.latestVersionName,
          );
          final exists = localStored.any(
            (n) =>
                n.type == SystemNotificationType.appUpdate &&
                n.version == appUpdateNotif.version,
          );
          if (!exists) {
            localStored = [appUpdateNotif, ...localStored];
            final saveJson =
                json.encode(localStored.map((e) => e.toJson()).toList());
            await storage.saveString(_localNotifKey, saveJson);
          }
        }
      } catch (_) {}
    }

    // 4. 合并后端通知和本地通知
    allNotifications.addAll(localStored);

    // 推送通知桌面小组件：最新告警标题 + 告警条数（fire-and-forget）
    _pushNotificationWidget(allNotifications);

    emit(SystemNotificationsLoaded(notifications: allNotifications));
  }

  /// 单条本地缓存通知解析：失败返回 null（调用方跳过该条）
  static SystemNotification? _tryParseStoredNotification(
    Map<String, dynamic> json,
  ) {
    try {
      return SystemNotification.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 将最新告警信息推送到通知桌面小组件
  ///
  /// 告警类通知 = 设备故障/离线/上线/告警清除；未读数语义在 App 端
  /// 无后端支持，用告警类通知条数代替（当前告警规模）。
  void _pushNotificationWidget(List<SystemNotification> notifications) {
    const alarmTypes = {
      SystemNotificationType.deviceFault,
      SystemNotificationType.deviceOffline,
      SystemNotificationType.deviceOnline,
      SystemNotificationType.alarmCleared,
    };
    final alarms = notifications
        .where((n) => alarmTypes.contains(n.type))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    unawaited(
      WidgetUpdateService.updateNotificationWidget(
        latestAlarmTitle: alarms.isEmpty ? '' : alarms.first.title,
        alarmCount: '${alarms.length}',
      ),
    );
  }

  /// 删除单条通知：后端通知调 DELETE /notifications/:id，本地通知直接从存储移除
  Future<void> _onSystemNotificationDeleteRequested(
    SystemNotificationDeleteRequested event,
    Emitter<NotificationState> emit,
  ) async {
    if (event.notification.fromBackend && event.notification.id != null) {
      try {
        await notificationDataSource?.delete(event.notification.id!);
      } catch (_) {
        // 删除失败不阻断本地刷新（列表会重新拉取真实状态）
      }
    } else {
      // 本地通知（OTA/APP 更新）：按类型+标题+时间戳从存储中移除。
      // 单条解析失败只剔除该条（写回时顺带清理坏条目），不再让整批删除失败
      final storage = getIt<StorageService>();
      final storedJson = await storage.getString(_localNotifKey);
      if (storedJson != null && storedJson.isNotEmpty) {
        try {
          final decoded = json.decode(storedJson) as List;
          final remaining = <Map<String, dynamic>>[];
          for (final e in decoded) {
            if (e is! Map<String, dynamic>) continue;
            final n = _tryParseStoredNotification(e);
            // 解析失败的条目：写回时剔除，避免永久滞留
            if (n == null) continue;
            final isTarget = n.type == event.notification.type &&
                n.title == event.notification.title &&
                n.timestamp == event.notification.timestamp;
            if (!isTarget) remaining.add(e);
          }
          await storage.saveString(_localNotifKey, json.encode(remaining));
        } catch (_) {}
      }
    }
    // 重发加载，刷新列表
    add(const SystemNotificationsRequested());
  }

  /// 清空全部通知：后端调 DELETE /notifications/clear-all，本地通知直接清存储
  Future<void> _onSystemNotificationsClearRequested(
    SystemNotificationsClearRequested event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await notificationDataSource?.clearAll();
    } catch (_) {
      // 清空失败不阻断本地清空
    }
    final storage = getIt<StorageService>();
    await storage.saveString(_localNotifKey, '[]');
    add(const SystemNotificationsRequested());
  }

  @override
  Future<void> close() {
    _realtimeSub?.cancel();
    _alarmSub?.cancel();
    _otaSub?.cancel();
    _debounceTimer?.cancel();
    return super.close();
  }
}
