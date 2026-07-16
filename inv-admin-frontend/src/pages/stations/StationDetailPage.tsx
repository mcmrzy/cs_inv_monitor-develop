import React, { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import {
  Row, Col, Card, Typography, Tag, Button, Space, Tabs, Spin, Alert, List,
  Empty, Divider, Form, Input, InputNumber, Select, Modal, Grid, message,
} from 'antd'
import {
  ArrowLeftOutlined, EditOutlined, CloudOutlined, AlertOutlined,
  DashboardOutlined, BarChartOutlined, DesktopOutlined, ReloadOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import api from '@/services/api'
import { alertApi } from '@/services/alertApi'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import useAuthStore from '@/stores/authStore'
import useLocaleStore from '@/stores/localeStore'
import { Role } from '@/types'
import { getAlarmLevelDisplay, getAlarmMessageI18nKey } from '@/utils/constants'
import { formatInTimezone, TIMEZONE_LIST, getTimezoneLabel } from '@/utils/timezone'
import EnergyFlowDiagram from './components/EnergyFlowDiagram'
import PowerMetricCards from './components/PowerMetricCards'
import EnergySummaryCards from './components/EnergySummaryCards'
import SocialContribution from './components/SocialContribution'
import StationStatisticsTab from './components/StationStatisticsTab'
import StationDevicesTab from './components/StationDevicesTab'

const { Title, Text } = Typography

/* ==================== 状态配置 ==================== */

const getStatusConfig = (station: any, t: (key: string) => string) => {
  if ((station.fault_count ?? 0) > 0) return { color: 'red', text: t('station.fault') }
  if (station.device_count > 0 && (station.online_count ?? 0) === 0)
    return { color: 'default', text: t('station.offline') }
  if (station.status === 1) return { color: 'green', text: t('station.normal') }
  return { color: 'default', text: t('station.stopped') }
}

/* ==================== 告警级别辅助 ==================== */

const getAlarmCfg = (alarm: any, t: (key: string) => string) => {
  const cfg = getAlarmLevelDisplay(alarm.fault_code, alarm.alarm_level)
  const msgKey = getAlarmMessageI18nKey(alarm.fault_code)
  return {
    color: cfg.color,
    text: msgKey ? t(msgKey) : (cfg.i18nKey ? t(cfg.i18nKey) : cfg.label),
    message: msgKey ? t(msgKey) : (alarm.fault_message || alarm.fault_code || '-'),
  }
}

/* ==================== 主组件 ==================== */

const StationDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>()
  const stationId = Number(id)
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const screens = Grid.useBreakpoint()
  const [messageApi, contextHolder] = message.useMessage()

  const { t } = useTranslation()
  const { lang } = useLocaleStore()
  const { timezone } = useTimezoneStore()
  const { user, hasPermission } = useAuthStore()
  const isAdmin = user && (user.role === Role.SUPER_ADMIN || user.role === Role.ADMIN)

  const [activeTab, setActiveTab] = useState('overview')
  const [editModalOpen, setEditModalOpen] = useState(false)
  const [editForm] = Form.useForm()

  /* ---------- 数据获取 ---------- */

  const { data: stationDetail, isLoading, error, refetch } = useQuery({
    queryKey: ['station-detail', stationId],
    queryFn: () => api.get(`/stations/${stationId}`, { expectedDataShape: 'object' })
      .then(res => res?.data?.data ?? res?.data ?? {}),
    enabled: !!stationId,
    refetchInterval: 15000,
  })

  const station = stationDetail?.station ?? {}
  const devices = stationDetail?.devices ?? []

  const { data: weatherData } = useQuery({
    queryKey: ['station-weather', stationId],
    queryFn: () => api.get(`/stations/${stationId}/weather`, { expectedDataShape: 'object' })
      .then(res => res?.data?.data ?? res?.data ?? {}),
    enabled: !!stationId,
    staleTime: 300000,
  })

  const { data: recentAlarms } = useQuery({
    queryKey: ['station-recent-alarms', stationId],
    queryFn: () => alertApi.list({ station_id: stationId, page: 1, page_size: 5 })
      .then(res => {
        const d = res?.data?.data ?? res?.data ?? {}
        return d?.items ?? (Array.isArray(d) ? d : [])
      }),
    enabled: !!stationId,
  })

  /* ---------- 编辑保存 ---------- */

  const handleEditSave = async () => {
    try {
      const values = await editForm.validateFields()
      await api.put(`/stations/${stationId}`, values)
      messageApi.success(t('station.updateSuccess'))
      setEditModalOpen(false)
      queryClient.invalidateQueries({ queryKey: ['station-detail', stationId] })
      queryClient.invalidateQueries({ queryKey: ['stations'] })
    } catch {
      messageApi.error(t('station.updateFailed'))
    }
  }

  const openEditModal = () => {
    editForm.setFieldsValue({
      name: station.name || station.station_name,
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
  }

  /* ---------- Loading / Error 状态 ---------- */

  if (isLoading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: 400 }}>
        <Spin size="large" tip={t('common.loading')} />
      </div>
    )
  }

  if (error || !stationDetail) {
    return (
      <div style={{ padding: 24 }}>
        <Alert
          type="error"
          showIcon
          message={t('station.listLoadFailed')}
          action={<Button size="small" danger onClick={() => refetch()}>{t('station.retryLoad')}</Button>}
          style={{ marginBottom: 16 }}
        />
      </div>
    )
  }

  const statusCfg = getStatusConfig(station, t)

  /* ---------- 概览 Tab ---------- */

  const renderOverviewTab = () => (
    <>
      {/* 天气/容量信息条 */}
      <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }} styles={{ body: { padding: '16px 20px' } }}>
        <Row gutter={24} align="middle">
          <Col>
            <Space>
              <CloudOutlined style={{ fontSize: 20, color: '#94a3b8' }} />
              <span>{weatherData?.temperature ? `${weatherData.temperature.toFixed(1)}°C` : '--'}</span>
              <span style={{ color: '#94a3b8' }}>{weatherData?.description || ''}</span>
            </Space>
          </Col>
          <Col flex="auto">
            <Space split={<Divider type="vertical" />} wrap>
              {station.capacity && (
                <span>{t('station.capacity_kW')}: <strong>{station.capacity} kW</strong></span>
              )}
              <span>{t('station.deviceCount')}: <strong>{station.device_count ?? 0}</strong></span>
              <span>{t('station.onlineCount')}: <strong style={{ color: '#52c41a' }}>{station.online_count ?? 0}</strong></span>
            </Space>
          </Col>
        </Row>
      </Card>

      {/* 能量流图 */}
      <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
        <EnergyFlowDiagram
          pvPower={station.pv_power ?? 0}
          loadPower={station.load_power ?? 0}
          battPower={station.batt_power ?? 0}
          gridPower={station.grid_power ?? 0}
          battSoc={station.batt_soc ?? 0}
        />
      </Card>

      {/* 实时功率指标 */}
      <div style={{ marginBottom: 16 }}>
        <PowerMetricCards
          totalPower={station.total_power ?? 0}
          todayEnergy={station.today_energy ?? station.today_generation ?? 0}
        />
      </div>

      {/* 发电量汇总 */}
      <div style={{ marginBottom: 16 }}>
        <EnergySummaryCards
          monthEnergy={station.month_energy ?? 0}
          yearEnergy={station.year_energy ?? 0}
          totalEnergy={station.total_energy ?? station.total_generation ?? 0}
        />
      </div>

      {/* 最近告警 */}
      <Card
        bordered={false}
        style={{ borderRadius: 12, marginBottom: 16 }}
        title={
          <Space>
            <AlertOutlined style={{ color: '#ef4444' }} />
            {t('station.recentAlarms')}
          </Space>
        }
        extra={
          recentAlarms?.length > 0 && (
            <a onClick={() => setActiveTab('alarms')}>{t('station.viewAll')}</a>
          )
        }
      >
        {recentAlarms?.length > 0 ? (
          <List
            size="small"
            dataSource={recentAlarms}
            renderItem={(alarm: any) => {
              const cfg = getAlarmCfg(alarm, t)
              return (
                <List.Item>
                  <Space wrap>
                    <Tag color={cfg.color}>{cfg.text}</Tag>
                    <Text>{cfg.message}</Text>
                    <Text type="secondary">
                      {formatInTimezone(alarm.occurred_at || alarm.created_at, timezone, 'MM-DD HH:mm')}
                    </Text>
                  </Space>
                </List.Item>
              )
            }}
          />
        ) : (
          <Empty description={t('station.noAlarms')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
        )}
      </Card>

      {/* 社会贡献 */}
      <SocialContribution totalEnergy={station.total_energy ?? station.total_generation ?? 0} />
    </>
  )

  /* ---------- 渲染 ---------- */

  return (
    <div style={{ padding: '0 0 24px' }}>
      {contextHolder}

      {/* 顶部导航栏 */}
      <Row align="middle" justify="space-between" style={{ marginBottom: 20 }}>
        <Col>
          <Space wrap>
            <Button type="text" icon={<ArrowLeftOutlined />} onClick={() => navigate('/stations')}>
              {t('station.backToList')}
            </Button>
            <Title level={4} style={{ margin: 0 }}>
              {station.station_name || station.name || '-'}
            </Title>
            <Tag color={statusCfg.color}>{statusCfg.text}</Tag>
            {station.device_count > 0 && (
              <Tag color="blue">
                {station.online_count ?? 0}/{station.device_count} {t('station.devicesOnline')}
              </Tag>
            )}
          </Space>
        </Col>
        <Col>
          <Space>
            <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
            {isAdmin && hasPermission('stations:edit') && (
              <Button type="primary" icon={<EditOutlined />} onClick={openEditModal}>
                {t('common.edit')}
              </Button>
            )}
          </Space>
        </Col>
      </Row>

      {/* Tabs */}
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Tabs
          activeKey={activeTab}
          onChange={setActiveTab}
          items={[
            {
              key: 'overview',
              label: <span><DashboardOutlined /> {t('station.overview')}</span>,
              children: renderOverviewTab(),
            },
            {
              key: 'statistics',
              label: <span><BarChartOutlined /> {t('station.genStats')}</span>,
              children: <StationStatisticsTab stationId={stationId} timezone={station.timezone || timezone} />,
            },
            {
              key: 'devices',
              label: <span><DesktopOutlined /> {t('station.deviceList')} ({devices.length})</span>,
              children: <StationDevicesTab stationId={stationId} timezone={station.timezone || timezone} />,
            },
          ]}
        />
      </Card>

      {/* 编辑电站弹窗 */}
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
                <InputNumber style={{ width: '100%' }} min={0} />
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
                <InputNumber style={{ width: '100%' }} min={0} />
              </Form.Item>
            </Col>
            <Col span={8}>
              <Form.Item name="battery_capacity" label={t('station.batteryCapacity')}>
                <InputNumber style={{ width: '100%' }} min={0} />
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
    </div>
  )
}

export default StationDetailPage
