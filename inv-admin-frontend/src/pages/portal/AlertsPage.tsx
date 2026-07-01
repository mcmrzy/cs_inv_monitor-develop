import { useEffect, useState, useCallback } from 'react'
import { Table, Tag, Typography, Space, Card, Row, Col, Statistic, Select } from 'antd'
import { AlertOutlined, WarningOutlined, InfoCircleOutlined, ReloadOutlined } from '@ant-design/icons'
import dayjs from 'dayjs'
import { alertApi } from '@/services/alertApi'
import { ALARM_LEVEL_MAP, getAlarmLevelDisplay } from '@/utils/constants'
import useTranslation from '@/hooks/useTranslation'

const { Title } = Typography

const AlertsPage: React.FC = () => {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(true)
  const [alerts, setAlerts] = useState<any[]>([])
  const [stats, setStats] = useState({ total: 0, unhandled: 0, critical: 0 })
  const [levelFilter, setLevelFilter] = useState<string>('all')

  const fetchAlerts = useCallback(async () => {
    try {
      const params: any = {}
      if (levelFilter !== 'all') params.alarmLevel = levelFilter
      const res = await alertApi.list(params)
      const list = res.data?.data?.list ?? res.data?.data?.items ?? res.data?.data ?? res.data ?? []
      setAlerts(list)
      setStats({
        total: list.length,
        unhandled: list.filter((a: any) => a.status === 0 || a.status === 'unhandled').length,
        critical: list.filter((a: any) => a.alarm_level === 3 || a.alarmLevel === 3 || a.alarmLevel === 'critical').length,
      })
    } catch { /* ignore */ }
    setLoading(false)
  }, [levelFilter])

  useEffect(() => {
    fetchAlerts()
    const timer = setInterval(fetchAlerts, 15000)
    return () => clearInterval(timer)
  }, [fetchAlerts])

  const columns = [
    {
      title: t('common.time'),
      dataIndex: 'occurredAt',
      key: 'occurredAt',
      width: 160,
      render: (v: string, r: any) => {
        const t = v ?? r.occurred_at
        return t ? dayjs(t).format('YYYY-MM-DD HH:mm:ss') : '-'
      },
    },
    {
      title: t('common.deviceSN'),
      dataIndex: 'deviceSn',
      key: 'deviceSn',
      width: 140,
      render: (v: string, r: any) => <code>{v ?? r.device_sn ?? '-'}</code>,
    },
    {
      title: t('portal.alertLevel'),
      dataIndex: 'alarmLevel',
      key: 'alarmLevel',
      width: 80,
      render: (v: any, r: any) => {
        const level = v ?? r.alarm_level
        const info = getAlarmLevelDisplay(r.fault_code ?? r.faultCode, level)
        return <Tag color={info.color}>{info.label}</Tag>
      },
    },
    {
      title: t('portal.faultCode'),
      dataIndex: 'faultCode',
      key: 'faultCode',
      width: 80,
      render: (v: string, r: any) => v ?? r.fault_code ?? '-',
    },
    {
      title: t('portal.faultInfo'),
      dataIndex: 'faultMessage',
      key: 'faultMessage',
      render: (v: string, r: any) => v ?? r.fault_message ?? '-',
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 80,
      render: (status: any) => {
        const isUnhandled = status === 0 || status === 'unhandled'
        const isHandled = status === 1 || status === 'handled'
        return (
          <Tag color={isUnhandled ? 'red' : isHandled ? 'green' : 'default'}>
            {isUnhandled ? t('portal.unprocessed') : isHandled ? t('portal.handled') : String(status)}
          </Tag>
        )
      },
    },
  ]

  return (
    <div style={{ padding: '0 0 24px' }}>
      <Space style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Title level={4} style={{ margin: 0 }}>🔔 {t('portal.alertMessage')}</Title>
        <Tag icon={<ReloadOutlined spin={loading} />} color="processing">
          {t('portal.autoRefresh15')}
        </Tag>
      </Space>

      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={24} sm={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('portal.alertTotal')} value={stats.total} prefix={<AlertOutlined />} valueStyle={{ color: '#1677ff' }} />
          </Card>
        </Col>
        <Col xs={24} sm={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('portal.unprocessed')} value={stats.unhandled} prefix={<WarningOutlined />} valueStyle={{ color: '#ff4d4f' }} />
          </Card>
        </Col>
        <Col xs={24} sm={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('portal.criticalAlerts')} value={stats.critical} prefix={<InfoCircleOutlined />} valueStyle={{ color: '#fa8c16' }} />
          </Card>
        </Col>
      </Row>

      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Space style={{ marginBottom: 12 }}>
          <Select
            value={levelFilter}
            onChange={setLevelFilter}
            style={{ width: 120 }}
            options={[
              { value: 'all', label: t('portal.allLevels') },
              { value: '1', label: t('portal.critical') },
              { value: '2', label: t('portal.warning') },
              { value: '3', label: t('portal.info') },
            ]}
          />
        </Space>
        <Table
          columns={columns}
          dataSource={alerts}
          rowKey={(r: any) => r.id ?? r._id}
          loading={loading}
          size="small"
          pagination={{ pageSize: 20, showSizeChanger: false }}
        />
      </Card>
    </div>
  )
}

export default AlertsPage
