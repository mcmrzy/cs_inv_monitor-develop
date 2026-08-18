/**
 * 能量统计：今日三巨头强调卡（光伏发电/电池充电/用电）+ 次级分项
 * + 近 7 日趋势（getTelemetry + echarts）+ 累计能量与环保贡献。
 * 今日实时能量同样受新鲜度约束，离线时不展示陈旧缓存值；
 * 7 日趋势与累计来自历史遥测/数据库聚合，离线仍可展示。
 */
import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Spin, Statistic, Typography, Empty } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import { BarChartOutlined } from '@ant-design/icons'
import dayjs from 'dayjs'

import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { safeNum } from '@/utils/format'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import ReactECharts from '@/lib/echarts'
import SocialContribution from '@/pages/stations/components/SocialContribution'
import { toRtEnvelope, freshRealtime, extractEnergyMetrics } from './energyUtils'

const { Text } = Typography

interface EnergyStatsTabProps {
  sn: string
}

const CARD_SHADOW = '0 2px 8px rgba(17,24,39,0.06)'

interface DayEnergy {
  date: string
  pv: number
  charge: number
  discharge: number
  load: number
  totalPv: number
}

/** 从单条遥测行中取日累计能量（兼容 V2 *_energy 与 V1 兼容字段） */
const rowDaily = (row: any) => ({
  pv: safeNum(row?.daily_pv_energy ?? row?.daily_pv),
  charge: safeNum(row?.daily_charge_energy ?? row?.daily_charge),
  discharge: safeNum(row?.daily_discharge_energy ?? row?.daily_discharge),
  load: safeNum(row?.daily_load_energy ?? row?.daily_load ?? row?.daily_consumption),
  totalPv: safeNum(row?.total_pv_energy ?? row?.total_energy ?? row?.total_pv),
})

