import React, { useState, useEffect, useCallback } from 'react'
import {
  Tabs,
  Card,
  Table,
  Button,
  Modal,
  Form,
  Input,
  Select,
  Tag,
  Drawer,
  Timeline,
  Dropdown,
  Space,
  Row,
  Col,
  DatePicker,
  Statistic,
  Popconfirm,
  message,
} from 'antd'
import {
  PlusOutlined,
  ReloadOutlined,
  EyeOutlined,
  CheckOutlined,
  StopOutlined,
  DownOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import type { MenuProps } from 'antd'
import dayjs from 'dayjs'
import { alertApi } from '@/services/alertApi'
import { workOrderApi, type WorkOrderDetail } from '@/services/workOrderApi'
import { userApi } from '@/services/userApi'
import { ALARM_LEVEL_MAP } from '@/utils/constants'
import type { Alert, WorkOrder, User } from '@/types'
import AlertRulesPage from '@/pages/alert-rules'

const { TextArea } = Input
const { RangePicker } = DatePicker

const ALERT_STATUS_MAP: Record<string, { label: string; color: string }> = {
  '0': { label: '未处理', color: '#ff4d4f' },
  '1': { label: '已处理', color: '#52c41a' },
  '2': { label: '已忽略', color: '#d9d9d9' },
  unhandled: { label: '未处理', color: '#ff4d4f' },
  handled: { label: '已处理', color: '#52c41a' },
  ignored: { label: '已忽略', color: '#d9d9d9' },
}

const WO_PRIORITY_MAP: Record<string, { label: string; color: string }> = {
  low: { label: '低', color: '#d9d9d9' },
  medium: { label: '中', color: '#1677ff' },
  high: { label: '高', color: '#fa8c16' },
  urgent: { label: '紧急', color: '#ff4d4f' },
}

const WO_STATUS_MAP: Record<string, { label: string; color: string }> = {
  open: { label: '待处理', color: '#1677ff' },
  in_progress: { label: '处理中', color: '#1677ff' },
  resolved: { label: '已解决', color: '#52c41a' },
  closed: { label: '已关闭', color: '#d9d9d9' },
}

const WO_STATUS_OPTIONS = Object.keys(WO_STATUS_MAP)

const AlertsPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState('alerts')

  return (
    <div>
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        items={[
          { key: 'alerts', label: '告警记录', children: <AlertTab /> },
          { key: 'rules', label: '告警规则', children: <AlertRulesPage /> },
          { key: 'workorders', label: '工单管理', children: <WorkOrderTab /> },
        ]}
      />
    </div>
  )
}

const AlertTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<Alert[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [levelFilter, setLevelFilter] = useState<string>()
  const [keyword, setKeyword] = useState<string>()
  const [dateRange, setDateRange] = useState<[dayjs.Dayjs, dayjs.Dayjs] | null>(null)
  const [stats, setStats] = useState({ total: 0, unhandled: 0, handled: 0, critical: 0 })

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await alertApi.list({
        page,
        pageSize,
        status: statusFilter !== undefined ? Number(statusFilter) : undefined,
        alarmLevel: levelFilter !== undefined ? Number(levelFilter) : undefined,
        keyword: keyword || undefined,
        startTime: dateRange?.[0]?.format('YYYY-MM-DD'),
        endTime: dateRange?.[1]?.format('YYYY-MM-DD'),
      })
      const d = res.data
      setData((d?.data?.list ?? d?.data?.items ?? []) as Alert[])
      setTotal(d?.data?.total ?? 0)
    } catch {
      message.error('获取告警列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, statusFilter, levelFilter, keyword, dateRange])

  const fetchStats = async () => {
    try {
      const res = await alertApi.getStats()
      setStats(res.data.data ?? { total: 0, unhandled: 0, handled: 0, critical: 0 })
    } catch {}
  }

  useEffect(() => {
    fetchData()
    fetchStats()
  }, [fetchData])

  const handleHandle = async (id: string) => {
    try {
      await alertApi.handle(id)
      message.success('已确认处理')
      fetchData()
      fetchStats()
    } catch {
      message.error('操作失败')
    }
  }

  const handleIgnore = async (id: string) => {
    try {
      await alertApi.ignore(Number(id))
      message.success('已忽略')
      fetchData()
      fetchStats()
    } catch {
      message.error('操作失败')
    }
  }

  const columns: ColumnsType<Alert> = [
    { title: 'SN', dataIndex: 'device_sn', key: 'device_sn', width: 140 },
    { title: '故障码', dataIndex: 'fault_code', key: 'fault_code', width: 100 },
    {
      title: '告警级别',
      dataIndex: 'alarm_level',
      key: 'alarm_level',
      width: 100,
      render: (level: number | string) => {
        const key = typeof level === 'number' ? String(level) : level
        const cfg = ALARM_LEVEL_MAP[key] || { label: String(level), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '故障信息',
      dataIndex: 'fault_message',
      key: 'fault_message',
      ellipsis: true,
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 90,
      render: (status: number | string) => {
        const key = typeof status === 'number' ? String(status) : status
        const cfg = ALERT_STATUS_MAP[key] || { label: String(status), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '发生时间',
      dataIndex: 'occurred_at',
      key: 'occurred_at',
      width: 170,
      render: (val: string) => val ? dayjs(val).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: '操作',
      key: 'action',
      width: 160,
      render: (_: any, record: any) => (
        <Space>
          {String(record.status) === '0' && (
            <>
              <Popconfirm title="确认处理该告警？" onConfirm={() => handleHandle(record.id)}>
                <Button type="link" size="small" icon={<CheckOutlined />}>
                  确认处理
                </Button>
              </Popconfirm>
              <Popconfirm title="确认忽略该告警？" onConfirm={() => handleIgnore(record.id)}>
                <Button type="link" size="small" icon={<StopOutlined />}>
                  忽略
                </Button>
              </Popconfirm>
            </>
          )}
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <Card size="small">
            <Statistic title="告警总数" value={stats.total} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic title="未处理" value={stats.unhandled} valueStyle={{ color: '#ff4d4f' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic title="已处理" value={stats.handled} valueStyle={{ color: '#52c41a' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic title="严重告警" value={stats.critical} valueStyle={{ color: '#ff4d4f' }} />
          </Card>
        </Col>
      </Row>

      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Select
              allowClear
              placeholder="状态"
              style={{ width: 120 }}
              value={statusFilter}
              onChange={(val) => { setStatusFilter(val); setPage(1) }}
              options={[
                { label: '未处理', value: '0' },
                { label: '已处理', value: '1' },
                { label: '已忽略', value: '2' },
              ]}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="级别"
              style={{ width: 120 }}
              value={levelFilter}
              onChange={(val) => { setLevelFilter(val); setPage(1) }}
              options={[
                { label: '严重', value: '1' },
                { label: '警告', value: '2' },
                { label: '提示', value: '3' },
              ]}
            />
          </Col>
          <Col>
            <Input.Search
              allowClear
              placeholder="搜索SN、故障信息"
              style={{ width: 220 }}
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              onSearch={() => { setPage(1); fetchData() }}
            />
          </Col>
          <Col>
            <RangePicker
              value={dateRange as any}
              onChange={(vals) => { setDateRange(vals as any); setPage(1) }}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={fetchData}>刷新</Button>
          </Col>
        </Row>
      </Card>

      <Table<Alert>
        rowKey="id"
        columns={columns}
        dataSource={data}
        loading={loading}
        rowClassName={(record: any) => record.alarm_level === 1 ? 'alert-row-critical' : ''}
        pagination={{
          current: page,
          pageSize,
          total,
          showSizeChanger: true,
          showTotal: (t) => `共 ${t} 条`,
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />
    </div>
  )
}

const WorkOrderTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<WorkOrder[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [priorityFilter, setPriorityFilter] = useState<string>()
  const [createOpen, setCreateOpen] = useState(false)
  const [creating, setCreating] = useState(false)
  const [installers, setInstallers] = useState<User[]>([])
  const [detailOpen, setDetailOpen] = useState(false)
  const [detail, setDetail] = useState<WorkOrderDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [form] = Form.useForm()

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await workOrderApi.list({
        page,
        pageSize,
        status: statusFilter || undefined,
        priority: priorityFilter || undefined,
      })
      const d = res.data
      setData((d?.list ?? d?.data?.list ?? d?.data?.items ?? []) as WorkOrder[])
      setTotal((d?.total ?? d?.data?.total ?? 0) as number)
    } catch {
      message.error('获取工单列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, statusFilter, priorityFilter])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const openCreate = async () => {
    setCreateOpen(true)
    try {
      const res = await userApi.getInstallers()
      const d = res.data
      setInstallers((d?.data ?? d?.items ?? d ?? []) as User[])
    } catch {}
  }

  const handleCreate = async () => {
    try {
      const values = await form.validateFields()
      setCreating(true)
      await workOrderApi.create(values)
      message.success('工单创建成功')
      setCreateOpen(false)
      form.resetFields()
      fetchData()
    } catch {
      message.error('创建失败')
    } finally {
      setCreating(false)
    }
  }

  const openDetail = async (id: string) => {
    setDetailLoading(true)
    setDetailOpen(true)
    try {
      const res = await workOrderApi.getDetail(id)
      const d = res.data
      setDetail((d?.data ?? d ?? null) as WorkOrderDetail | null)
    } catch {
      message.error('获取详情失败')
    } finally {
      setDetailLoading(false)
    }
  }

  const handleStatusChange = async (id: string, newStatus: string, resolution?: string) => {
    try {
      await workOrderApi.updateStatus(id, newStatus)
      message.success('状态更新成功')
      fetchData()
      if (detailOpen) openDetail(id)
    } catch {
      message.error('状态更新失败')
    }
  }

  const statusMenuItems = (id: string): MenuProps['items'] =>
    WO_STATUS_OPTIONS.map((s) => {
      const cfg = WO_STATUS_MAP[s]
      return { key: s, label: <Tag color={cfg.color}>{cfg.label}</Tag> }
    })

  const columns: ColumnsType<WorkOrder> = [
    { title: '标题', dataIndex: 'title', key: 'title', width: 180, ellipsis: true },
    {
      title: '优先级',
      dataIndex: 'priority',
      key: 'priority',
      width: 80,
      render: (val: string) => {
        const cfg = WO_PRIORITY_MAP[val] || { label: val, color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 90,
      render: (val: string) => {
        const cfg = WO_STATUS_MAP[val] || { label: val, color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '创建时间',
      dataIndex: 'createdAt',
      key: 'createdAt',
      width: 170,
      render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: '操作',
      key: 'action',
      width: 180,
      render: (_: any, record: WorkOrder) => (
        <Space>
          <Button type="link" size="small" icon={<EyeOutlined />} onClick={() => openDetail(record.id)}>
            详情
          </Button>
          <Dropdown
            menu={{
              items: statusMenuItems(record.id),
              onClick: ({ key }) => handleStatusChange(record.id, key),
            }}
          >
            <Button type="link" size="small">
              状态 <DownOutlined />
            </Button>
          </Dropdown>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
              创建工单
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="状态"
              style={{ width: 120 }}
              value={statusFilter}
              onChange={(val) => { setStatusFilter(val); setPage(1) }}
              options={Object.entries(WO_STATUS_MAP).map(([k, v]) => ({ label: v.label, value: k }))}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="优先级"
              style={{ width: 120 }}
              value={priorityFilter}
              onChange={(val) => { setPriorityFilter(val); setPage(1) }}
              options={Object.entries(WO_PRIORITY_MAP).map(([k, v]) => ({ label: v.label, value: k }))}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={fetchData}>刷新</Button>
          </Col>
        </Row>
      </Card>

      <Table<WorkOrder>
        rowKey="id"
        columns={columns}
        dataSource={data}
        loading={loading}
        pagination={{
          current: page,
          pageSize,
          total,
          showSizeChanger: true,
          showTotal: (t) => `共 ${t} 条`,
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      <Modal
        title="创建工单"
        open={createOpen}
        onCancel={() => { setCreateOpen(false); form.resetFields() }}
        onOk={handleCreate}
        confirmLoading={creating}
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Form.Item name="title" label="标题" rules={[{ required: true, message: '请输入标题' }]}>
            <Input placeholder="工单标题" />
          </Form.Item>
          <Form.Item name="description" label="描述" rules={[{ required: true, message: '请输入描述' }]}>
            <TextArea rows={3} placeholder="详细描述" />
          </Form.Item>
          <Form.Item name="deviceSn" label="关联设备SN">
            <Input placeholder="可选" />
          </Form.Item>
          <Form.Item name="priority" label="优先级" rules={[{ required: true, message: '请选择优先级' }]}>
            <Select
              placeholder="选择优先级"
              options={Object.entries(WO_PRIORITY_MAP).map(([k, v]) => ({ label: v.label, value: k }))}
            />
          </Form.Item>
          <Form.Item name="assigneeId" label="指派人" rules={[{ required: true, message: '请选择指派人' }]}>
            <Select
              placeholder="选择安装商"
              options={installers.map((u) => ({ label: u.nickname || u.phone, value: u.id }))}
            />
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title="工单详情"
        open={detailOpen}
        onClose={() => { setDetailOpen(false); setDetail(null) }}
        width={640}
        destroyOnClose
      >
        {detail && (
          <div>
            <Card size="small" style={{ marginBottom: 16 }}>
              <p><strong>标题：</strong>{detail.title}</p>
              <p><strong>优先级：</strong>
                <Tag color={WO_PRIORITY_MAP[detail.priority]?.color}>
                  {WO_PRIORITY_MAP[detail.priority]?.label || detail.priority}
                </Tag>
              </p>
              <p><strong>状态：</strong>
                <Tag color={WO_STATUS_MAP[detail.status]?.color}>
                  {WO_STATUS_MAP[detail.status]?.label || detail.status}
                </Tag>
              </p>
              <p><strong>描述：</strong>{detail.description}</p>
              <p><strong>创建人：</strong>{detail.creatorName || '-'}</p>
              <p><strong>指派人：</strong>{detail.assigneeName || '-'}</p>
              <p><strong>创建时间：</strong>{dayjs(detail.createdAt).format('YYYY-MM-DD HH:mm:ss')}</p>
              {detail.resolution && <p><strong>解决方案：</strong>{detail.resolution}</p>}
            </Card>

            <Card title="状态时间线" size="small" style={{ marginBottom: 16 }}>
              {detail.timeline && detail.timeline.length > 0 ? (
                <Timeline
                  items={detail.timeline.map((t: any) => ({
                    children: (
                      <div>
                        <Tag color={WO_STATUS_MAP[t.status]?.color}>
                          {WO_STATUS_MAP[t.status]?.label || t.status}
                        </Tag>
                        <span style={{ marginLeft: 8 }}>{t.operator}</span>
                        <div style={{ color: '#999', fontSize: 12 }}>
                          {dayjs(t.timestamp).format('YYYY-MM-DD HH:mm:ss')}
                        </div>
                        {t.remark && <div>{t.remark}</div>}
                      </div>
                    ),
                  }))}
                />
              ) : (
                <span style={{ color: '#999' }}>暂无记录</span>
              )}
            </Card>

            <Dropdown
              menu={{
                items: WO_STATUS_OPTIONS.map((s) => ({
                  key: s,
                  label: WO_STATUS_MAP[s]?.label || s,
                })),
                onClick: ({ key }) => handleStatusChange(detail.id, key),
              }}
            >
              <Button>
                更改状态 <DownOutlined />
              </Button>
            </Dropdown>
          </div>
        )}
        {!detail && !detailLoading && <div style={{ textAlign: 'center', color: '#999' }}>加载中...</div>}
      </Drawer>
    </div>
  )
}

export default AlertsPage
