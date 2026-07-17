import React, { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Card, Segmented, DatePicker, Button, Space, Spin, Statistic, Typography } from 'antd'
import { LeftOutlined, RightOutlined } from '@ant-design/icons'
import ReactECharts from '@/lib/echarts'
import dayjs, { type Dayjs } from 'dayjs'
import api from '@/services/api'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

interface StationStatisticsTabProps {
  stationId: number
  timezone: string
}

const PERIOD_OPTIONS = [
  { label: '日', value: 'day' },
  { label: '月', value: 'month' },
  { label: '年', value: 'year' },
]

const ENERGY_CARDS = [
  { key: 'daily_pv', label: 'PV 发电量', unit: 'kWh', color: '#f59e0b', bg: '#fffbeb' },
  { key: 'daily_charge', label: '电池充电量', unit: 'kWh', color: '#22c55e', bg: '#f0fdf4' },
  { key: 'daily_discharge', label: '电池放电量', unit: 'kWh', color: '#3b82f6', bg: '#eff6ff' },
  { key: 'daily_load', label: '负载用电量', unit: 'kWh', color: '#ef4444', bg: '#fef2f2' },
]

const StationStatisticsTab: React.FC<StationStatisticsTabProps> = ({ stationId, timezone }) => {
  const { t } = useTranslation()
  const [period, setPeriod] = useState<string>('day')
  const [currentDate, setCurrentDate] = useState<Dayjs>(dayjs().tz(timezone))

  const getDateRange = () => {
    switch (period) {
      case 'day':
        return {
          start: currentDate.startOf('day').toISOString(),
          end: currentDate.endOf('day').toISOString(),
          apiPeriod: 'hour',
        }
      case 'month':
        return {
          start: currentDate.startOf('month').toISOString(),
          end: currentDate.endOf('month').toISOString(),
          apiPeriod: 'day',
        }
      case 'year':
        return {
          start: currentDate.startOf('year').toISOString(),
          end: currentDate.endOf('year').toISOString(),
          apiPeriod: 'day',
        }
      default:
        return {
          start: currentDate.startOf('day').toISOString(),
          end: currentDate.endOf('day').toISOString(),
          apiPeriod: 'hour',
        }
    }
  }

  const { start: startDate, end: endDate, apiPeriod } = getDateRange()

  const { data: statsData, isLoading } = useQuery({
    queryKey: ['station-statistics', stationId, period, startDate, endDate],
    queryFn: () => api.get(`/stations/${stationId}/statistics`, {
      params: { start_date: startDate, end_date: endDate, period: apiPeriod },
      expectedDataShape: 'array',
    }).then(res => {
      const data = res?.data?.data ?? res?.data ?? []
      return Array.isArray(data) ? data : []
    }),
    enabled: !!stationId,
  })

  const navigate = (direction: 'prev' | 'next') => {
    const unit = period === 'day' ? 'day' : period === 'month' ? 'month' : 'year'
    setCurrentDate(prev => direction === 'prev' ? prev.subtract(1, unit) : prev.add(1, unit))
  }

  const onDateChange = (date: Dayjs | null) => {
    if (date) setCurrentDate(date)
  }

  const datePickerType = period === 'day' ? undefined : period === 'month' ? 'month' : 'year'

  // 汇总当日/当月/当年总电量
  const energySummary = useMemo(() => {
    if (!statsData || statsData.length === 0) {
      return { daily_pv: 0, daily_charge: 0, daily_discharge: 0, daily_load: 0 }
    }
    // 对于 hour 粒度，取最后一条的 daily_* 累计值；对于 day 粒度，求和
    if (apiPeriod === 'hour') {
      const last = statsData[statsData.length - 1]
      return {
        daily_pv: safeNum(last?.daily_pv),
        daily_charge: safeNum(last?.daily_charge),
        daily_discharge: safeNum(last?.daily_discharge),
        daily_load: safeNum(last?.daily_load),
      }
    }
    return statsData.reduce(
      (acc, item) => ({
        daily_pv: acc.daily_pv + safeNum(item?.daily_pv ?? item?.energy_produce),
        daily_charge: acc.daily_charge + safeNum(item?.daily_charge ?? item?.battery_charge),
        daily_discharge: acc.daily_discharge + safeNum(item?.daily_discharge ?? item?.battery_discharge),
        daily_load: acc.daily_load + safeNum(item?.daily_load ?? item?.energy_consume),
      }),
      { daily_pv: 0, daily_charge: 0, daily_discharge: 0, daily_load: 0 },
    )
  }, [statsData, apiPeriod])

  // 功率折线图（仅日粒度）
  const powerLineOption = useMemo(() => {
    if (period !== 'day' || !statsData || statsData.length === 0) return null
    const times = statsData.map((d: any) => formatInTimezone(d.time, timezone, 'HH:mm'))
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
        formatter: (params: any) => {
          let html = `<div style="font-weight:600;margin-bottom:4px">${params[0].axisValue}</div>`
          params.forEach((p: any) => {
            html += `<div>${p.marker} ${p.seriesName}: ${safeNum(p.value).toFixed(0)} W</div>`
          })
          return html
        },
      },
      legend: { data: ['PV功率', '电池功率', '负载功率', '电网功率'], top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: times, axisLabel: { fontSize: 11 } },
      yAxis: {
        type: 'value' as const,
        name: 'W',
        axisLabel: {
          formatter: (v: number) => Math.abs(v) >= 1000 ? (Math.abs(v) / 1000).toFixed(1) + 'k' : Math.abs(v).toString(),
        },
      },
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 },
      ],
      series: [
        {
          name: 'PV功率', type: 'line' as const, smooth: true, symbol: 'none',
          data: statsData.map((d: any) => safeNum(d.energy_produce)),
          lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
        },
        {
          name: '电池功率', type: 'line' as const, smooth: true, symbol: 'none',
          data: statsData.map((d: any) => safeNum(d.battery_charge) - safeNum(d.battery_discharge)),
          lineStyle: { color: '#22c55e', width: 2 }, itemStyle: { color: '#22c55e' },
        },
        {
          name: '负载功率', type: 'line' as const, smooth: true, symbol: 'none',
          data: statsData.map((d: any) => safeNum(d.energy_consume)),
          lineStyle: { color: '#ef4444', width: 2 }, itemStyle: { color: '#ef4444' },
        },
        {
          name: '电网功率', type: 'line' as const, smooth: true, symbol: 'none',
          data: statsData.map((d: any) => safeNum(d.grid_power)),
          lineStyle: { color: '#3b82f6', width: 2 }, itemStyle: { color: '#3b82f6' },
        },
      ],
    }
  }, [statsData, period, timezone])

  // 电量柱状图
  const energyBarOption = useMemo(() => {
    if (!statsData || statsData.length === 0) return null
    const labels = statsData.map((d: any) => {
      if (period === 'year') return formatInTimezone(d.time, timezone, 'MM-DD')
      if (period === 'month') return formatInTimezone(d.time, timezone, 'MM-DD')
      return formatInTimezone(d.time, timezone, 'HH:mm')
    })
    const seriesConfig = [
      { name: 'PV', color: '#f59e0b', key: 'daily_pv', fallback: 'energy_produce' },
      { name: '充电', color: '#22c55e', key: 'daily_charge', fallback: 'battery_charge' },
      { name: '放电', color: '#3b82f6', key: 'daily_discharge', fallback: 'battery_discharge' },
      { name: '负载', color: '#ef4444', key: 'daily_load', fallback: 'energy_consume' },
    ]
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      legend: { data: seriesConfig.map(s => s.name), top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: '45', containLabel: true },
      xAxis: { type: 'category' as const, data: labels, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: statsData.length > 15
        ? [{ type: 'inside', start: 0, end: 100 }, { type: 'slider', start: 0, end: 100, height: 20, bottom: 8 }]
        : undefined,
      series: seriesConfig.map(s => ({
        name: s.name,
        type: 'bar' as const,
        data: statsData.map((d: any) => parseFloat(safeNum(d[s.key] ?? d[s.fallback]).toFixed(2))),
        itemStyle: { color: s.color, borderRadius: [3, 3, 0, 0] },
        barMaxWidth: 20,
      })),
    }
  }, [statsData, period, timezone])

  const dateFormat = period === 'day' ? 'YYYY-MM-DD' : period === 'month' ? 'YYYY-MM' : 'YYYY'

  return (
    <Spin spinning={isLoading}>
      {/* 工具栏：时间粒度 + 日期导航 */}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Segmented options={PERIOD_OPTIONS} value={period} onChange={v => setPeriod(v as string)} />
        </Col>
        <Col>
          <Space>
            <Button icon={<LeftOutlined />} onClick={() => navigate('prev')} size="small" />
            <DatePicker
              value={currentDate}
              onChange={onDateChange}
              picker={datePickerType as any}
              format={dateFormat}
              allowClear={false}
              size="small"
            />
            <Button icon={<RightOutlined />} onClick={() => navigate('next')} size="small" />
          </Space>
        </Col>
      </Row>

      {/* 能源概览 4 宫格 */}
      <Row gutter={[12, 12]} style={{ marginBottom: 16 }}>
        {ENERGY_CARDS.map(card => (
          <Col xs={12} sm={6} key={card.key}>
            <Card bordered={false} style={{ background: card.bg, borderRadius: 12 }} styles={{ body: { padding: '16px' } }}>
              <Statistic
                title={<span style={{ fontSize: 13 }}>{card.label}</span>}
                value={energySummary[card.key as keyof typeof energySummary]}
                precision={1}
                suffix={card.unit}
                valueStyle={{ color: card.color, fontWeight: 700, fontSize: 22 }}
              />
            </Card>
          </Col>
        ))}
      </Row>

      {/* 功率折线图（仅日粒度） */}
      {period === 'day' && powerLineOption && (
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }} title="功率曲线" size="small">
          <ReactECharts option={powerLineOption} style={{ height: 320 }} />
        </Card>
      )}

      {/* 电量柱状图 */}
      {energyBarOption && (
        <Card bordered={false} style={{ borderRadius: 12 }} title="电量统计" size="small">
          <ReactECharts option={energyBarOption} style={{ height: 320 }} />
        </Card>
      )}

      {!isLoading && (!statsData || statsData.length === 0) && (
        <Card bordered={false} style={{ borderRadius: 12, textAlign: 'center', padding: '48px 24px' }}>
          <Text type="secondary">暂无统计数据</Text>
        </Card>
      )}
    </Spin>
  )
}

export default StationStatisticsTab
