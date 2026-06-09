import React, { useState, useEffect, useCallback, useRef } from 'react'
import {
  Tabs,
  Card,
  Table,
  Button,
  Tag,
  Select,
  Input,
  Space,
  Row,
  Col,
  DatePicker,
  Statistic,
  Modal,
  Form,
  Switch,
  InputNumber,
  message,
  Popconfirm,
  Tooltip,
  Checkbox,
  Divider,
  Spin,
} from 'antd'
import {
  ReloadOutlined,
  ExportOutlined,
  CheckCircleFilled,
  CloseCircleFilled,
  SyncOutlined,
  DashboardOutlined,
  PlusOutlined,
  StopOutlined,
  CheckCircleOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { adminApi, type AuditLog, type SystemHealth, type Tenant } from '@/services/adminApi'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'

const { RangePicker } = DatePicker

const ACTION_COLORS: Record<string, string> = {
  CREATE: '#52c41a',
  UPDATE: '#1677ff',
  DELETE: '#ff4d4f',
  LOGIN: '#13c2c2',
  OTA: '#722ed1',
}

const AdminPage: React.FC = () => {
  const { user } = useAuthStore()
  const [activeTab, setActiveTab] = useState('audit')

  if (user?.role !== Role.SUPER_ADMIN) {
    return (
      <Card>
        <h3>系统管理</h3>
        <p style={{ color: '#999' }}>仅超级管理员可访问此页面</p>
      </Card>
    )
  }

  return (
    <div>
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        items={[
          { key: 'audit', label: '审计日志', children: <AuditLogTab /> },
          { key: 'health', label: '系统健康', children: <HealthTab /> },
          { key: 'tenants', label: '租户管理', children: <TenantTab /> },
          { key: 'settings', label: '系统配置', children: <SettingsTab /> },
          { key: 'quotas', label: '系统配额', children: <QuotaTab /> },
          { key: 'permissions', label: '权限配置', children: <PermissionTab /> },
        ]}
      />
    </div>
  )
}

const AuditLogTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<AuditLog[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [userIdFilter, setUserIdFilter] = useState<string>()
  const [actionFilter, setActionFilter] = useState<string>()
  const [dateRange, setDateRange] = useState<[dayjs.Dayjs, dayjs.Dayjs] | null>(null)
  const [detailModalOpen, setDetailModalOpen] = useState(false)
  const [selectedDetail, setSelectedDetail] = useState<Record<string, unknown> | null>(null)

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await adminApi.getAuditLogs({
        page,
        pageSize,
        userId: userIdFilter || undefined,
        action: actionFilter || undefined,
        startDate: dateRange?.[0]?.format('YYYY-MM-DD'),
        endDate: dateRange?.[1]?.format('YYYY-MM-DD'),
      })
      setData(res.data.data?.items ?? [])
      setTotal(res.data.data?.total ?? 0)
    } catch {
      message.error('获取审计日志失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, userIdFilter, actionFilter, dateRange])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const handleExport = async () => {
    try {
      await adminApi.exportAuditLogs({
        startDate: dateRange?.[0]?.format('YYYY-MM-DD'),
        endDate: dateRange?.[1]?.format('YYYY-MM-DD'),
      })
      message.success('导出成功')
    } catch {
      message.error('导出失败')
    }
  }

  const columns: ColumnsType<AuditLog> = [
    {
      title: '时间',
      dataIndex: 'timestamp',
      key: 'timestamp',
      width: 170,
      render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss'),
    },
    { title: '用户', dataIndex: 'username', key: 'username', width: 120 },
    {
      title: '操作',
      dataIndex: 'action',
      key: 'action',
      width: 100,
      render: (action: string) => (
        <Tag color={ACTION_COLORS[action] || '#d9d9d9'}>{action}</Tag>
      ),
    },
    { title: '资源类型', dataIndex: 'resourceType', key: 'resourceType', width: 100 },
    {
      title: '操作详情',
      dataIndex: 'detail',
      key: 'detail',
      ellipsis: true,
      render: (detail: Record<string, unknown>) => (
        <Button
          type="link"
          size="small"
          onClick={() => {
            setSelectedDetail(detail)
            setDetailModalOpen(true)
          }}
        >
          查看详情
        </Button>
      ),
    },
    { title: 'IP地址', dataIndex: 'ip', key: 'ip', width: 130 },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Input.Search
              allowClear
              placeholder="搜索用户名"
              style={{ width: 200 }}
              value={userIdFilter}
              onChange={(e) => setUserIdFilter(e.target.value)}
              onSearch={() => { setPage(1); fetchData() }}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="操作类型"
              style={{ width: 140 }}
              value={actionFilter}
              onChange={(val) => { setActionFilter(val); setPage(1) }}
              options={Object.entries(ACTION_COLORS).map(([k]) => ({
                label: k,
                value: k,
              }))}
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
          <Col>
            <Button icon={<ExportOutlined />} onClick={handleExport}>导出</Button>
          </Col>
        </Row>
      </Card>

      <Table<AuditLog>
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
        title="操作详情"
        open={detailModalOpen}
        onCancel={() => { setDetailModalOpen(false); setSelectedDetail(null) }}
        footer={null}
        width={500}
      >
        {selectedDetail ? (
          <pre style={{
            background: '#f5f5f5',
            padding: 16,
            borderRadius: 4,
            maxHeight: 400,
            overflow: 'auto',
            fontSize: 13,
          }}>
            {JSON.stringify(selectedDetail, null, 2)}
          </pre>
        ) : null}
      </Modal>
    </div>
  )
}

const HealthTab: React.FC = () => {
  const [health, setHealth] = useState<SystemHealth | null>(null)
  const [loading, setLoading] = useState(false)
  const intervalRef = useRef<ReturnType<typeof setInterval>>()

  const fetchHealth = useCallback(async () => {
    setLoading(true)
    try {
      const res = await adminApi.getSystemHealth()
      setHealth(res.data.data ?? null)
    } catch {
      message.error('获取系统状态失败')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchHealth()
    intervalRef.current = setInterval(fetchHealth, 30000)
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
  }, [fetchHealth])

  function formatUptime(seconds: number): string {
    const d = Math.floor(seconds / 86400)
    const h = Math.floor((seconds % 86400) / 3600)
    const m = Math.floor((seconds % 3600) / 60)
    const parts: string[] = []
    if (d > 0) parts.push(`${d}天`)
    if (h > 0) parts.push(`${h}小时`)
    parts.push(`${m}分钟`)
    return parts.join(' ')
  }

  const statusIcon = (ok: boolean) =>
    ok ? (
      <CheckCircleFilled style={{ color: '#52c41a', fontSize: 18 }} />
    ) : (
      <CloseCircleFilled style={{ color: '#ff4d4f', fontSize: 18 }} />
    )

  return (
    <div>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <Card size="small">
            <Statistic
              title="运行时间"
              value={health ? formatUptime(health.uptime) : '-'}
              loading={loading}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic
              title="内存使用率"
              value={health?.memoryUsage ?? 0}
              suffix="%"
              precision={1}
              loading={loading}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic
              title="CPU使用率"
              value={health?.cpuUsage ?? 0}
              suffix="%"
              precision={1}
              loading={loading}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic
              title="系统版本"
              value={health?.version ?? '-'}
              loading={loading}
            />
          </Card>
        </Col>
      </Row>

      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={8}>
          <Card size="small" title="数据库">
            <Space>
              {health !== null && statusIcon(health.database)}
              <span>{health?.database ? '已连接' : '已断开'}</span>
            </Space>
            {health && (
              <div style={{ color: '#999', fontSize: 12, marginTop: 8 }}>
                上次检测: {dayjs(health.lastCheckAt).format('YYYY-MM-DD HH:mm:ss')}
              </div>
            )}
          </Card>
        </Col>
        <Col span={8}>
          <Card size="small" title="Redis">
            <Space>
              {health !== null && statusIcon(health.redis)}
              <span>{health?.redis ? '已连接' : '已断开'}</span>
            </Space>
            {health && (
              <div style={{ color: '#999', fontSize: 12, marginTop: 8 }}>
                上次检测: {dayjs(health.lastCheckAt).format('YYYY-MM-DD HH:mm:ss')}
              </div>
            )}
          </Card>
        </Col>
        <Col span={8}>
          <Card size="small" title="MQTT Broker">
            <Space>
              {health !== null && statusIcon(health.mqtt)}
              <span>{health?.mqtt ? '已连接' : '已断开'}</span>
            </Space>
            {health && (
              <div style={{ color: '#999', fontSize: 12, marginTop: 8 }}>
                上次检测: {dayjs(health.lastCheckAt).format('YYYY-MM-DD HH:mm:ss')}
              </div>
            )}
          </Card>
        </Col>
      </Row>

      <Button icon={<SyncOutlined spin={loading} />} onClick={fetchHealth}>
        刷新状态
      </Button>
    </div>
  )
}

const SettingsTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form] = Form.useForm()

  const fetchConfig = async () => {
    setLoading(true)
    try {
      const res = await adminApi.getSystemConfig()
      form.setFieldsValue(res.data?.data ?? {})
    } catch {
      message.error('获取系统配置失败')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchConfig()
  }, [])

  const handleSave = async () => {
    try {
      const values = await form.validateFields()
      setSaving(true)
      await adminApi.updateSystemConfig(values)
      message.success('配置保存成功')
    } catch {
      message.error('保存失败')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card title="系统配置" loading={loading} extra={
      <Tooltip title="前往 Grafana 监控大盘">
        <Button icon={<DashboardOutlined />} href="/grafana" target="_blank">
          Grafana
        </Button>
      </Tooltip>
    }>
      <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
        <Form.Item name="siteName" label="站点名称">
          <Input placeholder="请输入站点名称" />
        </Form.Item>
        <Form.Item name="mqttBrokerUrl" label="MQTT Broker地址">
          <Input placeholder="mqtt://localhost:1883" />
        </Form.Item>
        <Form.Item name="dataRetentionDays" label="数据保留天数">
          <InputNumber min={1} max={365} style={{ width: '100%' }} placeholder="30" />
        </Form.Item>
        <Form.Item name="enableAutoUpgrade" label="自动升级" valuePropName="checked">
          <Switch />
        </Form.Item>
        <Form.Item name="alertRetentionDays" label="告警保留天数">
          <InputNumber min={1} max={365} style={{ width: '100%' }} placeholder="90" />
        </Form.Item>
        <Form.Item name="maxLoginAttempts" label="最大登录尝试次数">
          <InputNumber min={1} max={10} style={{ width: '100%' }} placeholder="5" />
        </Form.Item>
        <Form.Item>
          <Button type="primary" onClick={handleSave} loading={saving}>
            保存配置
          </Button>
        </Form.Item>
      </Form>
    </Card>
  )
}

const TenantTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<Tenant[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [createModalOpen, setCreateModalOpen] = useState(false)
  const [editModalOpen, setEditModalOpen] = useState(false)
  const [editingTenant, setEditingTenant] = useState<Tenant | null>(null)
  const [createForm] = Form.useForm()
  const [editForm] = Form.useForm()
  const [creating, setCreating] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await adminApi.getTenants({ page, pageSize })
      setData(res.data?.data?.items ?? [])
      setTotal(res.data?.data?.total ?? 0)
    } catch {
      message.error('获取租户列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const handleCreate = async () => {
    try {
      const values = await createForm.validateFields()
      setCreating(true)
      await adminApi.createTenant(values)
      message.success('租户创建成功')
      setCreateModalOpen(false)
      createForm.resetFields()
      fetchData()
    } catch (err: any) {
      if (err?.response?.data?.message) {
        message.error(err.response.data.message)
      } else if (err?.errorFields) {
        return
      } else {
        message.error('创建失败')
      }
    } finally {
      setCreating(false)
    }
  }

  const handleEdit = (record: Tenant) => {
    setEditingTenant(record)
    editForm.setFieldsValue({
      deviceLimit: record.deviceLimit,
      userLimit: record.userLimit,
    })
    setEditModalOpen(true)
  }

  const handleSaveEdit = async () => {
    if (!editingTenant) return
    try {
      const values = await editForm.validateFields()
      setSaving(true)
      await adminApi.updateTenant(editingTenant.id, values)
      message.success('配额更新成功')
      setEditModalOpen(false)
      setEditingTenant(null)
      fetchData()
    } catch (err: any) {
      if (err?.errorFields) return
      message.error('更新失败')
    } finally {
      setSaving(false)
    }
  }

  const handleToggle = async (record: Tenant) => {
    try {
      await adminApi.toggleTenant(record.id)
      message.success(record.status === 1 ? '租户已禁用' : '租户已启用')
      fetchData()
    } catch {
      message.error('操作失败')
    }
  }

  const columns: ColumnsType<Tenant> = [
    { title: 'ID', dataIndex: 'id', key: 'id', width: 60 },
    { title: '名称', dataIndex: 'nickname', key: 'nickname', width: 150 },
    { title: '手机号', dataIndex: 'phone', key: 'phone', width: 140 },
    { title: '邮箱', dataIndex: 'email', key: 'email', width: 180, ellipsis: true },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 80,
      render: (status: number) =>
        status === 1 ? (
          <Tag color="green">启用</Tag>
        ) : (
          <Tag color="red">禁用</Tag>
        ),
    },
    {
      title: '子用户',
      dataIndex: 'subUserCount',
      key: 'subUserCount',
      width: 80,
      render: (count: number, record: Tenant) => (
        <span>
          {count}
          {record.userLimit ? ` / ${record.userLimit}` : ''}
        </span>
      ),
    },
    {
      title: '设备',
      dataIndex: 'deviceCount',
      key: 'deviceCount',
      width: 80,
      render: (count: number, record: Tenant) => (
        <span>
          {count}
          {record.deviceLimit ? ` / ${record.deviceLimit}` : ''}
        </span>
      ),
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
      key: 'actions',
      width: 180,
      render: (_: unknown, record: Tenant) => (
        <Space>
          <Button size="small" onClick={() => handleEdit(record)}>
            配额
          </Button>
          <Popconfirm
            title={record.status === 1 ? '确定要禁用此租户吗？' : '确定要启用此租户吗？'}
            onConfirm={() => handleToggle(record)}
          >
            <Button
              size="small"
              danger={record.status === 1}
              icon={record.status === 1 ? <StopOutlined /> : <CheckCircleOutlined />}
            >
              {record.status === 1 ? '禁用' : '启用'}
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Row justify="space-between" align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateModalOpen(true)}>
              创建租户
            </Button>
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={fetchData}>
              刷新
            </Button>
          </Col>
        </Row>
      </Card>

      <Table<Tenant>
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
          onChange: (p, ps) => {
            setPage(p)
            setPageSize(ps)
          },
        }}
      />

      <Modal
        title="创建租户"
        open={createModalOpen}
        onOk={handleCreate}
        onCancel={() => {
          setCreateModalOpen(false)
          createForm.resetFields()
        }}
        confirmLoading={creating}
        destroyOnClose
      >
        <Form form={createForm} layout="vertical" preserve={false}>
          <Form.Item name="phone" label="手机号" rules={[{ required: true, message: '请输入手机号' }]}>
            <Input placeholder="请输入手机号" />
          </Form.Item>
          <Form.Item name="nickname" label="租户名称">
            <Input placeholder="请输入租户名称" />
          </Form.Item>
          <Form.Item name="email" label="邮箱">
            <Input placeholder="请输入邮箱" />
          </Form.Item>
          <Form.Item name="password" label="密码" rules={[{ required: true, message: '请输入密码' }]}>
            <Input.Password placeholder="请输入密码" />
          </Form.Item>
          <Form.Item name="deviceLimit" label="设备配额" initialValue={100}>
            <InputNumber min={0} style={{ width: '100%' }} placeholder="100" />
          </Form.Item>
          <Form.Item name="userLimit" label="子用户配额" initialValue={50}>
            <InputNumber min={0} style={{ width: '100%' }} placeholder="50" />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title="编辑租户配额"
        open={editModalOpen}
        onOk={handleSaveEdit}
        onCancel={() => {
          setEditModalOpen(false)
          setEditingTenant(null)
        }}
        confirmLoading={saving}
        destroyOnClose
      >
        {editingTenant && (
          <div style={{ marginBottom: 16 }}>
            <strong>租户：</strong>{editingTenant.nickname} ({editingTenant.phone})
          </div>
        )}
        <Form form={editForm} layout="vertical" preserve={false}>
          <Form.Item name="deviceLimit" label="设备配额">
            <InputNumber min={0} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item name="userLimit" label="子用户配额">
            <InputNumber min={0} style={{ width: '100%' }} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

const QuotaTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form] = Form.useForm()

  const fetchQuotas = async () => {
    setLoading(true)
    try {
      const res = await adminApi.getSystemConfig()
      const data = res.data?.data ?? {}
      form.setFieldsValue({
        maxDevicesPerTenant: data.maxDevicesPerTenant ?? 500,
        maxUsersPerTenant: data.maxUsersPerTenant ?? 200,
        maxAlertsPerDay: data.maxAlertsPerDay ?? 1000,
        maxOtaTasksPerMonth: data.maxOtaTasksPerMonth ?? 50,
      })
    } catch {
      message.error('获取配额配置失败')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchQuotas()
  }, [])

  const handleSave = async () => {
    try {
      const values = await form.validateFields()
      setSaving(true)
      await adminApi.updateSystemConfig(values)
      message.success('配额保存成功')
    } catch {
      message.error('保存失败')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card title="系统配额" loading={loading}>
      <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
        <Form.Item name="maxDevicesPerTenant" label="每租户最大设备数">
          <InputNumber min={1} max={10000} style={{ width: '100%' }} />
        </Form.Item>
        <Form.Item name="maxUsersPerTenant" label="每租户最大用户数">
          <InputNumber min={1} max={1000} style={{ width: '100%' }} />
        </Form.Item>
        <Form.Item name="maxAlertsPerDay" label="每日最大告警数">
          <InputNumber min={1} max={100000} style={{ width: '100%' }} />
        </Form.Item>
        <Form.Item name="maxOtaTasksPerMonth" label="每月最大OTA任务数">
          <InputNumber min={1} max={5000} style={{ width: '100%' }} />
        </Form.Item>
        <Form.Item>
          <Button type="primary" onClick={handleSave} loading={saving}>
            保存配额
          </Button>
        </Form.Item>
      </Form>
    </Card>
  )
}

