import 'dart:convert';

import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// 用户通知偏好（与服务端 user_notify_prefs 表 / 接口字段一一对应）。
class NotifyPrefs {
  final String email; // 只读回显用户邮箱（App 展示邮件绑定状态）
  final bool pushEnabled;
  final bool notifyOnline;
  final bool notifyOffline;
  final bool notifyAlarm;
  final bool notifyAlarmFatal;
  final bool notifyAlarmWarning;
  final bool notifyAlarmInfo;
  final bool notifyAlarmCleared;
  final bool notifyOta;
  final bool notifySystem;
  final bool notifyDaily;
  final String dailyReportTime;
  final bool emailEnabled;
  final bool dndEnabled;
  final String dndStart;
  final String dndEnd;
  final bool alarmBreakDnd;

  const NotifyPrefs({
    this.email = '',
    this.pushEnabled = true,
    this.notifyOnline = true,
    this.notifyOffline = true,
    this.notifyAlarm = true,
    this.notifyAlarmFatal = true,
    this.notifyAlarmWarning = true,
    this.notifyAlarmInfo = true,
    this.notifyAlarmCleared = true,
    this.notifyOta = true,
    this.notifySystem = true,
    this.notifyDaily = false,
    this.dailyReportTime = '20:00',
    this.emailEnabled = false,
    this.dndEnabled = false,
    this.dndStart = '22:00',
    this.dndEnd = '07:00',
    this.alarmBreakDnd = true,
  });

  factory NotifyPrefs.fromJson(Map<String, dynamic> json) => NotifyPrefs(
        email: json['email'] as String? ?? '',
        pushEnabled: json['push_enabled'] as bool? ?? true,
        notifyOnline: json['notify_online'] as bool? ?? true,
        notifyOffline: json['notify_offline'] as bool? ?? true,
        notifyAlarm: json['notify_alarm'] as bool? ?? true,
        notifyAlarmFatal: json['notify_alarm_fatal'] as bool? ?? true,
        notifyAlarmWarning: json['notify_alarm_warning'] as bool? ?? true,
        notifyAlarmInfo: json['notify_alarm_info'] as bool? ?? true,
        notifyAlarmCleared: json['notify_alarm_cleared'] as bool? ?? true,
        notifyOta: json['notify_ota'] as bool? ?? true,
        notifySystem: json['notify_system'] as bool? ?? true,
        notifyDaily: json['notify_daily'] as bool? ?? false,
        dailyReportTime: json['daily_report_time'] as String? ?? '20:00',
        emailEnabled: json['email_enabled'] as bool? ?? false,
        dndEnabled: json['dnd_enabled'] as bool? ?? false,
        dndStart: json['dnd_start'] as String? ?? '22:00',
        dndEnd: json['dnd_end'] as String? ?? '07:00',
        alarmBreakDnd: json['alarm_break_dnd'] as bool? ?? true,
      );

  /// 提交给服务端的字段（email 只读，不参与提交）。
  Map<String, dynamic> toJson() => {
        'push_enabled': pushEnabled,
        'notify_online': notifyOnline,
        'notify_offline': notifyOffline,
        'notify_alarm': notifyAlarm,
        'notify_alarm_fatal': notifyAlarmFatal,
        'notify_alarm_warning': notifyAlarmWarning,
        'notify_alarm_info': notifyAlarmInfo,
        'notify_alarm_cleared': notifyAlarmCleared,
        'notify_ota': notifyOta,
        'notify_system': notifySystem,
        'notify_daily': notifyDaily,
        'daily_report_time': dailyReportTime,
        'email_enabled': emailEnabled,
        'dnd_enabled': dndEnabled,
        'dnd_start': dndStart,
        'dnd_end': dndEnd,
        'alarm_break_dnd': alarmBreakDnd,
      };

  NotifyPrefs copyWith({
    String? email,
    bool? pushEnabled,
    bool? notifyOnline,
    bool? notifyOffline,
    bool? notifyAlarm,
    bool? notifyAlarmFatal,
    bool? notifyAlarmWarning,
    bool? notifyAlarmInfo,
    bool? notifyAlarmCleared,
    bool? notifyOta,
    bool? notifySystem,
    bool? notifyDaily,
    String? dailyReportTime,
    bool? emailEnabled,
    bool? dndEnabled,
    String? dndStart,
    String? dndEnd,
    bool? alarmBreakDnd,
  }) {
    return NotifyPrefs(
      email: email ?? this.email,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      notifyOnline: notifyOnline ?? this.notifyOnline,
      notifyOffline: notifyOffline ?? this.notifyOffline,
      notifyAlarm: notifyAlarm ?? this.notifyAlarm,
      notifyAlarmFatal: notifyAlarmFatal ?? this.notifyAlarmFatal,
      notifyAlarmWarning: notifyAlarmWarning ?? this.notifyAlarmWarning,
      notifyAlarmInfo: notifyAlarmInfo ?? this.notifyAlarmInfo,
      notifyAlarmCleared: notifyAlarmCleared ?? this.notifyAlarmCleared,
      notifyOta: notifyOta ?? this.notifyOta,
      notifySystem: notifySystem ?? this.notifySystem,
      notifyDaily: notifyDaily ?? this.notifyDaily,
      dailyReportTime: dailyReportTime ?? this.dailyReportTime,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      dndStart: dndStart ?? this.dndStart,
      dndEnd: dndEnd ?? this.dndEnd,
      alarmBreakDnd: alarmBreakDnd ?? this.alarmBreakDnd,
    );
  }

  /// 服务端默认值（与迁移 094 DEFAULT 一致），用于"重置所有通知设置"。
  static const defaults = NotifyPrefs();
}

/// 通知偏好服务：与服务端 GET/PUT /notify-settings 交互。
/// 网络失败时回退本地缓存（离线仍可查看上次已保存的设置）。
class NotifyPrefsService {
  final ApiService _apiService;
  final StorageService _storage;

  static const String _cacheKey = 'notify_prefs_cache';

  NotifyPrefsService(this._apiService, this._storage);

  /// 拉取服务端偏好；失败时回退本地缓存，无缓存则返回默认值。
  Future<NotifyPrefs> fetchPrefs() async {
    final result = await _apiService.get<NotifyPrefs>(
      '/notify-settings',
      fromJson: (json) => NotifyPrefs.fromJson(json),
    );
    return result.fold(
      (failure) => _loadLocalCache(),
      (prefs) {
        _saveLocalCache(prefs);
        return prefs;
      },
    );
  }

  /// 保存偏好到服务端；失败抛出 [Failure]，由调用方回滚乐观更新。
  Future<void> savePrefs(NotifyPrefs prefs) async {
    final result = await _apiService.put<void>(
      '/notify-settings',
      data: prefs.toJson(),
      fromJson: (_) {},
    );
    return result.fold(
      (failure) => throw failure,
      (_) => _saveLocalCache(prefs),
    );
  }

  Future<NotifyPrefs> _loadLocalCache() async {
    final raw = await _storage.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return NotifyPrefs.defaults;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return NotifyPrefs.fromJson(map);
    } catch (_) {
      return NotifyPrefs.defaults;
    }
  }

  Future<void> _saveLocalCache(NotifyPrefs prefs) async {
    await _storage.saveString(_cacheKey, jsonEncode(prefs.toJson()));
  }
}
