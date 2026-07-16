import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Typography, Tag, Select, message, Space,
  Drawer, Descriptions, Tabs, Statistic, Input, Button, Form, Modal, Empty, Spin, Grid,
  Tooltip, Radio, Alert,
} from 'antd'
import Popconfirm from '@/components/LocalizedPopconfirm'
import type { ColumnsType } from 'antd/es/table'
import {
  ReloadOutlined, SwapOutlined, EyeOutlined, EditOutlined,
  ApartmentOutlined, DesktopOutlined, CheckCircleOutlined, ThunderboltOutlined,
  SunOutlined, ArrowUpOutlined, FireOutlined, PlusOutlined, DeleteOutlined,
} from '@ant-design/icons'
import ReactECharts from '@/lib/echarts'
import dayjs from 'dayjs'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'
import { ALARM_LEVEL_MAP, DEVICE_STATUS_MAP, getAlarmLevelDisplay, getAlarmMessageI18nKey } from '@/utils/constants'
import { safeNum } from '@/utils/format'
import { formatInTimezone, TIMEZONE_LIST, getTimezoneLabel } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import useLocaleStore from '@/stores/localeStore'
import StatisticCard from '@/components/StatisticCard'

const { Title, Text } = Typography

/* ==================== 类型定义 ==================== */

interface StationItem {
  id: number
  name: string
  province?: string
  city?: string
  district?: string
  address?: string
  capacity?: number
  panel_count?: number
  battery_capacity?: number
  contact_name?: string
  contact_phone?: string
  install_date?: string
  timezone?: string
  status: number
  user_id?: number
  device_count?: number
  online_count?: number
  fault_count?: number
  today_generation?: number
  total_generation?: number
  created_at?: string
  [key: string]: any
}

interface StationSummary {
  totalStations: number
  totalDevices: number
  onlineDevices: number
  todayGeneration: number
}

interface DeviceItem {
  id: string | number
  sn: string
  model?: string
  status: number | string
  rated_power?: number
  firmware_version?: string
  last_online_at?: string
  realtime_power?: number
  [key: string]: any
}

interface AlarmItem {
  id: string | number
  device_sn?: string
  alarm_level: number | string
  fault_code?: string
  fault_message?: string
  status?: string
  occurred_at?: string
  created_at?: string
  [key: string]: any
}

