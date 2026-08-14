import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Android 桌面小组件更新服务
///
/// 将电站概览数据写入 home_widget 的 SharedPreferences，
/// 并触发 Android 桌面小组件刷新。共 4 个小组件：
/// - StationWidgetProvider：电站概览（今日发电/设备在线/当前功率）
/// - StatsWidgetProvider：统计信息（累计发电/今日收益/设备在线，2×2）
/// - EnergyFlowWidgetProvider：能量流（今日发电/当前功率/本月发电，2×2）
/// - NotificationWidgetProvider：通知（最新告警标题 + 告警数，2×2）
///
/// 共享 AppGroupId：四个小组件读写同一份 SharedPreferences。
///
/// **真机验证项**：
/// - 桌面长按 → 小部件 → 添加"辰烁光伏"系列卡片
/// - 登录后数据应自动更新到小组件
/// - 点击通知小组件应启动 App（PendingIntent 深链，见 MainActivity 日志）
/// - 模拟器无法验证桌面小部件交互
class WidgetUpdateService {
  WidgetUpdateService._();

  static const _appGroupId = 'com.csergy.app1';

  /// 初始化 home_widget（Android 端注册 AppGroupId）
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (e) {
      debugPrint('[WidgetUpdate] init failed: $e');
    }
  }

  /// 更新小组件数据并触发刷新
  ///
  /// [todayKwh] 今日发电量（kWh）
  /// [deviceOnline] 在线设备数
  /// [deviceTotal] 设备总数
  /// [currentPower] 当前总功率（W）
  static Future<void> updateStationWidget({
    required String todayKwh,
    required String deviceOnline,
    required String deviceTotal,
    required String currentPower,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('today_kwh', todayKwh),
        HomeWidget.saveWidgetData<String>('device_online', deviceOnline),
        HomeWidget.saveWidgetData<String>('device_total', deviceTotal),
        HomeWidget.saveWidgetData<String>('current_power', currentPower),
      ]);
      await HomeWidget.updateWidget(
        name: 'StationWidgetProvider',
        androidName: 'com.csergy.app1.StationWidgetProvider',
      );
      debugPrint('[WidgetUpdate] widget data pushed');
    } catch (e) {
      debugPrint('[WidgetUpdate] update failed: $e');
    }
  }

  /// 更新统计信息小组件（2×2）
  ///
  /// [totalKwh] 累计发电量（kWh）
  /// [todayIncome] 今日收益（元）
  /// [deviceOnline] 在线设备数
  /// [deviceTotal] 设备总数
  static Future<void> updateStatsWidget({
    required String totalKwh,
    required String todayIncome,
    required String deviceOnline,
    required String deviceTotal,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('stats_total_kwh', totalKwh),
        HomeWidget.saveWidgetData<String>('stats_today_income', todayIncome),
        HomeWidget.saveWidgetData<String>('stats_online', deviceOnline),
        HomeWidget.saveWidgetData<String>('stats_total', deviceTotal),
      ]);
      await HomeWidget.updateWidget(
        name: 'StatsWidgetProvider',
        androidName: 'com.csergy.app1.StatsWidgetProvider',
      );
      debugPrint('[WidgetUpdate] stats widget data pushed');
    } catch (e) {
      debugPrint('[WidgetUpdate] stats update failed: $e');
    }
  }

  /// 更新能量流小组件（2×2）：静态流向示意 + 关键数值
  ///
  /// 不做自定义 Canvas 绘图（RemoteViews 不支持自定义 View 类，
  /// 且受 Binder 事务与 SP 体积限制），只传精简聚合值。
  ///
  /// [todayKwh] 今日发电（光伏产出，kWh）
  /// [currentPower] 当前总功率（流向强度，W）
  /// [monthKwh] 本月发电（kWh）
  static Future<void> updateEnergyFlowWidget({
    required String todayKwh,
    required String currentPower,
    required String monthKwh,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('ef_today_kwh', todayKwh),
        HomeWidget.saveWidgetData<String>('ef_current_power', currentPower),
        HomeWidget.saveWidgetData<String>('ef_month_kwh', monthKwh),
      ]);
      await HomeWidget.updateWidget(
        name: 'EnergyFlowWidgetProvider',
        androidName: 'com.csergy.app1.EnergyFlowWidgetProvider',
      );
      debugPrint('[WidgetUpdate] energy flow widget data pushed');
    } catch (e) {
      debugPrint('[WidgetUpdate] energy flow update failed: $e');
    }
  }

  /// 更新通知小组件（2×2）：最新告警标题 + 告警数
  ///
  /// [latestAlarmTitle] 最新一条告警类通知标题（空串表示暂无告警，
  /// 由原生侧兜底显示"暂无告警"）
  /// [alarmCount] 当前告警条数
  static Future<void> updateNotificationWidget({
    required String latestAlarmTitle,
    required String alarmCount,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('notif_latest_title', latestAlarmTitle),
        HomeWidget.saveWidgetData<String>('notif_alarm_count', alarmCount),
      ]);
      await HomeWidget.updateWidget(
        name: 'NotificationWidgetProvider',
        androidName: 'com.csergy.app1.NotificationWidgetProvider',
      );
      debugPrint('[WidgetUpdate] notification widget data pushed');
    } catch (e) {
      debugPrint('[WidgetUpdate] notification update failed: $e');
    }
  }

  /// 清空小组件数据（退出登录时调用）
  static Future<void> clearWidgetData() async {
    if (!Platform.isAndroid) return;
    try {
      await Future.wait([
        // 电站概览小组件
        HomeWidget.saveWidgetData<String>('today_kwh', null),
        HomeWidget.saveWidgetData<String>('device_online', null),
        HomeWidget.saveWidgetData<String>('device_total', null),
        HomeWidget.saveWidgetData<String>('current_power', null),
        // 统计小组件
        HomeWidget.saveWidgetData<String>('stats_total_kwh', null),
        HomeWidget.saveWidgetData<String>('stats_today_income', null),
        HomeWidget.saveWidgetData<String>('stats_online', null),
        HomeWidget.saveWidgetData<String>('stats_total', null),
        // 能量流小组件
        HomeWidget.saveWidgetData<String>('ef_today_kwh', null),
        HomeWidget.saveWidgetData<String>('ef_current_power', null),
        HomeWidget.saveWidgetData<String>('ef_month_kwh', null),
        // 通知小组件
        HomeWidget.saveWidgetData<String>('notif_latest_title', null),
        HomeWidget.saveWidgetData<String>('notif_alarm_count', null),
      ]);
      await Future.wait([
        HomeWidget.updateWidget(
          name: 'StationWidgetProvider',
          androidName: 'com.csergy.app1.StationWidgetProvider',
        ),
        HomeWidget.updateWidget(
          name: 'StatsWidgetProvider',
          androidName: 'com.csergy.app1.StatsWidgetProvider',
        ),
        HomeWidget.updateWidget(
          name: 'EnergyFlowWidgetProvider',
          androidName: 'com.csergy.app1.EnergyFlowWidgetProvider',
        ),
        HomeWidget.updateWidget(
          name: 'NotificationWidgetProvider',
          androidName: 'com.csergy.app1.NotificationWidgetProvider',
        ),
      ]);
      debugPrint('[WidgetUpdate] widget data cleared');
    } catch (e) {
      debugPrint('[WidgetUpdate] clear failed: $e');
    }
  }
}
