import React, { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Card, Segmented, DatePicker, Button, Space, Spin, Statistic, Typography } from 'antd'
import { LeftOutlined, RightOutlined } from '@ant-design/icons'
import ReactECharts from '@/lib/echarts'
import dayjs, { type Dayjs } from 'dayjs'
import api from '@/services/api'
import { dashboardApi } from '@/services/dashboardApi'
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
  const [flowDate, setFlowDate] = useState<string>(dayjs().tz(timezone).format('YYYY-MM-DD'))

  // 30日发电趋势
  const { data: trend30Res } = useQuery({
    queryKey: ['station-trend-30d', stationId],
    queryFn: () => dashboardApi.getTrend('30days').then(r => r.data),
    enabled: !!stationId,
  })
  const trend30Data = Array.isArray(trend30Res?.data) ? trend30Res.data :
    (Array.isArray(trend30Res?.data?.data) ? trend30Res.data.data : [])

  // 电量概览
  const [overviewPeriod, setOverviewPeriod] = useState('day')
  const { data: energyOverviewRes } = useQuery({
    queryKey: ['station-energy-overview', stationId, overviewPeriod],
    queryFn: () => dashboardApi.getEnergyStats({ type: overviewPeriod, stationId }).then(r => r.data),
    enabled: !!stationId,
  })
  const energyOverview = energyOverviewRes?.data ?? energyOverviewRes ?? {}

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

  // 功率趋势：使用 getEnergyFlow API 获取真实功率数据（与 Dashboard 一致）
  const { data: flowRes, isLoading: flowLoading } = useQuery({
    queryKey: ['station-power-flow', stationId, flowDate],
    queryFn: () => dashboardApi.getEnergyFlow({ date: flowDate, stationId }).then(r => {
      const d = r.data?.data ?? r.data ?? []
      return Array.isArray(d) ? d : (Array.isArray(d?.data) ? d.data : [])
    }),
    enabled: !!stationId && period === 'day',
  })
  const flowData = (Array.isArray(flowRes) ? flowRes : []) as any[]

  // 电量柱状图 + 能量概览仍使用 statistics API
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

  // 功率折线图（仅日粒度，使用 energy-flow API 获取真实功率数据）
  const powerLineOption = useMemo(() => {
    if (period !== 'day' || !flowData || flowData.length === 0) return null
    const times = flowData.map((d: any) => formatInTimezone(d.time, timezone, 'HH:mm'))
    const pvData = flowData.map((d: any) => safeNum(d.pvPower))
    const battChargeData = flowData.map((d: any) => safeNum(d.batteryCharge))
    const battDischargeData = flowData.map((d: any) => -safeNum(d.batteryDischarge))
    const loadData = flowData.map((d: any) => -safeNum(d.loadPower))
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'cross' as const },
        formatter: (params: any) => {
          let html = `<div style="font-weight:600;margin-bottom:4px">${params[0].axisValue}</div>`
          params.forEach((p: any) => {
            const val = Math.abs(p.value)
            html += `<div>${p.marker} ${p.seriesName}: ${val.toFixed(0)} W</div>`
          })
          return html
        },
      },
      legend: { data: [t('station.pvPower'), t('station.battChargeEnergy'), t('station.battDischargeEnergy'), t('station.loadPower')], top: 0, itemGap: 16 },
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
          name: t('station.pvPower'), type: 'line' as const, smooth: true, symbol: 'none',
          data: pvData,
          lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(245,158,11,0.3)' }, { offset: 1, color: 'rgba(245,158,11,0.02)' }] } },
        },
        {
          name: t('station.battChargeEnergy'), type: 'line' as const, smooth: true, symbol: 'none',
          data: battChargeData,
          lineStyle: { color: '#22c55e', width: 2 }, itemStyle: { color: '#22c55e' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(34,197,94,0.3)' }, { offset: 1, color: 'rgba(34,197,94,0.02)' }] } },
        },
        {
          name: t('station.battDischargeEnergy'), type: 'line' as const, smooth: true, symbol: 'none',
          data: battDischargeData,
          lineStyle: { color: '#3b82f6', width: 2 }, itemStyle: { color: '#3b82f6' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(59,130,246,0.02)' }, { offset: 1, color: 'rgba(59,130,246,0.2)' }] } },
        },
        {
          name: t('station.loadPower'), type: 'line' as const, smooth: true, symbol: 'none',
          data: loadData,
          lineStyle: { color: '#ef4444', width: 2 }, itemStyle: { color: '#ef4444' },
          areaStyle: { color: { type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(239,68,68,0.02)' }, { offset: 1, color: 'rgba(239,68,68,0.2)' }] } },
        },
      ],
      markLine: { silent: true, lineStyle: { color: '#94a3b8', type: 'solid' as const, width: 1 }, data: [{ yAxis: 0 }], label: { show: false } },
    }
  }, [flowData, period, timezone, t])

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

  // 30日发电趋势 ECharts 配置
  const trend30Option = useMemo(() => {
    if (!trend30Data?.length) return null
    return {
      tooltip: { trigger: 'axis' as const },
      grid: { left: '3%', right: '4%', bottom: '12%', top: 40, containLabel: true },
      xAxis: {
        type: 'category' as const,
        data: trend30Data.map((d: any) => dayjs(d.date).format('MM-DD')),
        axisLabel: { fontSize: 11, interval: 2 },
      },
      yAxis: { type: 'value' as const, name: 'kWh' },
      dataZoom: [{ type: 'inside' }, { type: 'slider', height: 20, bottom: 8 }],
      series: [{
        name: t('station.genEnergy'),
        type: 'line' as const,
        smooth: true,
        symbol: 'none',
        data: trend30Data.map((d: any) => safeNum(d.energy)),
        lineStyle: { color: '#f59e0b', width: 2 },
        itemStyle: { color: '#f59e0b' },
        areaStyle: {
          color: {
            type: 'linear' as const, x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: 'rgba(245,158,11,0.3)' },
              { offset: 1, color: 'rgba(245,158,11,0.02)' },
            ],
          },
        },
      }],
    }
  }, [trend30Data, t])

  // 电量概览 ECharts 配置
  const energyOverviewOption = useMemo(() => {
    if (!energyOverview || typeof energyOverview !== 'object') return null
    const categories = Array.isArray(energyOverview.categories) ? energyOverview.categories :
      (Array.isArray(energyOverview.dates) ? energyOverview.dates : [])
    const pvData = Array.isArray(energyOverview.pv) ? energyOverview.pv : []
    const chargeData = Array.isArray(energyOverview.charge) ? energyOverview.charge :
      (Array.isArray(energyOverview.batteryCharge) ? energyOverview.batteryCharge : [])
    const dischargeData = Array.isArray(energyOverview.discharge) ? energyOverview.discharge :
      (Array.isArray(energyOverview.batteryDischarge) ? energyOverview.batteryDischarge : [])
    const loadData = Array.isArray(energyOverview.load) ? energyOverview.load :
      (Array.isArray(energyOverview.dailyLoad) ? energyOverview.dailyLoad : [])
    if (!categories.length) return null
    return {
      tooltip: { trigger: 'axis' as const, axisPointer: { type: 'shadow' as const } },
      legend: { data: ['PV发电', '电池充电', '电池放电', '负载用电'], top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '12%', top: 45, containLabel: true },
      xAxis: { type: 'category' as const, data: categories, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value' as const, name: 'kWh' },
      series: [
        { name: 'PV发电', type: 'bar' as const, data: pvData.map((v: any) => safeNum(v)), itemStyle: { color: '#f59e0b', borderRadius: [3, 3, 0, 0] }, barMaxWidth: 20 },
        { name: '电池充电', type: 'bar' as const, data: chargeData.map((v: any) => safeNum(v)), itemStyle: { color: '#22c55e', borderRadius: [3, 3, 0, 0] }, barMaxWidth: 20 },
        { name: '电池放电', type: 'bar' as const, data: dischargeData.map((v: any) => safeNum(v)), itemStyle: { color: '#3b82f6', borderRadius: [3, 3, 0, 0] }, barMaxWidth: 20 },
        { name: '负载用电', type: 'bar' as const, data: loadData.map((v: any) => safeNum(v)), itemStyle: { color: '#ef4444', borderRadius: [3, 3, 0, 0] }, barMaxWidth: 20 },
      ],
    }
  }, [energyOverview])

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

      {/* 功率折线图（仅日粒度，使用 energy-flow API） */}
      {period === 'day' && (
        <Card
          bordered={false}
          style={{ borderRadius: 12, marginBottom: 16 }}
          title={t('station.powerTrend')}
          size="small"
          extra={
            <Space>
              <DatePicker
                value={dayjs(flowDate)}
                onChange={(d) => d && setFlowDate(dayjs(d).tz(timezone).format('YYYY-MM-DD'))}
                allowClear={false}
                style={{ width: 150 }}
                size="small"
              />
              <Button size="small" onClick={() => setFlowDate(dayjs().tz(timezone).subtract(1, 'day').format('YYYY-MM-DD'))}>昨天</Button>
              <Button size="small" onClick={() => setFlowDate(dayjs().tz(timezone).format('YYYY-MM-DD'))}>今天</Button>
            </Space>
          }
        >
          {flowLoading ? (
            <div style={{ height: 320, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spin /></div>
          ) : powerLineOption ? (
            <ReactECharts option={powerLineOption} style={{ height: 320 }} />
          ) : (
            <div style={{ textAlign: 'center', padding: '48px 0' }}>
              <Text type="secondary">{t('station.noData')}</Text>
            </div>
          )}
        </Card>
      )}

      {/* 电量柱状图 */}
      {energyBarOption && (
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }} title="电量统计" size="small">
          <ReactECharts option={energyBarOption} style={{ height: 320 }} />
        </Card>
      )}

      {/* 30日发电趋势折线图（新增） */}
      {trend30Option && (
        <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }} title={t('station.genTrend30Days')} size="small">
          <ReactECharts option={trend30Option} style={{ height: 320 }} />
        </Card>
      )}

      {/* 电量概览柱状图 + Segmented 切换（新增） */}
      <Card
        bordered={false}
        style={{ borderRadius: 12, marginBottom: 16 }}
        title={t('station.energyOverview')}
        size="small"
        extra={
          <Segmented
            size="small"
            options={[
              { label: t('station.dayPeriod'), value: 'day' },
              { label: t('station.monthPeriod'), value: 'month' },
              { label: t('station.yearPeriod'), value: 'year' },
            ]}
            value={overviewPeriod}
            onChange={v => setOverviewPeriod(v as string)}
          />
        }
      >
        {energyOverviewOption ? (
          <ReactECharts option={energyOverviewOption} style={{ height: 320 }} />
        ) : (
          <div style={{ textAlign: 'center', padding: '48px 0' }}>
            <Text type="secondary">{t('station.noData')}</Text>
          </div>
        )}
      </Card>

      {!isLoading && (!statsData || statsData.length === 0) && (
        <Card bordered={false} style={{ borderRadius: 12, textAlign: 'center', padding: '48px 24px' }}>
          <Text type="secondary">暂无统计数据</Text>
        </Card>
      )}
    </Spin>
  )
}

export default StationStatisticsTab
