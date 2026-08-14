package com.csergy.app1

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 桌面小组件 Provider：电站概览
 *
 * 数据由 Flutter 侧通过 home_widget 写入 SharedPreferences，
 * 本 Provider 读取并渲染到 RemoteViews。
 *
 * 真机验证项：需要用户在桌面长按 → 添加小部件 → 选择"辰烁光伏"。
 * 模拟器无法验证桌面小部件交互，已保留日志供调试。
 */
class StationWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.station_widget_layout).apply {
                // 今日发电（kWh）
                val todayKwh = widgetData.getString("today_kwh", null) ?: "--"
                setTextViewText(R.id.widget_today_kwh, "$todayKwh kWh")

                // 设备在线 / 总数
                val online = widgetData.getString("device_online", null) ?: "--"
                val total = widgetData.getString("device_total", null) ?: "--"
                setTextViewText(R.id.widget_device_online, "$online / $total")

                // 当前功率（W）
                val power = widgetData.getString("current_power", null) ?: "--"
                setTextViewText(R.id.widget_current_power, "$power W")
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
