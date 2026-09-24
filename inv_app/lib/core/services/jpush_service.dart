import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:inv_app/core/platform/app_platform.dart';
import 'package:inv_app/core/router/app_router.dart';

/// 极光推送消息对象
///
/// 从 JPush SDK 回调中解析得到，包含通知类型、关联设备序列号、
/// 标题与内容等字段。
class JPushNotification {
  /// 推送通知类型，对应后端 extras 中的 `notify_type` 字段。
  final String notifyType;

  /// 关联设备序列号，对应 extras 中的 `device_sn` 字段。
  final String? deviceSn;

  /// 关联告警 ID，对应 extras 中的 `alarm_id` 字段（仅告警/恢复类推送携带），
  /// 用于深链到告警详情页 `/alarm/:id`。
  final int? alarmId;

  /// 通知标题。
  final String title;

  /// 通知内容。
  final String content;

  const JPushNotification({
    required this.notifyType,
    this.deviceSn,
    this.alarmId,
    this.title = '',
    this.content = '',
  });

  @override
  String toString() {
    return 'JPushNotification(notifyType: $notifyType, deviceSn: $deviceSn, alarmId: $alarmId, title: $title, content: $content)';
  }
}

/// 极光推送服务
///
/// 负责初始化 JPush SDK、获取 Registration ID、
/// 以及用户登录/退出时的别名绑定与解绑。
///
/// 使用单例模式，通过 [ServiceLocator] 注册。
class JPushService {
  static final JPushService _instance = JPushService._internal();
  factory JPushService() => _instance;
  JPushService._internal();

  late JPushFlutterInterface _jpush;
  bool _initialized = false;

  /// 收到通知时的回调（应用在前台）
  void Function(JPushNotification notification)? onNotificationReceived;

  /// 用户点击打开通知时的回调
  void Function(JPushNotification notification)? onNotificationOpened;

  /// 检查当前平台是否支持 JPush
  ///
  /// 能力矩阵见 [PlatformCapabilities.supportsPush]；鸿蒙需换华为推送通道
  bool get isSupported {
    if (kIsWeb) return false;
    return PlatformCapabilities.supportsPush;
  }

  /// 初始化 JPush SDK
  ///
  /// [appKey] 为极光推送的 AppKey，未提供时使用占位符。
  /// 应在 App 启动、依赖注入初始化完成后调用。
  Future<void> init({String? appKey}) async {
    if (_initialized) return;
    if (!isSupported) {
      debugPrint('[JPushService] Platform not supported, skipping init');
      return;
    }

    _jpush = JPush.newJPush();
    _jpush.setup(
      appKey: appKey ?? '5a5df0da74b0ec20becb9bb1',
      channel: 'inv_app',
      production: true,
      debug: kDebugMode,
    );

    _jpush.addEventHandler(
      onReceiveNotification: (Map<String, dynamic> message) async {
        final notification = _parseNotification(message);
        debugPrint('[JPushService] Received notification: $notification');
        onNotificationReceived?.call(notification);
      },
      onOpenNotification: (Map<String, dynamic> message) async {
        final notification = _parseNotification(message);
        debugPrint('[JPushService] Opened notification: $notification');
        onNotificationOpened?.call(notification);
        _handleNavigation(notification);
      },
    );

    // Android 13+ 需要运行时申请通知权限
    await _requestNotificationPermission();

    _initialized = true;
  }

  /// 获取 Registration ID
  ///
  /// Registration ID 是设备的唯一标识，
  /// 后端可通过此 ID 向特定设备推送消息。
  Future<String?> getRegistrationID() async {
    if (!_initialized || !isSupported) return null;
    return await _jpush.getRegistrationID();
  }

  /// 登录后绑定用户别名
  ///
  /// [userId] 为用户 ID，绑定后后端可通过别名 `user_$userId`
  /// 向该用户的所有设备推送消息。
  /// 会等待 JPush SDK 就绪后再设置别名，最多重试 3 次。
  Future<void> bindUser(int userId) async {
    if (!_initialized || !isSupported) return;
    final alias = 'user_$userId';

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 等待 SDK 注册完成（获取到 registrationID 表示就绪）
        final regId = await _jpush.getRegistrationID();
        if (regId.isNotEmpty) {
          debugPrint(
            '[JPushService] SDK ready, regId=$regId, setting alias=$alias',
          );
          await _jpush.setAlias(alias);
          debugPrint('[JPushService] Alias set successfully: $alias');
          return;
        }
        debugPrint(
          '[JPushService] SDK not ready yet, retry ${attempt + 1}/3...',
        );
      } catch (e) {
        debugPrint(
          '[JPushService] setAlias failed (attempt ${attempt + 1}/3): $e',
        );
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('[JPushService] Failed to set alias after 3 attempts');
  }

  /// 退出登录时解绑别名
  Future<void> unbindUser() async {
    if (!_initialized || !isSupported) return;
    await _jpush.deleteAlias();
  }