const EnergyStatsTab: React.FC<EnergyStatsTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()

  // 今日能量（实时 envelope，新鲜度约束）
  const { data: envelope } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => toRtEnvelope(r.data?.data ?? r.data)),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })
  const m = extractEnergyMetrics(freshRealtime(envelope))
  const todayFresh = freshRealtime(envelope) != null

  // 近 7 日趋势：按天窗口请求遥测，取每日累计计数器最大值（V2 为 3 分钟粒度原始行）
  const { data: daily7, isLoading: trendLoading } = useQuery({
    queryKey: ['device-energy-7d', sn],
    queryFn: async () => {
      const days = Array.from({ length: 7 }, (_, i) => dayjs().tz(timezone).subtract(6 - i, 'day'))
      const results = await Promise.allSettled(
        days.map(async (day) => {
          const res = await deviceApi.getTelemetry(sn, {
            startTime: day.startOf('day').toISOString(),
            endTime: day.endOf('day').toISOString(),
            granularity: 'hour',
            page_size: 500,
          })
          const d = res.data?.data ?? res.data ?? {}
          const items: any[] = Array.isArray(d) ? d : (d?.items ?? d?.list ?? [])
          const agg: DayEnergy = { date: day.format('YYYY-MM-DD'), pv: 0, charge: 0, discharge: 0, load: 0, totalPv: 0 }
          items.forEach((row) => {
            const v = rowDaily(row)
            agg.pv = Math.max(agg.pv, v.pv)
            agg.charge = Math.max(agg.charge, v.charge)
            agg.discharge = Math.max(agg.discharge, v.discharge)
            agg.load = Math.max(agg.load, v.load)
            agg.totalPv = Math.max(agg.totalPv, v.totalPv)
          })
          return agg
        }),
      )
      return results.map((r) => (r.status === 'fulfilled' ? r.value : null)).filter(Boolean) as DayEnergy[]
    },
    staleTime: 5 * 60_000,
  })

  // 设备级累计统计（数据库聚合，离线可用）
  const { data: deviceStats } = useQuery({
    queryKey: ['device-stats', sn],
    queryFn: () => api.get(`/devices/by-sn/${sn}/statistics`, { expectedDataShape: 'object' }).then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      return {
        totalEnergy: safeNum(d?.total_energy),
        dailyEnergy: safeNum(d?.daily_energy),
        monthlyEnergy: safeNum(d?.monthly_energy),
      }
    }),
    staleTime: 5 * 60_000,
  })

  // 累计 PV 发电：优先 DB 统计，回退遥测最新 total_pv_energy
  const totalPvKwh = useMemo(() => {
    const fromTelemetry = Math.max(...(daily7 ?? []).map((d) => d.totalPv), 0)
    return Math.max(deviceStats?.totalEnergy ?? 0, fromTelemetry)
  }, [deviceStats, daily7])

  // 7 日趋势 echarts 配置
  const trendOption = useMemo(() => {
    const rows = daily7 ?? []
    if (rows.length === 0) return null
    const labels = rows.map((d) => dayjs(d.date).format('MM-DD'))
    const seriesConfig = [
      { name: t('deviceDetail.stats.dailyPv'), color: '#F59E0B', key: 'pv' as const },
      { name: t('deviceDetail.stats.dailyCharge'), color: '#22c55e', key: 'charge' as const },
      { name: t('deviceDetail.stats.dailyDischarge'), color: '#3b82f6', key: 'discharge' as const },
      { name: t('deviceDetail.stats.dailyLoad'), color: '#ef4444', key: 'load' as const },
    ]
    return {
      tooltip: {
        trigger: 'axis' as const,
        axisPointer: { type: 'shadow' as const },
        valueFormatter: (v: any) => `${Number(v ?? 0).toFixed(2)} kWh`,
      },
      legend: { data: seriesConfig.map((s) => s.name), top: 0, itemGap: 16 },
      grid: { left: '3%', right: '4%', bottom: '8%', top: 45, containLabel: true },
      xAxis: { type: 'category' as const, data: labels, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value' as const, name: 'kWh' },
      series: seriesConfig.map((s) => ({
        name: s.name,
        type: 'bar' as const,
        data: rows.map((d) => parseFloat(d[s.key].toFixed(2))),
        itemStyle: { color: s.color, borderRadius: [4, 4, 0, 0] },
        barMaxWidth: 18,
      })),
    }
  }, [daily7, t])

  // 今日三巨头：光伏发电 / 电池充电 / 用电（大数字强调卡）
  const todayCards = [
    { key: 'pv', icon: '☀️', label: t('deviceDetail.stats.dailyPv'), value: m.dailyPv, color: '#F59E0B', bg: '#fffbeb' },
    { key: 'charge', icon: '🔋', label: t('deviceDetail.stats.dailyCharge'), value: m.dailyCharge, color: '#22c55e', bg: '#f0fdf4' },
    { key: 'load', icon: '🏠', label: t('deviceDetail.stats.dailyLoad'), value: m.dailyLoad, color: '#ef4444', bg: '#fef2f2' },
  ]

  // 次级分项：仅在有值（>0）时展示，不铺全量 14 个能量字段
  const todaySecondary = [
    { key: 'discharge', label: t('deviceDetail.stats.dailyDischarge'), value: m.dailyDischarge },
    { key: 'feed', label: t('deviceDetail.stats.dailyFeed'), value: m.dailyFeedEnergy },
    { key: 'import', label: t('deviceDetail.stats.dailyGridImport'), value: m.dailyGridImport },
  ].filter((s) => s.value > 0)

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* ── 今日能量：三巨头强调卡 + 次级分项 ── */}
      {todayFresh ? (
        <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} bodyStyle={{ padding: 20 }}>
          <Row gutter={[16, 16]}>
            {todayCards.map((c) => (
              <Col xs={24} md={8} key={c.key}>
                <div style={{ borderRadius: 12, background: c.bg, padding: '18px 20px' }}>
                  <div style={{ fontSize: 13, color: '#6b7280', fontWeight: 500 }}>{c.icon} {c.label}</div>
                  <div style={{ fontSize: 28, fontWeight: 700, color: c.color, lineHeight: 1.3 }}>
                    {c.value.toFixed(1)} <span style={{ fontSize: 14, fontWeight: 500 }}>kWh</span>
                  </div>
                </div>
              </Col>
            ))}
          </Row>
          {todaySecondary.length > 0 && (
            <div style={{ marginTop: 14, display: 'flex', gap: 24, flexWrap: 'wrap' }}>
              {todaySecondary.map((s) => (
                <Text key={s.key} type="secondary" style={{ fontSize: 12 }}>
                  {s.label}: <Text strong>{s.value.toFixed(1)} kWh</Text>
                </Text>
              ))}
            </div>
          )}
        </ProCard>
      ) : (
        <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} bodyStyle={{ padding: '24px', textAlign: 'center' }}>
          <Text type="secondary">{t('deviceDetail.stats.todayOffline')}</Text>
        </ProCard>
      )}

      {/* ── 近 7 日趋势 ── */}
      <ProCard
        style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
        title={<span style={{ fontWeight: 600 }}><BarChartOutlined style={{ color: '#00D4FF', marginRight: 6 }} />{t('deviceDetail.stats.trend7d')}</span>}
        size="small"
      >
        <Spin spinning={trendLoading}>
          {trendOption ? (
            <ReactECharts option={trendOption} style={{ height: 320 }} />
          ) : (
            <Empty description={t('deviceDetail.stats.noTrendData')} image={Empty.PRESENTED_IMAGE_SIMPLE} style={{ padding: '32px 0' }} />
          )}
        </Spin>
      </ProCard>

      {/* ── 累计与环保贡献 ── */}
      <Row gutter={[16, 16]}>
        <Col xs={24} lg={10}>
          <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} title={<span style={{ fontWeight: 600 }}>{t('deviceDetail.stats.cumulativeTitle')}</span>} size="small">
            <Row gutter={[16, 16]}>
              <Col span={12}>
                <Statistic title={t('deviceDetail.stats.cumPv')} value={totalPvKwh} precision={1} suffix="kWh" valueStyle={{ color: '#F59E0B', fontWeight: 700 }} />
              </Col>
              <Col span={12}>
                <Statistic title={t('deviceDetail.stats.monthEnergy')} value={deviceStats?.monthlyEnergy ?? 0} precision={1} suffix="kWh" valueStyle={{ color: '#00D4FF', fontWeight: 700 }} />
              </Col>
              <Col span={12}>
                <Statistic title={t('deviceDetail.stats.todayEnergy')} value={todayFresh ? m.dailyPv : (deviceStats?.dailyEnergy ?? 0)} precision={1} suffix="kWh" valueStyle={{ fontWeight: 700 }} />
              </Col>
              <Col span={12}>
                <Statistic title={t('deviceDetail.stats.cumDischarge')} value={todayFresh ? m.totalDischarge : 0} precision={1} suffix="kWh" valueStyle={{ color: '#3b82f6', fontWeight: 700 }} />
              </Col>
            </Row>
          </ProCard>
        </Col>
        <Col xs={24} lg={14}>
          <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} title={<span style={{ fontWeight: 600 }}>🌍 {t('deviceDetail.stats.ecoTitle')}</span>} size="small">
            <SocialContribution totalEnergy={totalPvKwh} />
            <Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 4 }}>
              {t('deviceDetail.stats.ecoHint')}
            </Text>
          </ProCard>
        </Col>
      </Row>
    </div>
  )
}

export default EnergyStatsTab
