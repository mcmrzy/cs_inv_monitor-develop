import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
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
    final type = SystemNotificationType.values[json['type'] as int];
    final title = json['title'] as String;
    final legacyVersion = type == SystemNotificationType.appUpdate
        ? RegExp(r'v([^\s]+)').firstMatch(title)?.group(1)
        : null;
    return SystemNotification(
      type: type,
      title: title,
      subtitle: json['subtitle'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
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
  final MQTTService? mqttService;
  final NotificationRemoteDataSource? notificationDataSource;
  static const _localNotifKey = 'local_notifications'; // 仅存储OTA/APP更新等本地通知
  static const _maxNotifications = 100;

  StreamSubscription<dynamic>? _realtimeSub;
  StreamSubscription<dynamic>? _alarmSub;
  StreamSubscription<dynamic>? _otaSub;
  Timer? _debounceTimer;

  NotificationBloc({
    required this.deviceRepository,
    this.mqttService,
    this.notificationDataSource,
  }) : super(NotificationInitial()) {
    on<SystemNotificationsRequested>(_onSystemNotificationsRequested);
    on<_MqttStatusUpdate>(_onMqttStatusUpdate);
    on<JPushNotificationReceived>(_onJPushNotificationReceived);
    on<JPushNotificationTapped>(_onJPushNotificationTapped);
    _subscribeToMqtt();
  }

  void _subscribeToMqtt() {
    // 监听设备实时数据流，触发刷新（后端已自动插入通知）
    _realtimeSub = mqttService?.realtimeDataStream.listen((rt) {
      add(_MqttStatusUpdate(deviceSn: rt.deviceSN, isOnline: rt.onlineStatus?.online ?? false));
    });

    // 监听告警，触发通知列表刷新
    _alarmSub = mqttService?.alarmStream.listen((_) {
      _debouncedRefresh();
    });

    // 监听 OTA 通知（仍然本地生成）
    _otaSub = mqttService?.otaNotificationStream.listen((ota) {
      _addOtaNotification(ota);
    });
  }

  void _debouncedRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      add(const SystemNotificationsRequested());
    });
  }

  Future<void> _addOtaNotification(dynamic ota) async {
    final storage = getIt<StorageService>();
    final notification = SystemNotification(
      type: SystemNotificationType.otaAvailable,
      title: '',
      subtitle: '',
      timestamp: DateTime.now(),
      deviceSn: ota.deviceSN,
    );
    await _prependLocalNotification(storage, notification);
    add(const SystemNotificationsRequested());
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
    debugPrint('[NotificationBloc] JPush received: ${event.notifyType}, deviceSn=${event.deviceSn}');
    _debouncedRefresh();
  }

  /// 用户点击 JPush 通知时，触发通知列表刷新
  Future<void> _onJPushNotificationTapped(
    JPushNotificationTapped event,
    Emitter<NotificationState> emit,
  ) async {
    debugPrint('[NotificationBloc] JPush tapped: ${event.notifyType}, deviceSn=${event.deviceSn}');
    _debouncedRefresh();
  }

  Future<void> _prependLocalNotification(StorageService storage, SystemNotification notification) async {
    final storedJson = await storage.getString(_localNotifKey);
    List<SystemNotification> stored = [];
    if (storedJson != null && storedJson.isNotEmpty) {
      try {
        final decoded = json.decode(storedJson) as List;
        stored = decoded
            .map((e) => SystemNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    final allNotifications = [notification, ...stored];
    final trimmed = allNotifications.length > _maxNotifications
        ? allNotifications.sublist(0, _maxNotifications)
        : allNotifications;

    final saveJson = json.encode(trimmed.map((e) => e.toJson()).toList());
    await storage.saveString(_localNotifKey, saveJson);
  }

  Future<void> _onSystemNotificationsRequested(
    SystemNotificationsRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final List<SystemNotification> allNotifications = [];

    // 1. 从后端获取设备通知（上线/离线等）
    if (notificationDataSource != null) {
      try {
        final response = await notificationDataSource!.getList(page: 1, pageSize: 50);
        final data = response.data;
        if (data != null) {
          final responseData = data['data'] ?? data;
          final items = responseData is Map ? (responseData['items'] ?? []) : (responseData is List ? responseData : []);
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
    final storage = getIt<StorageService>();
    final storedJson = await storage.getString(_localNotifKey);
    List<SystemNotification> localStored = [];
    if (storedJson != null && storedJson.isNotEmpty) {
      try {
        final decoded = json.decode(storedJson) as List;
        localStored = decoded
            .map((e) => SystemNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // 3. 检查 App 更新（仅首次或手动刷新时检查）
    if (state is! SystemNotificationsLoaded) {
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
          final exists = localStored.any((n) =>
              n.type == SystemNotificationType.appUpdate &&
              n.version == appUpdateNotif.version);
          if (!exists) {
            localStored = [appUpdateNotif, ...localStored];
            final saveJson = json.encode(localStored.map((e) => e.toJson()).toList());
            await storage.saveString(_localNotifKey, saveJson);
          }
        }
      } catch (_) {}
    }

    // 4. 合并后端通知和本地通知
    allNotifications.addAll(localStored);

    emit(SystemNotificationsLoaded(notifications: allNotifications));
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
