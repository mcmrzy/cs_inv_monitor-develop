import { useEffect, useState, useCallback } from 'react'
import { Table, Tag, Typography, Space, Card, Row, Col, Statistic, Select } from 'antd'
import { AlertOutlined, WarningOutlined, InfoCircleOutlined, ReloadOutlined } from '@ant-design/icons'
import { alertApi } from '@/services/alertApi'
import { ALARM_LEVEL_MAP } from '@/utils/constants'

const { Title } = Typography

const AlertsPage: React.FC = () => {
  const [loading, setLoading] = useState(true)
  const [alerts, setAlerts] = useState<any[]>([])
  const [stats, setStats] = useState({ total: 0, unhandled: 0, critical: 0 })
  const [levelFilter, setLevelFilter] = useState<string>('all')

  const fetchAlerts = useCallback(async () => {
    try {
      const params: any = {}
      if (levelFilter !== 'all') params.alarmLevel = levelFilter
      const res = await alertApi.getAlerts(params)
      const list = res.data?.data?.list ?? res.data?.data?.items ?? res.data?.data ?? res.data ?? []
      setAlerts(list)
      setStats({
        total: list.length,
        unhandled: list.filter((a: any) => a.status === 0 || a.status === 'unhandled').length,
        critical: list.filter((a: any) => a.alarm_level === 1 || a.alarmLevel === 'critical').length,
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
      title: '时间',
      dataIndex: 'occurredAt',
      key: 'occurredAt',
      width: 160,
      render: (v: string, r: any) => {
        const t = v ?? r.occurred_at
        return t ? new Date(t).toLocaleString('zh-CN') : '-'
      },
    },
    {
      title: '设备SN',
      dataIndex: 'deviceSn',
      key: 'deviceSn',
      width: 140,
      render: (v: string, r: any) => <code>{v ?? r.device_sn ?? '-'}</code>,
    },
    {
      title: '级别',
      dataIndex: 'alarmLevel',
      key: 'alarmLevel',
      width: 80,
      render: (v: any, r: any) => {
        const level = v ?? r.alarm_level
        const info = ALARM_LEVEL_MAP[String(level)] ?? { label: level, color: 'default' }
        return <Tag color={info.color}>{info.label}</Tag>
      },
    },
    {
      title: '故障码',
      dataIndex: 'faultCode',
      key: 'faultCode',
      width: 80,
      render: (v: string, r: any) => v ?? r.fault_code ?? '-',
    },
    {
      title: '故障信息',
      dataIndex: 'faultMessage',
      key: 'faultMessage',
      render: (v: string, r: any) => v ?? r.fault_message ?? '-',
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 80,
      render: (status: any) => {
        const isUnhandled = status === 0 || status === 'unhandled'
        const isHandled = status === 1 || status === 'handled'
        return (
          <Tag color={isUnhandled ? 'red' : isHandled ? 'green' : 'default'}>
            {isUnhandled ? '未处理' : isHandled ? '已处理' : String(status)}
          </Tag>
        )
      },
    },
  ]

  return (
    <div style={{ padding: '0 0 24px' }}>
      <Space style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Title level={4} style={{ margin: 0 }}>🔔 告警消息</Title>
        <Tag icon={<ReloadOutlined spin={loading} />} color="processing">
          15秒自动刷新
        </Tag>
      </Space>

      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={24} sm={8}>
          <Card size="small">
            <Statistic title="告警总数" value={stats.total} prefix={<AlertOutlined />} valueStyle={{ color: '#1677ff' }} />
          </Card>
        </Col>
        <Col xs={24} sm={8}>
          <Card size="small">
            <Statistic title="未处理" value={stats.unhandled} prefix={<WarningOutlined />} valueStyle={{ color: '#ff4d4f' }} />
          </Card>
        </Col>
        <Col xs={24} sm={8}>
          <Card size="small">
            <Statistic title="严重告警" value={stats.critical} prefix={<InfoCircleOutlined />} valueStyle={{ color: '#fa8c16' }} />
          </Card>
        </Col>
      </Row>

      <Card>
        <Space style={{ marginBottom: 12 }}>
          <Select
            value={levelFilter}
            onChange={setLevelFilter}
            style={{ width: 120 }}
            options={[
              { value: 'all', label: '全部级别' },
              { value: '1', label: '严重' },
              { value: '2', label: '警告' },
              { value: '3', label: '提示' },
            ]}
          />
        </Space>
        <Table
          columns={columns}
          dataSource={alerts}
          rowKey={(r: any) => r.id ?? r._id}
          loading={loading}
          size="middle"
          pagination={{ pageSize: 20, showSizeChanger: false }}
        />
      </Card>
    </div>
  )
}

export default AlertsPage