  /// 从 JPush SDK 回调消息中解析出结构化的通知对象
  JPushNotification _parseNotification(Map<String, dynamic> message) {
    final extras = _parseExtras(message);
    return JPushNotification(
      notifyType: _extractString(extras, 'notify_type'),
      deviceSn: _extractStringOrNull(extras, 'device_sn'),
      alarmId: _extractIntOrNull(extras, 'alarm_id'),
      title: _extractString(message, 'title'),
      content: _extractString(message, 'alert').isNotEmpty
          ? _extractString(message, 'alert')
          : _extractString(message, 'content'),
    );
  }

  /// 解析 extras 字段，兼容 Map 与 JSON 字符串两种格式
  Map<String, dynamic> _parseExtras(Map<String, dynamic> message) {
    final extras = message['extras'];
    if (extras is Map<String, dynamic>) {
      return extras;
    }
    if (extras is String && extras.isNotEmpty) {
      try {
        final decoded = json.decode(extras);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (e) {
        debugPrint('[JPushService] Failed to parse extras: $e');
      }
    }
    return {};
  }

  String _extractString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return '';
    return value.toString();
  }

  String? _extractStringOrNull(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    final str = value.toString();
    return str.isEmpty ? null : str;
  }

  int? _extractIntOrNull(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// 根据通知类型执行页面跳转
  ///
  /// 具体目标见 [resolveTargetRoute]；导航延后一帧执行，
  /// 因为冷启动点通知时补发的回调可能在 Router 挂载前到达。
  void _handleNavigation(JPushNotification notification) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = resolveTargetRoute(notification);
      debugPrint(
        '[JPushService] Navigate to ${target.location} '
        '(push: ${target.push})',
      );
      if (target.push) {
        AppRouter.router.push(target.location);
      } else {
        AppRouter.router.go(target.location);
      }
    });
  }

  /// 申请通知权限（Android 13+ 必需）
  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) {
      debugPrint('[JPushService] Notification permission already granted');
      return;
    }
    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        debugPrint('[JPushService] Notification permission granted');
      } else {
        debugPrint('[JPushService] Notification permission denied');
      }
    }
    if (status.isPermanentlyDenied) {
      debugPrint(
        '[JPushService] Notification permission permanently denied, please enable in settings',
      );
    }
  }
}

/// 通知点击后的跳转目标
///
/// [push] 为 true 时压栈导航（用户可返回原页面），
/// 为 false 时替换当前栈（tab 级页面）。
class NotificationRouteTarget {
  /// go_router 目标路径。
  final String location;

  /// 是否使用 push（可返回）而非 go（替换）。
  final bool push;

  const NotificationRouteTarget({
    required this.location,
    this.push = false,
  });

  @override
  bool operator ==(Object other) =>
      other is NotificationRouteTarget &&
      other.location == location &&
      other.push == push;

  @override
  int get hashCode => Object.hash(location, push);

  @override
  String toString() =>
      'NotificationRouteTarget(location: $location, push: $push)';
}

/// 根据通知类型决定点击通知后的跳转目标
///
/// - device_online / device_offline → 设备详情页（push，可返回原页面；
///   extras 缺 device_sn 时兜底消息中心）
/// - device_alarm / alarm_cleared → 告警详情页 `/alarm/:id`（push；extras
///   缺 alarm_id 时兜底消息中心列表）
/// - device_ota / ota_available → OTA 管理页
/// - app_update → 关于页并自动检查更新（push，可返回）
/// - daily_report → 统计概览
/// - system_announcement → 消息中心（公告存在于 feed，无单条详情页）
/// - 未知类型 → 消息中心兜底，保证点击必有响应
NotificationRouteTarget resolveTargetRoute(JPushNotification notification) {
  switch (notification.notifyType) {
    case 'device_online':
    case 'device_offline':
      final sn = notification.deviceSn;
      if (sn != null && sn.isNotEmpty) {
        return NotificationRouteTarget(location: '/device/$sn', push: true);
      }
      return const NotificationRouteTarget(location: '/alarms');
    case 'device_alarm':
    case 'alarm_cleared':
      final alarmId = notification.alarmId;
      if (alarmId != null && alarmId > 0) {
        return NotificationRouteTarget(location: '/alarm/$alarmId', push: true);
      }
      return const NotificationRouteTarget(location: '/alarms');
    case 'device_ota':
    case 'ota_available':
      return const NotificationRouteTarget(location: '/ota');
    case 'app_update':
      // 深链到关于页并自动检查，保证点通知后能立刻看到更新弹窗/已是最新
      return const NotificationRouteTarget(
        location: '/about?check=1',
        push: true,
      );
    case 'daily_report':
      return const NotificationRouteTarget(location: '/statistics');
    default:
      // 公告/未知类型统一进消息中心
      return const NotificationRouteTarget(location: '/alarms');
  }
}
