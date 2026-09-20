/**
 * 调试页主题常量（浅色，与后台其它卡片一致：白底 + 彩色曲线）。
 *
 * 历史：这里曾是「深色示波器」面板（深蓝底 + 辉光曲线）。整站是白底浅色，
 * 那块深色成了异类，2026-09-20 改为白底彩色：白卡片 + 高饱和曲线，
 * 面积渐变交回给曲线自身撑「彩」，文字/分隔线用后台统一的灰阶。
 * 色值集中在此，DebugTab / DebugChart / DebugTable / debugChartOption 共用一份。
 */
import type { CSSProperties } from 'react'

/** 白底卡片面板（与后台其它 Card 一致） */
export const DEBUG_PANEL_STYLE: CSSProperties = {
  borderRadius: 12,
  border: '1px solid #f0f0f0',
  background: '#ffffff',
  boxShadow: '0 2px 8px rgba(17,24,39,0.06)',
}

/** 面板内的标题色 */
export const DEBUG_TITLE = '#1f2937'
/** 面板内的次要文字 */
export const DEBUG_TEXT = '#6b7280'
/** 面板内的分隔线（网格） */
export const DEBUG_SPLIT = 'rgba(17,24,39,0.06)'
/** 面板内的坐标轴/描边 */
export const DEBUG_AXIS = 'rgba(17,24,39,0.22)'
/** 强调色（与后台主色一致） */
export const DEBUG_ACCENT = '#1677ff'
/** 读数徽标等浅底色块 */
export const DEBUG_CHIP_BG = '#fafafa'
/** 图表高度 */
export const DEBUG_CHART_HEIGHT = 380
