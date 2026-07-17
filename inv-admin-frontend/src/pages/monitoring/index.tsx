import { useState, useMemo, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Card, Input, Typography, Space, Spin, Empty, Grid, Segmented, Statistic } from 'antd'
import {
  SearchOutlined, ReloadOutlined, ApartmentOutlined,
  DesktopOutlined, CheckCircleOutlined, WarningOutlined,
  ThunderboltOutlined, SunOutlined,
} from '@ant-design/icons'
import api from '@/services/api'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import StationCard from '../stations/components/StationCard'

const { Title } = Typography

/* ==================== 类型定义 ==================== */

interface StationItem {
  id: number
  name: string
  province?: string
  city?: string
  district?: string
  address?: string
  capacity?: number
  device_count?: number
  online_count?: number
  fault_count?: number
  today_generation?: number
  total_generation?: number
  status: number
  [key: string]: any
}

interface StationSummary {
  totalStations: number
  totalDevices: number
  onlineDevices: number
  todayGeneration: number
}

/* ==================== 工具函数 ==================== */

const extractList = (res: any): any[] => {
  const d = res?.data?.data ?? res?.data ?? []
  if (Array.isArray(d)) return d
  return d?.items ?? d?.list ?? []
}

const extractData = (res: any): any => {
  return res?.data?.data ?? res?.data ?? {}
}

type FilterType = 'all' | 'normal' | 'fault' | 'offline'

/* ==================== 主组件 ==================== */