const RESOURCE_LABELS: Record<string, string> = {
  devices: '设备管理',
  users: '用户管理',
  alerts: '告警管理',
  alert_rules: '告警规则',
  work_orders: '工单管理',
  firmware: '固件管理',
  ota: 'OTA升级',
  dashboard: '仪表盘',
  stations: '电站管理',
  parallel: '并机管理',
  audit: '审计日志',
  admin: '系统管理',
}

const RESOURCE_ORDER = [
  'devices',
  'users',
  'alerts',
  'alert_rules',
  'work_orders',
  'firmware',
  'ota',
  'dashboard',
  'stations',
  'parallel',
  'audit',
  'admin',
]

const ALL_PERMISSION_DEFS = [
  { resource: 'devices', action: 'view', label: '查看设备列表' },
  { resource: 'devices', action: 'create', label: '创建设备/导入Excel' },
  { resource: 'devices', action: 'edit', label: '编辑设备信息' },
  { resource: 'devices', action: 'delete', label: '删除设备' },
  { resource: 'devices', action: 'export', label: '导出设备数据' },
  { resource: 'devices', action: 'control', label: '远程控制设备' },
  { resource: 'devices', action: 'manage', label: '解绑/审批/生命周期管理' },
  { resource: 'users', action: 'view', label: '查看用户列表' },
  { resource: 'users', action: 'create', label: '创建下级用户' },
  { resource: 'users', action: 'edit', label: '编辑用户信息' },
  { resource: 'users', action: 'delete', label: '删除/禁用用户' },
  { resource: 'users', action: 'manage', label: '重置密码/角色变更' },
  { resource: 'alerts', action: 'view', label: '查看告警列表' },
  { resource: 'alerts', action: 'manage', label: '确认/忽略告警' },
  { resource: 'alert_rules', action: 'view', label: '查看告警规则' },
  { resource: 'alert_rules', action: 'create', label: '创建告警规则' },
  { resource: 'alert_rules', action: 'edit', label: '编辑告警规则' },
  { resource: 'alert_rules', action: 'delete', label: '删除告警规则' },
  { resource: 'work_orders', action: 'view', label: '查看工单列表' },
  { resource: 'work_orders', action: 'create', label: '创建工单' },
  { resource: 'work_orders', action: 'edit', label: '编辑/指派工单' },
  { resource: 'work_orders', action: 'manage', label: 'SLA管理/升级工单' },
  { resource: 'firmware', action: 'view', label: '查看固件列表' },
  { resource: 'firmware', action: 'create', label: '上传固件' },
  { resource: 'firmware', action: 'delete', label: '删除固件' },
  { resource: 'ota', action: 'view', label: '查看OTA任务' },
  { resource: 'ota', action: 'create', label: '创建OTA任务' },
  { resource: 'ota', action: 'control', label: '执行/取消/回滚OTA任务' },
  { resource: 'dashboard', action: 'view', label: '查看仪表盘' },
  { resource: 'dashboard', action: 'export', label: '多设备对比/导出' },
  { resource: 'stations', action: 'view', label: '查看电站列表' },
  { resource: 'stations', action: 'create', label: '创建电站' },
  { resource: 'stations', action: 'edit', label: '编辑电站' },
  { resource: 'parallel', action: 'view', label: '查看并机配置' },
  { resource: 'parallel', action: 'create', label: '创建并机配置' },
  { resource: 'parallel', action: 'control', label: '同步参数/管理并机' },
  { resource: 'audit', action: 'view', label: '查看审计日志' },
  { resource: 'admin', action: 'view', label: '查看系统健康' },
  { resource: 'admin', action: 'manage', label: '租户管理/系统配置' },
]

