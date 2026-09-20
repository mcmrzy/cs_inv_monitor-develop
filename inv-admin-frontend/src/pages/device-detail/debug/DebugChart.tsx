/**
 * 调试曲线（示波器）。option 由 buildDebugChartOption 构造后整体传入，
 * 本组件只负责渲染与空态，保证「图怎么画」的逻辑可被纯函数单测覆盖。
 */
import React from 'react'

import ReactECharts from '@/lib/echarts'
import { DEBUG_CHART_HEIGHT, DEBUG_TEXT } from './debugTheme'

interface DebugChartProps {
  /** buildDebugChartOption 的结果；null = 无可绘制曲线 */
  option: Record<string, unknown> | null
  /** 空态文案 */
  emptyText: string
  height?: number
}

const DebugChart: React.FC<DebugChartProps> = ({ option, emptyText, height = DEBUG_CHART_HEIGHT }) => {
  if (!option) {
    return (
      <div style={{ padding: '56px 0', textAlign: 'center', color: DEBUG_TEXT, fontSize: 13 }}>
        {emptyText}
      </div>
    )
  }
  return <ReactECharts option={option} notMerge lazyUpdate style={{ height, width: '100%' }} />
}

export default DebugChart
