/**
 * ECharts 按需引入 Wrapper
 *
 * 替代 echarts-for-react 默认的全量导入，
 * 仅注册项目中实际使用的图表类型与组件，显著减小 bundle 体积。
 */
import React, { useEffect, useRef } from 'react'
import * as echarts from 'echarts/core'
import { LineChart, PieChart, BarChart } from 'echarts/charts'
import {
  TitleComponent,
  TooltipComponent,
  GridComponent,
  LegendComponent,
  DataZoomComponent,
  MarkLineComponent,
  AxisPointerComponent,
} from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'

echarts.use([
  LineChart,
  PieChart,
  BarChart,
  TitleComponent,
  TooltipComponent,
  GridComponent,
  LegendComponent,
  DataZoomComponent,
  MarkLineComponent,
  AxisPointerComponent,
  CanvasRenderer,
])

export interface ReactEChartsProps {
  option: Record<string, any>
  notMerge?: boolean
  lazyUpdate?: boolean
  style?: React.CSSProperties
  className?: string
  opts?: Record<string, any>
  onChartReady?: (instance: echarts.ECharts) => void
  loading?: boolean
  showLoading?: Record<string, any>
}

const ReactECharts: React.FC<ReactEChartsProps> = ({
  option,
  notMerge = false,
  lazyUpdate = false,
  style,
  className,
  opts,
  onChartReady,
  loading = false,
  showLoading,
}) => {
  const containerRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<echarts.ECharts | null>(null)

  // 初始化图表实例
  useEffect(() => {
    if (!containerRef.current) return
    const chart = echarts.init(containerRef.current, undefined, opts)
    chartRef.current = chart
    if (onChartReady) onChartReady(chart)

    const handleResize = () => chart.resize()
    window.addEventListener('resize', handleResize)

    return () => {
      window.removeEventListener('resize', handleResize)
      chart.dispose()
      chartRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // 更新图表配置
  useEffect(() => {
    if (chartRef.current && option) {
      chartRef.current.setOption(option, { notMerge, lazyUpdate })
    }
  }, [option, notMerge, lazyUpdate])

  // loading 状态
  useEffect(() => {
    if (!chartRef.current) return
    if (loading) {
      chartRef.current.showLoading('default', showLoading)
    } else {
      chartRef.current.hideLoading()
    }
  }, [loading, showLoading])

  return <div ref={containerRef} style={style} className={className} />
}

export default ReactECharts
