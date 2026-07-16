import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';
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

  /// 通知标题。
  final String title;

  /// 通知内容。
  final String content;

  const JPushNotification({
    required this.notifyType,
    this.deviceSn,
    this.title = '',
    this.content = '',
  });

  @override
  String toString() {
    return 'JPushNotification(notifyType: $notifyType, deviceSn: $deviceSn, title: $title, content: $content)';
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

  /// 初始化 JPush SDK
  ///
  /// [appKey] 为极光推送的 AppKey，未提供时使用占位符。
  /// 应在 App 启动、依赖注入初始化完成后调用。
  Future<void> init({String? appKey}) async {
    if (_initialized) return;

    _jpush = JPush.newJPush();
    _jpush.setup(
      appKey: appKey ?? 'e89e8b711cd18f666705fe7f',
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
    if (!_initialized) return null;
    return await _jpush.getRegistrationID();
  }

  /// 登录后绑定用户别名
  ///
  /// [userId] 为用户 ID，绑定后后端可通过别名 `user_$userId`
  /// 向该用户的所有设备推送消息。
  /// 会等待 JPush SDK 就绪后再设置别名，最多重试 3 次。
  Future<void> bindUser(int userId) async {
    if (!_initialized) return;
    final alias = 'user_$userId';

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 等待 SDK 注册完成（获取到 registrationID 表示就绪）
        final regId = await _jpush.getRegistrationID();
        if (regId.isNotEmpty) {
          debugPrint(
              '[JPushService] SDK ready, regId=$regId, setting alias=$alias');
          await _jpush.setAlias(alias);
          debugPrint('[JPushService] Alias set successfully: $alias');
          return;
        }
        debugPrint(
            '[JPushService] SDK not ready yet, retry ${attempt + 1}/3...');
      } catch (e) {
        debugPrint(
            '[JPushService] setAlias failed (attempt ${attempt + 1}/3): $e');
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('[JPushService] Failed to set alias after 3 attempts');
  }

  /// 退出登录时解绑别名
  Future<void> unbindUser() async {
    if (!_initialized) return;
    await _jpush.deleteAlias();
  }

  /// 从 JPush SDK 回调消息中解析出结构化的通知对象
  JPushNotification _parseNotification(Map<String, dynamic> message) {
    final extras = _parseExtras(message);
    return JPushNotification(
      notifyType: _extractString(extras, 'notify_type'),
      deviceSn: _extractStringOrNull(extras, 'device_sn'),
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

  /// 根据通知类型执行页面跳转
  ///
  /// 跳转目标：
  /// - device_alarm / alarm_cleared / device_offline / device_online → 设备详情页
  /// - system_announcement → 通知中心页面（/alarms）
  void _handleNavigation(JPushNotification notification) {
    final notifyType = notification.notifyType;
    final deviceSn = notification.deviceSn;

    switch (notifyType) {
      case 'device_alarm':
      case 'alarm_cleared':
      case 'device_offline':
      case 'device_online':
        if (deviceSn != null && deviceSn.isNotEmpty) {
          AppRouter.router.go('/device/$deviceSn');
        } else {
          debugPrint(
              '[JPushService] Missing device_sn for notify_type=$notifyType');
        }
        break;
      case 'system_announcement':
        AppRouter.router.go('/alarms');
        break;
      case 'ota_available':
        AppRouter.router.go('/ota');
        break;
      case 'app_update':
        AppRouter.router.go('/settings');
        break;
      default:
        debugPrint(
            '[JPushService] Unknown notify_type: $notifyType, skip navigation');
    }
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
          '[JPushService] Notification permission permanently denied, please enable in settings');
    }
  }
}