interface StatisticsData {
  today?: number
  month?: number
  year?: number
  total?: number
  daily?: { date: string; value: number }[]
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

/* ==================== 主组件 ==================== */

const StationsPage: React.FC = () => {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { user, hasPermission } = useAuthStore()
  const [messageApi, contextHolder] = message.useMessage()
  const screens = Grid.useBreakpoint()

  const { t } = useTranslation()
  const { lang } = useLocaleStore()
  const { timezone } = useTimezoneStore()
  const isAdmin = user && (user.role === Role.SUPER_ADMIN || user.role === Role.ADMIN)

  /* ---------- 详情抽屉 ---------- */
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [currentStation, setCurrentStation] = useState<StationItem | null>(null)
  const [activeTab, setActiveTab] = useState('info')

  /* ---------- 编辑弹窗 ---------- */
  const [editModalOpen, setEditModalOpen] = useState(false)
  const [editForm] = Form.useForm()

  /* ---------- 创建电站弹窗 ---------- */
  const [addModalOpen, setAddModalOpen] = useState(false)
  const [addForm] = Form.useForm()
  const [addLoading, setAddLoading] = useState(false)

  /* ---------- 分配用户 ---------- */
  const [assignVisible, setAssignVisible] = useState(false)
  const [assignStation, setAssignStation] = useState<StationItem | null>(null)
  const [targetUserId, setTargetUserId] = useState<number | null>(null)

  /* ---------- 添加设备弹窗 ---------- */
  const [addDeviceModalOpen, setAddDeviceModalOpen] = useState(false)
  const [addDeviceSn, setAddDeviceSn] = useState('')
  const isSuperAdmin = user?.role === Role.SUPER_ADMIN

  /* ---------- 设备筛选 ---------- */
  const [deviceKeyword, setDeviceKeyword] = useState('')
  const [deviceStatusFilter, setDeviceStatusFilter] = useState<number | undefined>(undefined)

  /* ---------- 趋势图时间范围 ---------- */
  const [trendRange, setTrendRange] = useState<7 | 30>(30)

  /* ---------- 数据获取 ---------- */

  const { data: stations = [], isLoading, isError: stationsError, refetch } = useQuery({
    queryKey: ['stations'],
    queryFn: () => api.get('/stations', { params: { all: true }, expectedDataShape: 'page' }).then(extractList),
  })

  const { data: summary, error: summaryError, refetch: refetchSummary } = useQuery({
    queryKey: ['stations', 'summary'],
    queryFn: () => api.get('/stations/summary', { params: { all: true }, expectedDataShape: 'object' }).then(extractData),
  })

  const { data: users = [], error: usersError, refetch: refetchUsers } = useQuery({
    queryKey: ['users', 'all'],
    queryFn: () => api.get('/users', { params: { pageSize: 9999 }, expectedDataShape: 'page' }).then(extractList),
    enabled: !!isAdmin && hasPermission('users:view'),
  })

  /* ---------- 详情数据 ---------- */

  const { data: stationDevices = [], isLoading: devicesLoading, error: stationDevicesError, refetch: refetchStationDevices } = useQuery({
    queryKey: ['station-devices', currentStation?.id],
    queryFn: () => api.get('/devices', { params: { station_id: currentStation!.id, pageSize: 999 }, expectedDataShape: 'page' }).then(extractList),
    enabled: !!currentStation?.id && drawerOpen && activeTab === 'devices',
  })

  /* 实时数据批量获取 - 15秒刷新 */
  const { data: realtimeData, error: realtimeError, refetch: refetchRealtime } = useQuery({
    queryKey: ['station-devices-realtime', currentStation?.id],
    queryFn: async () => {
      const devices = stationDevices ?? []
      const results: Record<string, any> = {}
      await Promise.allSettled(
        devices.map(async (dev: any) => {
          try {
            const res = await deviceApi.getRealtime(dev.sn)
            results[dev.sn] = res.data?.data ?? res.data ?? {}
          } catch { /* ignore */ }
        })
      )
      return results
    },
    enabled: !!stationDevices?.length && !!currentStation?.id && drawerOpen && activeTab === 'devices',
    refetchInterval: 15000,
  })

  /* 实时字段渲染辅助 */
  const renderPower = (v: any) => {
    const n = safeNum(v)
    if (n === 0 && (v == null || v === '')) return '-'
    return <span style={{ color: n > 0 ? '#52c41a' : undefined, fontWeight: n > 0 ? 600 : 400 }}>{n} W</span>
  }

  const renderEnergy = (v: any) => {
    const n = safeNum(v)
    return n > 0 ? `${n.toFixed(1)} kWh` : '-'
  }

  const renderTemperature = (v: any) => {
    const n = safeNum(v)
    if (n === 0 && (v == null || v === '')) return '-'
    const color = n > 60 ? '#ff4d4f' : n > 45 ? '#fa8c16' : undefined
    const icon = <FireOutlined style={{ color, marginRight: 4 }} />
    return (
      <Tooltip title={n > 60 ? t('station.temperatureHigh') : n > 45 ? t('station.temperatureWarn') : undefined}>
        <span style={{ color }}>{icon}{n}°C</span>
      </Tooltip>
    )
  }

  const { data: stationStats, isLoading: statsLoading, error: statsError, refetch: refetchStats } = useQuery({
    queryKey: ['station-statistics', currentStation?.id, trendRange],
    queryFn: async () => {
      const res = await api.get(`/stations/${currentStation!.id}/statistics`, {
        expectedDataShape: 'array',
        params: {
          start_date: dayjs().tz(timezone).subtract(trendRange, 'day').format('YYYY-MM-DD'),
          end_date: dayjs().tz(timezone).format('YYYY-MM-DD'),
          period: 'day',
        }
      })
      const rawData = extractData(res)
      
      // 后端返回的是数组格式，需要转换为前端期望的对象格式
      if (Array.isArray(rawData)) {
        const daily = rawData.map((item: any) => ({
          date: item.time || item.date,
          value: item.daily_pv || item.value || 0
        }))
        
        // 计算汇总数据
        const today = daily.length > 0 ? daily[daily.length - 1].value : 0
        const total = daily.reduce((sum: number, item: any) => sum + item.value, 0)
        const monthStart = dayjs().tz(timezone).startOf('month').format('YYYY-MM-DD')
        const month = daily
          .filter((item: any) => item.date >= monthStart)
          .reduce((sum: number, item: any) => sum + item.value, 0)
        const yearStart = dayjs().tz(timezone).startOf('year').format('YYYY-MM-DD')
        const year = daily
          .filter((item: any) => item.date >= yearStart)
          .reduce((sum: number, item: any) => sum + item.value, 0)
        
        return { today, month, year, total, daily }
      }
      
      // 如果已经是对象格式，直接返回
      return rawData
    },
    enabled: !!currentStation?.id && drawerOpen && activeTab === 'statistics',
  })

  const { data: stationAlarms = [], isLoading: alarmsLoading, error: alarmsError, refetch: refetchAlarms } = useQuery({
    queryKey: ['station-alarms', currentStation?.id],
    queryFn: () => api.get('/alarms', { params: { station_id: currentStation!.id, pageSize: 999 }, expectedDataShape: 'page' }).then(extractList),
    enabled: !!currentStation?.id && drawerOpen && activeTab === 'alarms',
  })

  /* ---------- 设备绑定/移除 Mutation ---------- */

  const addToStationMutation = useMutation({
    mutationFn: ({ sn, stationId }: { sn: string; stationId: number }) =>
      deviceApi.addToStation(sn, stationId),
    onSuccess: () => {
      messageApi.success(t('station.addDeviceSuccess'))
      setAddDeviceModalOpen(false)
      setAddDeviceSn('')
      queryClient.invalidateQueries({ queryKey: ['station-devices', currentStation?.id] })
    },
    onError: (err: any) => {
      messageApi.error(err?.response?.data?.message || err?.message || t('common.error'))
    },
  })

  const removeFromStationMutation = useMutation({
    mutationFn: (sn: string) => deviceApi.removeFromStation(sn),
    onSuccess: () => {
      messageApi.success(t('station.removeDeviceSuccess'))
      queryClient.invalidateQueries({ queryKey: ['station-devices', currentStation?.id] })
    },
    onError: (err: any) => {
      messageApi.error(err?.response?.data?.message || err?.message || t('common.error'))
    },
  })

  /* ---------- 操作处理 ---------- */

  const handleAssign = async () => {
    if (!assignStation || targetUserId == null) return
    try {
      await api.put(`/stations/${assignStation.id}/assign`, { user_id: targetUserId })
      messageApi.success(t('station.assignSuccess'))
      setAssignVisible(false)
      setAssignStation(null)
      queryClient.invalidateQueries({ queryKey: ['stations'] })
    } catch {
      messageApi.error(t('station.assignFailed'))
    }
  }

  const handleEditSave = async () => {
    try {
      const values = await editForm.validateFields()
      await api.put(`/stations/${currentStation!.id}`, values)
      messageApi.success(t('station.updateSuccess'))
      setEditModalOpen(false)
      queryClient.invalidateQueries({ queryKey: ['stations'] })
      setCurrentStation({ ...currentStation!, ...values })
    } catch {
      messageApi.error(t('station.updateFailed'))
    }
  }

  const handleCreate = async () => {
    try {
      setAddLoading(true)
      const values = await addForm.validateFields()
      await api.post('/stations', values)
      messageApi.success(t('station.addSuccess'))
      setAddModalOpen(false)
      addForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['stations'] })
    } catch {
      messageApi.error(t('station.addFailed'))
    } finally {
      setAddLoading(false)
    }
  }

  const openDetail = (record: StationItem) => {
    setCurrentStation(record)
    setActiveTab('info')
    setDrawerOpen(true)
    setDeviceKeyword('')
    setDeviceStatusFilter(undefined)
  }

  const handleDelete = async (stationId: number) => {
    try {
      await api.delete(`/stations/${stationId}`)
      messageApi.success(t('station.deleteSuccess'))
      queryClient.invalidateQueries({ queryKey: ['stations'] })
    } catch {
      messageApi.error(t('station.deleteFailed'))
    }
  }

  /* ---------- 过滤后的设备列表 ---------- */

  const filteredDevices = useMemo(() => {
    let list = stationDevices
    if (deviceStatusFilter !== undefined) {
      list = list.filter((d: DeviceItem) => Number(d.status) === deviceStatusFilter)
    }
    if (deviceKeyword) {
      const kw = deviceKeyword.toLowerCase()
      list = list.filter((d: DeviceItem) =>
        d.sn?.toLowerCase().includes(kw) || d.model?.toLowerCase().includes(kw)
      )
    }
    return list
  }, [stationDevices, deviceStatusFilter, deviceKeyword])

  /* ---------- 发电统计图表配置 ---------- */

  const generationChartOption = useMemo(() => {
    const stats = stationStats as StatisticsData
    if (!stats?.daily || stats.daily.length === 0) return null
    return {
      tooltip: {
        trigger: 'axis' as const,
        formatter: (params: any) => {
          const p = params[0]
          return `${p.axisValue}<br/>${t('station.genEnergy')}: ${p.value} kWh`
        },
      },
      grid: { left: 50, right: 20, top: 20, bottom: 40 },
      xAxis: {
        type: 'category' as const,
        data: stats.daily.map((d) => dayjs(d.date).format('MM-DD')),
        axisLabel: {
          fontSize: 11,
          interval: trendRange === 30 ? 2 : 0,
        },
      },
      yAxis: {
        type: 'value' as const,
        name: 'kWh',
        axisLabel: { fontSize: 11 },
      },
      series: [
        {
          name: t('station.genEnergy'),
          type: 'line',
          data: stats.daily.map((d) => d.value),
          smooth: true,
          areaStyle: {
            color: {
              type: 'linear' as const,
              x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(22,119,255,0.3)' },
                { offset: 1, color: 'rgba(22,119,255,0.02)' },
              ],
            },
          },
          lineStyle: { width: 2, color: '#1677ff' },
          itemStyle: { color: '#1677ff' },
        },
      ],
    }
  }, [stationStats, trendRange, t])

  /* ---------- 电站表格列定义 ---------- */

  const columns: ColumnsType<StationItem> = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: t('station.stationName'), dataIndex: 'name', width: 150 },
    {
      title: t('station.location'),
      key: 'location',
      width: 180,
      render: (_: any, r: StationItem) =>
        [r.province, r.city, r.district].filter(Boolean).join(' ') || r.address || '-',
    },
    {
      title: t('station.capacity_kW'),
      dataIndex: 'capacity',
      width: 90,
      render: (v: number) => v ? `${v}` : '-',
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      width: 70,
      render: (v: number) => (
        <Tag color={v === 1 ? 'green' : 'red'}>{v === 1 ? t('station.normal') : t('station.stopped')}</Tag>
      ),
    },
    {
      title: t('station.deviceCount'),
      dataIndex: 'device_count',
      width: 80,
      render: (v: number) => v ?? '-',
    },
    {
      title: t('station.onlineCount'),
      dataIndex: 'online_count',
      width: 60,
      render: (v: number) => (
        <span style={{ color: '#52c41a', fontWeight: 600 }}>{v ?? '-'}</span>
      ),
    },
    {
      title: t('station.faultCount'),
      dataIndex: 'fault_count',
      width: 60,
      render: (v: number) => (
        <span style={{ color: v && v > 0 ? '#ff4d4f' : undefined, fontWeight: v && v > 0 ? 600 : undefined }}>
          {v ?? '-'}
        </span>
      ),
    },
    {
      title: t('station.todayGeneration'),
      dataIndex: 'today_generation',
      width: 110,
      render: (v: number) => v != null ? v.toFixed(1) : '-',
    },
    {
      title: t('station.totalGeneration'),
      dataIndex: 'total_generation',
      width: 120,
      render: (v: number) => v != null ? v.toLocaleString() : '-',
    },
    {
      title: t('station.createDate'),
      dataIndex: 'created_at',
      width: 110,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD') : '-',
    },
    ...(isAdmin ? [
      {
        title: t('station.ownerUserID'),
        dataIndex: 'user_id',
        width: 110,
        render: (uid: number) => {
          const u = users.find((x: any) => x.id === uid)
          return u ? `${u.nickname || u.phone} (${uid})` : String(uid ?? '-')
        },
      },
    ] : []),
    {
      title: t('common.operation'),
      key: 'action',
      width: 180,
      fixed: screens.md ? undefined as any : undefined,
      render: (_: any, record: StationItem) => (
        <Space>
          <a onClick={() => openDetail(record)}><EyeOutlined /> {t('common.detail')}</a>
          {isAdmin && hasPermission('stations:edit') && (
            <Popconfirm
              title={t('station.assignStation')}
              description={
                <Select
                  showSearch
                  style={{ width: 250 }}
                  placeholder={t('station.selectUser')}
                  optionFilterProp="label"
                  onChange={(val) => setTargetUserId(val)}
                  options={users.map((u: any) => ({
                    value: u.id,
                    label: `${u.nickname || u.phone} (ID:${u.id})`,
                  }))}
                />
              }
              onConfirm={handleAssign}
              onCancel={() => setAssignStation(null)}
              onOpenChange={(open) => { if (open) setAssignStation(record) }}
            >
              <a><SwapOutlined /> {t('station.assign')}</a>
            </Popconfirm>
          )}
          <a onClick={() => {
            editForm.setFieldsValue({
              name: record.name,
              province: record.province,
              city: record.city,
              district: record.district,
              address: record.address,
              capacity: record.capacity,
              panel_count: record.panel_count,
              battery_capacity: record.battery_capacity,
              contact_name: record.contact_name,
              contact_phone: record.contact_phone,
              timezone: record.timezone || 'Asia/Shanghai',
            })
            setCurrentStation(record)
            setEditModalOpen(true)
          }}><EditOutlined /> {t('common.edit')}</a>
          <Popconfirm
            title={t('station.deleteConfirm')}
            onConfirm={() => handleDelete(record.id)}
            okText={t('common.confirm')}
            cancelText={t('common.cancel')}
            okButtonProps={{ danger: true }}
          >
            <a style={{ color: '#ff4d4f' }}><DeleteOutlined /> {t('common.delete')}</a>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  /* ---------- 设备表格列定义 ---------- */

  const deviceColumns: ColumnsType<DeviceItem> = [
    { title: 'SN', dataIndex: 'sn', width: 160 },
    { title: t('common.model'), dataIndex: 'model', width: 120 },
    {
      title: t('common.status'),
      dataIndex: 'status',
      width: 80,
      render: (v: number | string) => {
        const s = DEVICE_STATUS_MAP[String(v)]
        return s ? <Tag color={s.color}>{t(s.i18nKey)}</Tag> : <Tag>{v}</Tag>
      },
    },
    {
      title: t('station.ratedPower_W'),
      dataIndex: 'rated_power',
      width: 100,
      render: (v: number) => v ?? '-',
    },
    {
      title: t('station.firmwareVersion'),
      dataIndex: 'firmware_arm',
      width: 100,
      render: (v: string) => v || '-',
    },
    {
      title: t('station.lastComm'),
      dataIndex: 'last_online_at',
      width: 150,
      render: (v: string, record: any) => formatInTimezone(v, record.timezone, 'YYYY-MM-DD HH:mm'),
    },
    {
      title: t('station.realtimePower_W'),
      width: 110,
      render: (_: any, record: DeviceItem) => {
        if (String(record.status) !== '1' && record.status !== 1) return <Text type="secondary">{t('station.offline')}</Text>
        const rt = realtimeData?.[record.sn]
        const power = rt?.total_active_power ?? rt?.ac_power ?? rt?.power ?? record.current_power
        return renderPower(power)
      },
    },
    {
      title: t('station.dailyGen_kWh'),
      width: 110,
      render: (_: any, record: DeviceItem) => {
        const rt = realtimeData?.[record.sn]
        const energy = rt?.daily_pv ?? rt?.daily_energy ?? record.daily_energy
        return renderEnergy(energy)
      },
    },
    {
      title: t('common.operation'),
      key: 'action',
      width: 80,
      render: (_: any, r: DeviceItem) => (
        <a onClick={() => {
          setDrawerOpen(false)
          navigate(`/devices?sn=${r.sn}`)
        }}>
          {t('station.view')}
        </a>
      ),
    },
    {
      title: t('common.actions'),
      key: 'actions',
      width: 100,
      fixed: 'right' as const,
      render: (_: any, record: DeviceItem) => (
        (isSuperAdmin || currentStation?.user_id === user?.id) && (
          <Popconfirm
            title={t('station.confirmRemoveDevice')}
            onConfirm={() => removeFromStationMutation.mutate(record.sn)}
            okText={t('common.confirm')}
            cancelText={t('common.cancel')}
          >
            <Button type="link" size="small" danger>
              {t('station.removeDevice')}
            </Button>
          </Popconfirm>
        )
      ),
    },
  ]

  /* ---------- 告警表格列定义 ---------- */

  const alarmColumns: ColumnsType<AlarmItem> = [
    {
      title: t('common.time'),
      dataIndex: 'occurred_at',
      width: 160,
      render: (v: string, r: AlarmItem) => {
        const time = v || r.created_at
        return time ? formatInTimezone(time, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'
      },
    },
    { title: t('common.deviceSN'), dataIndex: 'device_sn', width: 160 },
    {
      title: t('station.alertLevel'),
      dataIndex: 'alarm_level',
      width: 80,
      render: (v: number | string, record: any) => {
        const cfg = getAlarmLevelDisplay(record.fault_code, v)
        return <Tag color={cfg.color}>{cfg.i18nKey ? t(cfg.i18nKey) : cfg.label}</Tag>
      },
    },
    { title: t('station.faultCode'), dataIndex: 'fault_code', width: 100 },
    {
      title: t('station.faultMessage'),
      dataIndex: 'fault_message',
      ellipsis: true,
      render: (message: string, record: AlarmItem) => {
        const key = getAlarmMessageI18nKey(record.fault_code)
        return key ? t(key) : message
      },
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      width: 80,
      render: (v: string) => {
        if (v === 'resolved' || v === 'handled') return <Tag color="green">{t('station.alarmHandled')}</Tag>
        if (v === 'active' || v === 'pending') return <Tag color="red">{t('station.alarmUnhandled')}</Tag>
        return <Tag>{v || '-'}</Tag>
      },
    },
  ]

  /* ==================== 详情抽屉内容 ==================== */

  const renderInfoTab = () => {
    const station = currentStation
    if (!station) return null
    return (
      <>
        <div style={{ marginBottom: 16, textAlign: 'right' }}>
          {isAdmin && hasPermission('stations:edit') && (
            <Button
              type="primary"
              icon={<EditOutlined />}
              onClick={() => {
                editForm.setFieldsValue({
                  name: station.name,
                  province: station.province,
                  city: station.city,
                  district: station.district,
                  address: station.address,
                  capacity: station.capacity,
                  panel_count: station.panel_count,
                  battery_capacity: station.battery_capacity,
                  contact_name: station.contact_name,
                  contact_phone: station.contact_phone,
                  install_date: station.install_date ? dayjs(station.install_date) : undefined,
                  status: station.status,
                  timezone: station.timezone || 'Asia/Shanghai',
                })
                setEditModalOpen(true)
              }}
            >
              {t('station.editInfo')}
            </Button>
          )}
        </div>
        <Descriptions
          bordered
          column={screens.md ? 2 : 1}
          size="small"
        >
          <Descriptions.Item label={t('station.stationName')}>{station.name || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('common.status')}>
            <Tag color={station.status === 1 ? 'green' : 'red'}>
              {station.status === 1 ? t('station.normal') : t('station.stopped')}
            </Tag>
          </Descriptions.Item>
          <Descriptions.Item label={t('station.province')}>{station.province || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.city')}>{station.city || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.district')}>{station.district || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.address')}>{station.address || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.capacity_kW')}>{station.capacity ? `${station.capacity} kW` : '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.panelCount')}>{station.panel_count ?? '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.batteryCapacity')}>{station.battery_capacity ? `${station.battery_capacity} kWh` : '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.contact')}>{station.contact_name || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.contactPhone')}>{station.contact_phone || '-'}</Descriptions.Item>
          <Descriptions.Item label={t('station.installDate')}>
            {station.install_date ? formatInTimezone(station.install_date, timezone, 'YYYY-MM-DD') : '-'}
          </Descriptions.Item>
          <Descriptions.Item label={t('station.timezone')}>{getTimezoneLabel(station.timezone || 'Asia/Shanghai', lang)}</Descriptions.Item>
          <Descriptions.Item label={t('common.createdAt')}>
            {formatInTimezone(station.created_at, timezone)}
          </Descriptions.Item>
        </Descriptions>
      </>
    )
  }

  const renderDevicesTab = () => (
    <>
      <Space style={{ marginBottom: 16 }} wrap>
        <Input.Search
          placeholder={t('station.searchSN')}
          style={{ width: 200 }}
          allowClear
          onSearch={setDeviceKeyword}
          onChange={(e) => { if (!e.target.value) setDeviceKeyword('') }}
        />
        <Select
          placeholder={t('station.deviceStatus')}
          style={{ width: 120 }}
          allowClear
          value={deviceStatusFilter}
          onChange={setDeviceStatusFilter}
          options={[
            { value: 1, label: t('common.online') },
            { value: 0, label: t('common.offline') },
            { value: 2, label: t('station.deviceFault') },
          ]}
        />
        <Button icon={<ReloadOutlined />} onClick={() => queryClient.invalidateQueries({ queryKey: ['station-devices', currentStation?.id] })}>
          {t('common.refresh')}
        </Button>
        {(isSuperAdmin || currentStation?.user_id === user?.id) && (
          <Button
            type="primary"
            icon={<PlusOutlined />}
            onClick={() => { setAddDeviceSn(''); setAddDeviceModalOpen(true) }}
          >
            {t('station.addDevice')}
          </Button>
        )}
      </Space>
      <Table<DeviceItem>
        columns={deviceColumns}
        dataSource={filteredDevices}
        rowKey="id"
        loading={devicesLoading}
        size="small"
        pagination={{ pageSize: 10, showTotal: (total) => t('common.total', { total }) }}
        scroll={{ x: 800 }}
      />
    </>
  )

  const renderStatisticsTab = () => {
    const stats = stationStats as StatisticsData
    if (statsLoading) {
      return <div style={{ textAlign: 'center', padding: 80 }}><Spin tip={t('common.loading')} /></div>
    }
    return (
      <>
        <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
          <Col xs={12} sm={6}>
            <StatisticCard size="small"
              title={t('station.todayGen')}
              value={stats?.today ?? 0}
              precision={1}
              suffix="kWh"
              prefix={<SunOutlined />}
              valueStyle={{ color: '#fa8c16', fontSize: 20 }}
            />
          </Col>
          <Col xs={12} sm={6}>
            <StatisticCard size="small"
              title={t('station.monthGen')}
              value={stats?.month ?? 0}
              precision={1}
              suffix="kWh"
              prefix={<ThunderboltOutlined />}
              valueStyle={{ color: '#1677ff', fontSize: 20 }}
            />
          </Col>
          <Col xs={12} sm={6}>
            <StatisticCard size="small"
              title={t('station.yearGen')}
              value={stats?.year ?? 0}
              precision={0}
              suffix="kWh"
              prefix={<ArrowUpOutlined />}
              valueStyle={{ color: '#52c41a', fontSize: 20 }}
            />
          </Col>
          <Col xs={12} sm={6}>
            <StatisticCard size="small"
              title={t('station.totalGen')}
              value={stats?.total ?? 0}
              precision={0}
              suffix="kWh"
              prefix={<ThunderboltOutlined />}
              valueStyle={{ color: '#722ed1', fontSize: 20 }}
            />
          </Col>
        </Row>
        <Card
          title={t('station.genTrend30Days')}
          size="small"
          bordered={false}
          style={{ borderRadius: 12 }}
          extra={
            <Radio.Group
              value={trendRange}
              onChange={(e) => setTrendRange(e.target.value)}
              size="small"
              optionType="button"
              buttonStyle="solid"
            >
              <Radio.Button value={7}>7D</Radio.Button>
              <Radio.Button value={30}>30D</Radio.Button>
            </Radio.Group>
          }
        >
          {generationChartOption ? (
            <ReactECharts option={generationChartOption} style={{ height: 280 }} />
          ) : (
            <Empty description={t('station.noGenData')} />
          )}
        </Card>
      </>
    )
  }

  const renderAlarmsTab = () => (
    <>
      <Space style={{ marginBottom: 16 }}>
        <Button icon={<ReloadOutlined />} onClick={() => queryClient.invalidateQueries({ queryKey: ['station-alarms', currentStation?.id] })}>
          {t('common.refresh')}
        </Button>
      </Space>
      <Table<AlarmItem>
        columns={alarmColumns}
        dataSource={stationAlarms}
        rowKey="id"
        loading={alarmsLoading}
        size="small"
        pagination={{ pageSize: 10, showTotal: (total) => t('common.total', { total }) }}
        scroll={{ x: 700 }}
      />
    </>
  )

  /* ==================== 渲染 ==================== */

  const secondaryQueryFailure = [
    { error: summaryError, retry: refetchSummary },
    { error: usersError, retry: refetchUsers },
    { error: stationDevicesError, retry: refetchStationDevices },
    { error: realtimeError, retry: refetchRealtime },
    { error: statsError, retry: refetchStats },
    { error: alarmsError, retry: refetchAlarms },
  ].find((item) => item.error)

  return (
    <div style={{ padding: '0 0 24px' }}>
      {contextHolder}
      {stationsError && (
        <Alert
          type="error"
          showIcon
          message={t('station.listLoadFailed')}
          action={<Button size="small" danger onClick={() => refetch()}>{t('station.retryLoad')}</Button>}
          style={{ marginBottom: 16 }}
        />
      )}
      {secondaryQueryFailure && (
        <QueryErrorAlert
          error={secondaryQueryFailure.error}
          onRetry={() => { void secondaryQueryFailure.retry() }}
          style={{ marginBottom: 16 }}
        />
      )}
      <Space style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Title level={4} style={{ margin: 0 }}>⚡ {t('station.title')}</Title>
        <Space>
          {isAdmin && (
            <Button type="primary" icon={<PlusOutlined />} onClick={() => setAddModalOpen(true)}>
              {t('station.addStation')}
            </Button>
          )}
          {isAdmin && <Tag icon={<ReloadOutlined spin={isLoading} />} color="processing">{t('station.manageAll')}</Tag>}
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Space>
      </Space>

      {/* 汇总卡片 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={12} sm={6}>
          <StatisticCard size="small"
            title={t('station.stationTotal')}
            value={summary?.totalStations ?? stations.length}
            prefix={<ApartmentOutlined />}
            valueStyle={{ color: '#1677ff' }}
          />
        </Col>
        <Col xs={12} sm={6}>
          <StatisticCard size="small"
            title={t('station.deviceTotal')}
            value={summary?.totalDevices ?? stations.reduce((s: number, st: StationItem) => s + (st.device_count ?? 0), 0)}
            prefix={<DesktopOutlined />}
            valueStyle={{ color: '#722ed1' }}
          />
        </Col>
        <Col xs={12} sm={6}>
          <StatisticCard size="small"
            title={t('station.deviceOnline')}
            value={summary?.onlineDevices ?? stations.reduce((s: number, st: StationItem) => s + (st.online_count ?? 0), 0)}
            prefix={<CheckCircleOutlined />}
            valueStyle={{ color: '#52c41a' }}
          />
        </Col>
        <Col xs={12} sm={6}>
          <StatisticCard size="small"
            title={t('station.todayGen_kWh')}
            value={summary?.todayGeneration ?? stations.reduce((s: number, st: StationItem) => s + (st.today_generation ?? 0), 0)}
            precision={1}
            prefix={<SunOutlined />}
            valueStyle={{ color: '#fa8c16' }}
          />
        </Col>
      </Row>

      {/* 电站列表 */}
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Table<StationItem>
          columns={columns}
          dataSource={stations}
          rowKey="id"
          loading={isLoading}
          size="small"
          pagination={{ pageSize: 20, showSizeChanger: true, showTotal: (total) => t('common.total', { total }) }}
          scroll={{ x: 1200 }}
        />
      </Card>

      {/* 详情抽屉 */}
      <Drawer
        title={currentStation ? `${currentStation.name} - ${t('station.stationDetail')}` : t('station.stationDetail')}
        open={drawerOpen}
        onClose={() => {
          setDrawerOpen(false)
          setCurrentStation(null)
        }}
        width={screens.md ? 800 : '100%'}
        destroyOnClose
      >
        <Tabs
          activeKey={activeTab}
          onChange={setActiveTab}
          items={[
            { key: 'info', label: t('station.stationInfo'), children: renderInfoTab() },
            { key: 'devices', label: `${t('station.deviceList')} (${stationDevices.length || currentStation?.device_count || 0})`, children: renderDevicesTab() },
            { key: 'statistics', label: t('station.genStats'), children: renderStatisticsTab() },
            { key: 'alarms', label: t('station.alertRecords'), children: renderAlarmsTab() },
          ]}
        />
      </Drawer>

      {/* 编辑弹窗 */}
      <Modal
        title={t('station.editStation')}
        open={editModalOpen}
        onCancel={() => setEditModalOpen(false)}
        onOk={handleEditSave}
        width={600}
        destroyOnClose
      >
        <Form form={editForm} layout="vertical" style={{ marginTop: 16 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="name" label={t('station.stationName')} rules={[{ required: true }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="capacity" label={t('station.capacity_kW')}>
                <Input type="number" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="province" label={t('station.province')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="city" label={t('station.city')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="district" label={t('station.district')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="address" label={t('station.address')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="panel_count" label={t('station.panelCount')}>
                <Input type="number" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="battery_capacity" label={t('station.batteryCapacity')}>
                <Input type="number" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="status" label={t('common.status')}>
                <Select
                  options={[
                    { value: 1, label: t('station.normal') },
                    { value: 0, label: t('station.stopped') },
                  ]}
                />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="timezone" label={t('station.timezone')}>
                <Select
                  showSearch
                  placeholder={t('station.selectTimezone')}
                  options={TIMEZONE_LIST.map(tz => ({ value: tz.id, label: getTimezoneLabel(tz.id, lang) }))}
                  filterOption={(input, option) =>
                    (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
                  }
                />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="contact_name" label={t('station.contact')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="contact_phone" label={t('station.contactPhone')}>
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      {/* 添加设备弹窗 */}
      <Modal
        title={t('station.addDevice')}
        open={addDeviceModalOpen}
        onCancel={() => { setAddDeviceModalOpen(false); setAddDeviceSn('') }}
        onOk={() => {
          if (addDeviceSn.trim() && currentStation?.id) {
            addToStationMutation.mutate({ sn: addDeviceSn.trim(), stationId: currentStation.id })
          }
        }}
        confirmLoading={addToStationMutation.isPending}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
      >
        <div style={{ padding: '16px 0' }}>
          <div style={{ marginBottom: 8 }}>{t('station.searchDeviceSN')}</div>
          <Input
            value={addDeviceSn}
            onChange={(e) => setAddDeviceSn(e.target.value)}
            placeholder={t('station.searchDeviceSN')}
          />
        </div>
      </Modal>

      {/* 创建电站弹窗 */}
      <Modal
        title={t('station.addStationTitle')}
        open={addModalOpen}
        onCancel={() => {
          setAddModalOpen(false)
          addForm.resetFields()
        }}
        onOk={handleCreate}
        confirmLoading={addLoading}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
        width={600}
        destroyOnClose
      >
        <Form form={addForm} layout="vertical" style={{ marginTop: 16 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="name" label={t('station.stationName')} rules={[{ required: true, message: t('station.stationName') }]}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="capacity" label={t('station.capacity_kW')}>
                <Input type="number" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="province" label={t('station.province')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="city" label={t('station.city')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="district" label={t('station.district')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={24}>
              <Form.Item name="address" label={t('station.address')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="panel_count" label={t('station.panelCount')}>
                <Input type="number" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="battery_capacity" label={t('station.batteryCapacity')}>
                <Input type="number" />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="timezone" label={t('station.timezone')}>
                <Select
                  showSearch
                  placeholder={t('station.selectTimezone')}
                  options={TIMEZONE_LIST.map(tz => ({ value: tz.id, label: getTimezoneLabel(tz.id, lang) }))}
                  filterOption={(input, option) =>
                    (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
                  }
                />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="contact_name" label={t('station.contact')}>
                <Input />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="contact_phone" label={t('station.contactPhone')}>
                <Input />
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>
    </div>
  )
}

export default StationsPage
