package com.csergy.app1

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 桌面小组件 Provider：通知（2×2）
 *
 * 展示最新告警标题 + 告警数，点击小组件通过 PendingIntent 深链
 * 启动 App（携带 invapp://notifications URI，
 * Flutter 侧监听 HomeWidget.widgetClicked 导航到通知中心）。
 * 数据由 Flutter 侧 WidgetUpdateService.updateNotificationWidget 写入。
 *
 * 真机验证项：
 * - 桌面长按 → 添加小部件 → 选择"辰烁光伏-通知"
 * - 点击小组件应启动 App（深链导航见 MainActivity 日志）
 */
class NotificationWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.notification_widget_layout).apply {
                // 最新告警标题（空串兜底显示"暂无告警"）
                val title = widgetData.getString("notif_latest_title", null)
                setTextViewText(
                    R.id.notif_latest_title,
                    if (title.isNullOrBlank()) "暂无告警" else title,
                )

                // 告警条数
                val count = widgetData.getString("notif_alarm_count", null) ?: "0"
                setTextViewText(R.id.notif_alarm_count, count)

                // 点击深链：启动 App 并携带路由 URI
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("invapp://notifications"),
                )
                setOnClickPendingIntent(R.id.notification_widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