const ROLE_TABS = [
  { key: '0', label: '超级管理员' },
  { key: '1', label: '代理商' },
  { key: '2', label: '安装商' },
  { key: '3', label: '终端用户' },
]

const PermissionTab: React.FC = () => {
  const [selectedRole, setSelectedRole] = useState<string>('1')
  const [permissions, setPermissions] = useState<Record<string, Set<string>>>({})
  const [originalPermissions, setOriginalPermissions] = useState<Record<string, Set<string>>>({})
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchPermissions = async (role: string) => {
    setLoading(true)
    try {
      const res = await adminApi.getRolePermissions(Number(role))
      const items = (res.data?.data ?? res.data ?? []) as { resource: string; action: string; is_allowed: boolean }[]
      const permSet: Record<string, Set<string>> = {}
      for (const item of items) {
        if (!permSet[item.resource]) permSet[item.resource] = new Set()
        if (item.is_allowed) permSet[item.resource].add(item.action)
      }
      setPermissions(permSet)
      setOriginalPermissions(structuredClone(permSet))
    } catch {
      message.error('获取权限配置失败')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchPermissions(selectedRole)
  }, [selectedRole])

  const handleToggle = (resource: string, action: string, checked: boolean) => {
    setPermissions((prev) => {
      const next = { ...prev }
      if (!next[resource]) next[resource] = new Set()
      else next[resource] = new Set(next[resource])
      if (checked) {
        next[resource].add(action)
      } else {
        next[resource].delete(action)
      }
      return next
    })
  }

  const hasChanged = () => {
    for (const res of RESOURCE_ORDER) {
      const curr = permissions[res] ?? new Set()
      const orig = originalPermissions[res] ?? new Set()
      if (curr.size !== orig.size) return true
      for (const a of curr) {
        if (!orig.has(a)) return true
      }
    }
    return false
  }

  const handleSave = async () => {
    const permList: { resource: string; action: string; is_allowed: boolean }[] = []
    for (const def of ALL_PERMISSION_DEFS) {
      const allowed = permissions[def.resource]?.has(def.action) ?? false
      permList.push({ resource: def.resource, action: def.action, is_allowed: allowed })
    }
    setSaving(true)
    try {
      await adminApi.updateRolePermissions(Number(selectedRole), { permissions: permList })
      message.success('权限配置保存成功')
      setOriginalPermissions(structuredClone(permissions))
    } catch {
      message.error('保存失败')
    } finally {
      setSaving(false)
    }
  }

  const isSuperAdmin = selectedRole === '0'

  const groupedByResource = () => {
    const map: Record<string, typeof ALL_PERMISSION_DEFS> = {}
    for (const def of ALL_PERMISSION_DEFS) {
      if (!map[def.resource]) map[def.resource] = []
      map[def.resource].push(def)
    }
    return RESOURCE_ORDER.filter((r) => map[r]).map((r) => ({
      resource: r,
      label: RESOURCE_LABELS[r] ?? r,
      actions: map[r],
    }))
  }

  return (
    <div>
      <Card size="small" style={{ marginBottom: 16 }}>
        <Row justify="space-between" align="middle">
          <Col>
            <Space>
              <span style={{ fontWeight: 500 }}>选择角色：</span>
              <Select
                value={selectedRole}
                onChange={(val) => {
                  if (hasChanged()) {
                    Modal.confirm({
                      title: '未保存的更改',
                      content: '当前有未保存的更改，切换角色将丢失更改，确定继续吗？',
                      onOk: () => setSelectedRole(val),
                    })
                  } else {
                    setSelectedRole(val)
                  }
                }}
                style={{ width: 160 }}
                options={ROLE_TABS.map((t) => ({ label: t.label, value: t.key }))}
              />
            </Space>
          </Col>
          <Col>
            <Button
              type="primary"
              onClick={handleSave}
              loading={saving}
              disabled={!hasChanged()}
            >
              保存
            </Button>
          </Col>
        </Row>
      </Card>

      {isSuperAdmin ? (
        <Card>
          <div style={{ textAlign: 'center', padding: 24, color: '#999', fontSize: 16 }}>
            超级管理员默认拥有所有权限，无需配置。
          </div>
        </Card>
      ) : (
        <Spin spinning={loading}>
          <Row gutter={[16, 16]}>
            {groupedByResource().map((group) => {
              const allowedSet = permissions[group.resource] ?? new Set()
              return (
                <Col xs={24} sm={12} lg={8} xl={6} key={group.resource}>
                  <Card
                    title={
                      <span style={{ fontWeight: 600, fontSize: 14 }}>
                        {group.label}
                      </span>
                    }
                    size="small"
                    bodyStyle={{ padding: '12px 16px' }}
                  >
                    {group.actions.map((perm) => (
                      <div key={perm.action} style={{ marginBottom: 8 }}>
                        <Checkbox
                          checked={allowedSet.has(perm.action)}
                          onChange={(e) =>
                            handleToggle(group.resource, perm.action, e.target.checked)
                          }
                        >
                          {perm.label}
                        </Checkbox>
                      </div>
                    ))}
                  </Card>
                </Col>
              )
            })}
          </Row>
        </Spin>
      )}
    </div>
  )
}

export default AdminPage