const MonitoringPage: React.FC = () => {
  const navigate = useNavigate()
  const { t } = useTranslation()
  const screens = Grid.useBreakpoint()

  const [filter, setFilter] = useState<FilterType>('all')
  const [keyword, setKeyword] = useState('')

  /* ---------- 自动跳转上次电站 ---------- */

  const { data: stations = [], isLoading, isError, error, refetch } = useQuery({
    queryKey: ['stations'],
    queryFn: () => api.get('/stations', { params: { all: true }, expectedDataShape: 'page' }).then(extractList),
  })

  useEffect(() => {
    if (!isLoading && stations.length > 0) {
      const lastId = localStorage.getItem('last_selected_station')
      // Only auto-navigate once per session to avoid trapping user
      const alreadyRedirected = sessionStorage.getItem('monitoring_auto_nav')
      if (lastId && !alreadyRedirected) {
        const exists = stations.some((s: StationItem) => String(s.id) === lastId)
        if (exists) {
          sessionStorage.setItem('monitoring_auto_nav', '1')
          navigate(`/monitoring/${lastId}`)
        }
      }
    }
  }, [isLoading, stations, navigate])

  const { data: summary } = useQuery({
    queryKey: ['stations', 'summary'],
    queryFn: () => api.get('/stations/summary', { params: { all: true }, expectedDataShape: 'object' }).then(extractData),
  })

  /* ---------- 统计计数 ---------- */

  const counts = useMemo(() => {
    let normal = 0
    let fault = 0
    let offline = 0
    for (const s of stations as StationItem[]) {
      const fc = s.fault_count ?? 0
      const dc = s.device_count ?? 0
      const oc = s.online_count ?? 0
      if (fc > 0) fault++
      else if (dc > 0 && oc === 0) offline++
      else normal++
    }
    return { all: stations.length, normal, fault, offline }
  }, [stations])

  /* ---------- 筛选 & 搜索 ---------- */

  const filtered = useMemo(() => {
    let list = stations as StationItem[]

    // 状态筛选
    if (filter !== 'all') {
      list = list.filter((s) => {
        const fc = s.fault_count ?? 0
        const dc = s.device_count ?? 0
        const oc = s.online_count ?? 0
        if (filter === 'fault') return fc > 0
        if (filter === 'offline') return dc > 0 && oc === 0 && fc === 0
        // normal
        return fc === 0 && !(dc > 0 && oc === 0)
      })
    }

    // 关键词搜索
    if (keyword.trim()) {
      const kw = keyword.trim().toLowerCase()
      list = list.filter(
        (s) =>
          s.name?.toLowerCase().includes(kw) ||
          s.address?.toLowerCase().includes(kw) ||
          s.province?.toLowerCase().includes(kw) ||
          s.city?.toLowerCase().includes(kw) ||
          s.district?.toLowerCase().includes(kw),
      )
    }

    return list
  }, [stations, filter, keyword])

  /* ---------- 汇总数据 ---------- */

  const summaryData: StationSummary = useMemo(() => {
    if (summary && typeof summary === 'object' && 'totalStations' in summary) {
      return summary as StationSummary
    }
    // 从 stations 数组自行计算
    let totalDevices = 0
    let onlineDevices = 0
    let todayGeneration = 0
    for (const s of stations as StationItem[]) {
      totalDevices += s.device_count ?? 0
      onlineDevices += s.online_count ?? 0
      todayGeneration += s.today_generation ?? 0
    }
    return {
      totalStations: stations.length,
      totalDevices,
      onlineDevices,
      todayGeneration: Math.round(todayGeneration * 10) / 10,
    }
  }, [summary, stations])

  /* ---------- 筛选选项 ---------- */

  const filterOptions = [
    { label: `${t('common.all')} (${counts.all})`, value: 'all' as const },
    {
      label: (
        <Space size={4}>
          <CheckCircleOutlined style={{ color: '#52c41a' }} />
          {t('station.normal')} ({counts.normal})
        </Space>
      ),
      value: 'normal' as const,
    },
    {
      label: (
        <Space size={4}>
          <WarningOutlined style={{ color: '#ff4d4f' }} />
          {t('station.fault')} ({counts.fault})
        </Space>
      ),
      value: 'fault' as const,
    },
    {
      label: (
        <Space size={4}>
          <DesktopOutlined style={{ color: '#8c8c8c' }} />
          {t('station.offline')} ({counts.offline})
        </Space>
      ),
      value: 'offline' as const,
    },
  ]

  /* ---------- 渲染 ---------- */

  if (isError) {
    return (
      <div style={{ padding: 24 }}>
        <QueryErrorAlert error={error} onRetry={refetch} />
      </div>
    )
  }

  return (
    <div style={{ padding: screens.md ? 24 : 16 }}>
      {/* 页头 */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
        <Title level={4} style={{ margin: 0 }}>
          <ApartmentOutlined style={{ marginRight: 8 }} />
          {t('mon.title')}
        </Title>
        <Space>
          <Input
            placeholder={t('station.searchStation')}
            prefix={<SearchOutlined />}
            allowClear
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            style={{ width: screens.sm ? 260 : 180 }}
          />
          <ReloadOutlined
            spin={isLoading}
            style={{ fontSize: 18, cursor: 'pointer', color: '#1677ff' }}
            onClick={() => refetch()}
          />
        </Space>
      </div>

      {/* 汇总统计 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 20 }}>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ borderRadius: 10 }}>
            <Statistic
              title={t('station.stationTotal')}
              value={summaryData.totalStations}
              prefix={<ApartmentOutlined />}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ borderRadius: 10 }}>
            <Statistic
              title={t('station.deviceTotal')}
              value={summaryData.totalDevices}
              prefix={<DesktopOutlined />}
              valueStyle={{ color: '#1677ff' }}
            />
          </Card>
        </Col>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ borderRadius: 10 }}>
            <Statistic
              title={t('station.deviceOnline')}
              value={summaryData.onlineDevices}
              prefix={<CheckCircleOutlined />}
              valueStyle={{ color: '#52c41a' }}
            />
          </Card>
        </Col>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ borderRadius: 10 }}>
            <Statistic
              title={t('station.todayGen_kWh')}
              value={summaryData.todayGeneration}
              precision={1}
              prefix={<SunOutlined />}
              valueStyle={{ color: '#fa8c16' }}
            />
          </Card>
        </Col>
      </Row>

      {/* 状态筛选 */}
      <div style={{ marginBottom: 16 }}>
        <Segmented
          options={filterOptions}
          value={filter}
          onChange={(v) => setFilter(v as FilterType)}
          size={screens.md ? 'middle' : 'small'}
        />
      </div>

      {/* 电站卡片列表 */}
      <Spin spinning={isLoading}>
        {filtered.length === 0 ? (
          <Empty
            description={keyword ? t('station.noData') : t('station.noData')}
            style={{ marginTop: 80 }}
          />
        ) : (
          <Row gutter={[16, 16]}>
            {filtered.map((station) => (
              <Col key={station.id} xs={24} sm={12} md={8} lg={6}>
                <StationCard
                  station={station}
                  onClick={() => {
                    localStorage.setItem('last_selected_station', String(station.id))
                    navigate(`/monitoring/${station.id}`)
                  }}
                />
              </Col>
            ))}
          </Row>
        )}
      </Spin>
    </div>
  )
}

export default MonitoringPage
