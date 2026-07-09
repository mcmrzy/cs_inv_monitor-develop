import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Tabs, Card, Table, Button, Tag, Select, Input, Space, Row, Col,
  Statistic, Modal, Form, Switch, InputNumber, Popconfirm, Tooltip,
  Checkbox, Spin, Typography, App, Empty,
} from 'antd'
import {
  ReloadOutlined, CheckCircleFilled, CloseCircleFilled, SyncOutlined,
  DashboardOutlined, PlusOutlined, StopOutlined, CheckCircleOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { adminApi, type SystemHealth, type Tenant } from '@/services/adminApi'
import useAuthStore from '@/stores/authStore'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import useTranslation from '@/hooks/useTranslation'
import { Role } from '@/types'
import { queryKeys } from '@/utils/queryKeys'

const { Title, Text } = Typography

function formatUptime(seconds: number, t: (key: string) => string): string {
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const parts: string[] = []
  if (d > 0) parts.push(`${d}${t('admin.days')}`)
  if (h > 0) parts.push(`${h}${t('admin.hours')}`)
  parts.push(`${m}${t('admin.minutes')}`)
  return parts.join(' ')
}

const statusIcon = (ok: boolean) => ok
  ? <CheckCircleFilled style={{ color: '#52c41a', fontSize: 18 }} />
  : <CloseCircleFilled style={{ color: '#ff4d4f', fontSize: 18 }} />

const AdminPage: React.FC = () => {
  const { t } = useTranslation()
  const { user } = useAuthStore()
  const [activeTab, setActiveTab] = useState('health')

  if (user?.role !== Role.SUPER_ADMIN) {
    return (
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <Title level={4}>{t('admin.title')}</Title>
        <Text type="secondary">{t('admin.onlySuperAdmin')}</Text>
      </Card>
    )
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>{t('admin.title')}</Title>
      <Tabs activeKey={activeTab} onChange={setActiveTab} items={[
        { key: 'health', label: t('admin.systemHealth'), children: <HealthTab /> },
        { key: 'tenants', label: t('admin.tenantManage'), children: <TenantTab /> },
        { key: 'settings', label: t('admin.systemConfig'), children: <SettingsTab /> },
        { key: 'quotas', label: t('admin.systemQuota'), children: <QuotaTab /> },
        { key: 'permissions', label: t('admin.permissionConfig'), children: <PermissionTab /> },
        { key: 'api-overview', label: t('admin.apiOverview'), children: <APIOverviewTab onNavigateToPermissions={() => setActiveTab('permissions')} /> },
      ]} />
    </div>
  )
}

const HealthTab: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const { data: health, isLoading, refetch } = useQuery({
    queryKey: queryKeys.admin.health(),
    queryFn: () => adminApi.getSystemHealth().then((r) => r.data?.data ?? null as SystemHealth | null),
    refetchInterval: 30000,
  })

  return (
    <div>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('admin.uptime')} value={health ? formatUptime(health.uptime, t) : '-'} loading={isLoading} /></Card></Col>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('admin.memoryUsage')} value={health?.memoryUsage ?? 0} suffix="%" precision={1} loading={isLoading} /></Card></Col>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('admin.cpuUsage')} value={health?.cpuUsage ?? 0} suffix="%" precision={1} loading={isLoading} /></Card></Col>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('admin.systemVersion')} value={health?.version ?? '-'} loading={isLoading} /></Card></Col>
      </Row>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        {[
          { label: t('admin.database'), ok: health?.database },
          { label: 'Redis', ok: health?.redis },
          { label: 'MQTT Broker', ok: health?.mqtt },
        ].map((svc) => (
          <Col span={8} key={svc.label}>
            <Card size="small" title={svc.label} bordered={false} style={{ borderRadius: 12 }}>
              <Space>{health !== null && statusIcon(!!svc.ok)}<span>{svc.ok ? t('admin.connected') : t('admin.disconnected')}</span></Space>
              {health && <div style={{ color: '#999', fontSize: 12, marginTop: 8 }}>{t('admin.lastCheck')}: {formatInTimezone(health.lastCheckAt, timezone, 'YYYY-MM-DD HH:mm:ss')}</div>}
            </Card>
          </Col>
        ))}
      </Row>
      <Button icon={<SyncOutlined spin={isLoading} />} onClick={() => refetch()}>{t('admin.refreshStatus')}</Button>
    </div>
  )
}

const SettingsTab: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const [form] = Form.useForm()

  const { isLoading } = useQuery({
    queryKey: queryKeys.admin.config(),
    queryFn: () => adminApi.getSystemConfig().then((r) => {
      form.setFieldsValue(r.data?.data ?? {})
      return r.data?.data ?? {}
    }),
  })

  const saveMutation = useMutation({
    mutationFn: (values: any) => adminApi.updateSystemConfig(values),
    onSuccess: () => { message.success(t('admin.configSaveSuccess')) },
    onError: () => { message.error(t('admin.configSaveFailed')) },
  })

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <Card title={t('admin.basicSettings')} bordered={false} style={{ borderRadius: 12 }} loading={isLoading}>
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Form.Item name="site_name" label={t('admin.siteName')}><Input placeholder="CSERGY 光伏监控平台" /></Form.Item>
        </Form>
      </Card>

      <Card title={t('admin.emailSettings')} bordered={false} style={{ borderRadius: 12 }} loading={isLoading}>
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Row gutter={16}>
            <Col span={16}><Form.Item name="email_host" label={t('admin.smtpServer')}><Input placeholder="smtp.qq.com" /></Form.Item></Col>
            <Col span={8}><Form.Item name="email_port" label={t('admin.smtpPort')}><InputNumber placeholder="465" style={{ width: '100%' }} /></Form.Item></Col>
          </Row>
          <Row gutter={16}>
            <Col span={12}><Form.Item name="email_username" label={t('admin.emailUsername')}><Input placeholder="your@email.com" /></Form.Item></Col>
            <Col span={12}><Form.Item name="email_password" label={t('admin.emailPassword')}><Input.Password placeholder={t('admin.emailPasswordPlaceholder')} /></Form.Item></Col>
          </Row>
          <Form.Item name="email_from" label={t('admin.emailFrom')}><Input placeholder="your@email.com" /></Form.Item>
          <Form.Item name="email_use_ssl" label={t('admin.enableSSL')} valuePropName="checked"><Switch /></Form.Item>
        </Form>
      </Card>

      <Card title={t('admin.mqttSettings')} bordered={false} style={{ borderRadius: 12 }} loading={isLoading}>
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Row gutter={16}>
            <Col span={16}><Form.Item name="mqtt_broker" label={t('admin.mqttBroker')}><Input placeholder="jiuxiaoyw.online" /></Form.Item></Col>
            <Col span={8}><Form.Item name="mqtt_port" label={t('admin.mqttPort')}><Input placeholder="8883" /></Form.Item></Col>
          </Row>
          <Row gutter={16}>
            <Col span={12}><Form.Item name="mqtt_username" label={t('admin.mqttUsername')}><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="mqtt_password" label={t('admin.mqttPassword')}><Input.Password /></Form.Item></Col>
          </Row>
          <Form.Item name="mqtt_tls_insecure" label={t('admin.mqttTLSInsecure')} valuePropName="checked"><Switch /></Form.Item>
        </Form>
      </Card>

      <Card title={t('admin.smsSettings')} bordered={false} style={{ borderRadius: 12 }} loading={isLoading}>
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Row gutter={16}>
            <Col span={12}><Form.Item name="sms_access_key" label="Access Key"><Input.Password /></Form.Item></Col>
            <Col span={12}><Form.Item name="sms_secret_key" label="Secret Key"><Input.Password /></Form.Item></Col>
          </Row>
          <Row gutter={16}>
            <Col span={12}><Form.Item name="sms_sign_name" label={t('admin.smsSignName')}><Input /></Form.Item></Col>
            <Col span={12}><Form.Item name="sms_template" label={t('admin.smsTemplate')}><Input /></Form.Item></Col>
          </Row>
        </Form>
      </Card>

      <Card title={t('admin.dataSettings')} bordered={false} style={{ borderRadius: 12 }} loading={isLoading}>
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Row gutter={16}>
            <Col span={8}><Form.Item name="data_retention_days" label={t('admin.dataRetention')}><InputNumber min={1} max={365} style={{ width: '100%' }} placeholder="30" /></Form.Item></Col>
            <Col span={8}><Form.Item name="alert_retention_days" label={t('admin.alertRetention')}><InputNumber min={1} max={365} style={{ width: '100%' }} placeholder="90" /></Form.Item></Col>
            <Col span={8}><Form.Item name="max_login_attempts" label={t('admin.maxLoginAttempts')}><InputNumber min={1} max={10} style={{ width: '100%' }} placeholder="5" /></Form.Item></Col>
          </Row>
          <Form.Item name="enable_auto_upgrade" label={t('admin.autoUpgrade')} valuePropName="checked"><Switch /></Form.Item>
        </Form>
      </Card>

      <Button type="primary" size="large" onClick={async () => {
        try {
          const v = await form.validateFields()
          saveMutation.mutate(v)
        } catch {}
      }} loading={saveMutation.isPending}>{t('admin.saveConfig')}</Button>
    </div>
  )
}

const TenantTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [createOpen, setCreateOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [editingTenant, setEditingTenant] = useState<Tenant | null>(null)
  const [createForm] = Form.useForm()
  const [editForm] = Form.useForm()

  const { data: listRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.admin.tenants({ page, pageSize }),
    queryFn: () => adminApi.getTenants({ page, pageSize }).then((r) => ({
      items: r.data?.data?.items ?? [] as Tenant[],
      total: r.data?.data?.total ?? 0,
    })),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.admin.tenants() })

  const createMutation = useMutation({
    mutationFn: (values: any) => adminApi.createTenant(values),
    onSuccess: () => { message.success(t('admin.tenantCreateSuccess')); setCreateOpen(false); createForm.resetFields(); invalidate() },
    onError: (err: any) => { message.error(err?.response?.data?.message || t('admin.tenantCreateFailed')) },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, values }: { id: number; values: any }) => adminApi.updateTenant(id, values),
    onSuccess: () => { message.success(t('admin.quotaUpdateSuccess')); setEditOpen(false); setEditingTenant(null); invalidate() },
    onError: () => { message.error(t('admin.quotaUpdateFailed')) },
  })

  const toggleMutation = useMutation({
    mutationFn: (id: number) => adminApi.toggleTenant(id),
    onSuccess: (_, id) => { message.success(t('admin.operationSuccess')); invalidate() },
    onError: () => { message.error(t('admin.operationFailed')) },
  })

  const columns: ColumnsType<Tenant> = [
    { title: 'ID', dataIndex: 'id', key: 'id', width: 60 },
    { title: t('admin.tenantName'), dataIndex: 'nickname', key: 'nickname', width: 150 },
    { title: t('admin.tenantPhone'), dataIndex: 'phone', key: 'phone', width: 140 },
    { title: t('admin.tenantEmail'), dataIndex: 'email', key: 'email', width: 180, ellipsis: true },
    { title: t('admin.tenantStatus'), dataIndex: 'status', key: 'status', width: 80, render: (s: number) => s === 1 ? <Tag color="green">{t('common.enabled')}</Tag> : <Tag color="red">{t('common.disabled')}</Tag> },
    { title: t('admin.subUsers'), dataIndex: 'subUserCount', key: 'subUserCount', width: 80, render: (c: number, r: Tenant) => <span>{c}{r.userLimit ? ` / ${r.userLimit}` : ''}</span> },
    { title: t('admin.tenantDevices'), dataIndex: 'deviceCount', key: 'deviceCount', width: 80, render: (c: number, r: Tenant) => <span>{c}{r.deviceLimit ? ` / ${r.deviceLimit}` : ''}</span> },
    { title: t('common.createdAt'), dataIndex: 'createdAt', key: 'createdAt', width: 170, render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') },
    {
      title: t('common.actions'), key: 'actions', width: 180,
      render: (_: unknown, record: Tenant) => (
        <Space>
          <Button size="small" onClick={() => { setEditingTenant(record); editForm.setFieldsValue({ deviceLimit: record.deviceLimit, userLimit: record.userLimit }); setEditOpen(true) }}>{t('admin.quota')}</Button>
          <Popconfirm title={record.status === 1 ? '确定要禁用此租户吗？' : '确定要启用此租户吗？'} onConfirm={() => toggleMutation.mutate(record.id)}>
            <Button size="small" danger={record.status === 1} icon={record.status === 1 ? <StopOutlined /> : <CheckCircleOutlined />}>{record.status === 1 ? t('common.disabled') : t('common.enabled')}</Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row justify="space-between" align="middle">
          <Col><Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateOpen(true)}>{t('admin.createTenant')}</Button></Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
        </Row>
      </Card>

      <Table<Tenant> rowKey="id" columns={columns} dataSource={listRes?.items ?? []} loading={isLoading} size="small"
        locale={{ emptyText: <Empty description={t('common.noData')} /> }}
        pagination={{ current: page, pageSize, total: listRes?.total ?? 0, showSizeChanger: true, showTotal: (tt) => t('common.total', { total: tt }), onChange: (p, ps) => { setPage(p); setPageSize(ps) } }} />

      <Modal title={t('admin.createTenant')} open={createOpen} onOk={async () => { try { createMutation.mutate(await createForm.validateFields()) } catch {} }}
        onCancel={() => { setCreateOpen(false); createForm.resetFields() }} confirmLoading={createMutation.isPending} destroyOnClose>
        <Form form={createForm} layout="vertical" preserve={false}>
          <Form.Item name="phone" label={t('admin.tenantPhone')} rules={[{ required: true, message: '请输入手机号' }]}><Input placeholder="请输入手机号" /></Form.Item>
          <Form.Item name="nickname" label={t('admin.tenantName')}><Input placeholder="请输入租户名称" /></Form.Item>
          <Form.Item name="email" label={t('admin.tenantEmail')}><Input placeholder="请输入邮箱" /></Form.Item>
          <Form.Item name="password" label="密码" rules={[{ required: true, message: '请输入密码' }]}><Input.Password placeholder="请输入密码" /></Form.Item>
          <Form.Item name="deviceLimit" label={t('admin.deviceQuota')} initialValue={100}><InputNumber min={0} style={{ width: '100%' }} placeholder="100" /></Form.Item>
          <Form.Item name="userLimit" label={t('admin.userQuota')} initialValue={50}><InputNumber min={0} style={{ width: '100%' }} placeholder="50" /></Form.Item>
        </Form>
      </Modal>

      <Modal title={t('admin.editTenantQuota')} open={editOpen} onOk={async () => { try { updateMutation.mutate({ id: editingTenant!.id, values: await editForm.validateFields() }) } catch {} }}
        onCancel={() => { setEditOpen(false); setEditingTenant(null) }} confirmLoading={updateMutation.isPending} destroyOnClose>
        {editingTenant && <div style={{ marginBottom: 16 }}><strong>租户：</strong>{editingTenant.nickname} ({editingTenant.phone})</div>}
        <Form form={editForm} layout="vertical" preserve={false}>
          <Form.Item name="deviceLimit" label={t('admin.deviceQuota')}><InputNumber min={0} style={{ width: '100%' }} /></Form.Item>
          <Form.Item name="userLimit" label={t('admin.userQuota')}><InputNumber min={0} style={{ width: '100%' }} /></Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

const QuotaTab: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const [form] = Form.useForm()

  const { isLoading } = useQuery({
    queryKey: ['admin', 'quotas'],
    queryFn: () => adminApi.getSystemConfig().then((r) => {
      const d = r.data?.data ?? {}
      form.setFieldsValue({
        maxDevicesPerTenant: d.maxDevicesPerTenant ?? 500,
        maxUsersPerTenant: d.maxUsersPerTenant ?? 200,
        maxAlertsPerDay: d.maxAlertsPerDay ?? 1000,
        maxOtaTasksPerMonth: d.maxOtaTasksPerMonth ?? 50,
      })
      return d
    }),
  })

  const saveMutation = useMutation({
    mutationFn: (values: any) => adminApi.updateSystemConfig(values),
    onSuccess: () => { message.success(t('admin.quotaSaveSuccess')) },
    onError: () => { message.error(t('admin.quotaSaveFailed')) },
  })

  return (
    <Card title={t('admin.systemQuota')} bordered={false} style={{ borderRadius: 12 }} loading={isLoading}>
      <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
        <Form.Item name="maxDevicesPerTenant" label="每租户最大设备数"><InputNumber min={1} max={10000} style={{ width: '100%' }} /></Form.Item>
        <Form.Item name="maxUsersPerTenant" label="每租户最大用户数"><InputNumber min={1} max={1000} style={{ width: '100%' }} /></Form.Item>
        <Form.Item name="maxAlertsPerDay" label="每日最大告警数"><InputNumber min={1} max={100000} style={{ width: '100%' }} /></Form.Item>
        <Form.Item name="maxOtaTasksPerMonth" label="每月最大OTA任务数"><InputNumber min={1} max={5000} style={{ width: '100%' }} /></Form.Item>
        <Form.Item><Button type="primary" onClick={async () => { try { saveMutation.mutate(await form.validateFields()) } catch {} }} loading={saveMutation.isPending}>{t('common.save')}</Button></Form.Item>
      </Form>
    </Card>
  )
}

const RESOURCE_LABELS: Record<string, string> = {
  devices: 'admin.deviceManagement', users: 'admin.userManagement', alerts: 'admin.alertManagement', alert_rules: 'admin.alertRule',
  work_orders: 'admin.workOrderManagement', firmware: 'admin.firmwareManagement', ota: 'admin.otaUpgrade', dashboard: 'admin.dashboardPerm',
  stations: 'admin.stationManagement', parallel: 'admin.parallelManagement', audit: 'admin.auditLog', admin: 'admin.systemManagement',
}
const RESOURCE_ORDER = ['devices', 'users', 'alerts', 'alert_rules', 'work_orders', 'firmware', 'ota', 'dashboard', 'stations', 'parallel', 'audit', 'admin']
const ALL_PERMISSION_DEFS = [
  { resource: 'devices', action: 'view', label: 'admin.perm.devices.view' }, { resource: 'devices', action: 'create', label: 'admin.perm.devices.create' },
  { resource: 'devices', action: 'edit', label: 'admin.perm.devices.edit' }, { resource: 'devices', action: 'delete', label: 'admin.perm.devices.delete' },
  { resource: 'devices', action: 'export', label: 'admin.perm.devices.export' }, { resource: 'devices', action: 'control', label: 'admin.perm.devices.control' },
  { resource: 'devices', action: 'manage', label: 'admin.perm.devices.manage' },
  { resource: 'users', action: 'view', label: 'admin.perm.users.view' }, { resource: 'users', action: 'create', label: 'admin.perm.users.create' },
  { resource: 'users', action: 'edit', label: 'admin.perm.users.edit' }, { resource: 'users', action: 'delete', label: 'admin.perm.users.delete' },
  { resource: 'users', action: 'manage', label: 'admin.perm.users.manage' },
  { resource: 'alerts', action: 'view', label: 'admin.perm.alerts.view' }, { resource: 'alerts', action: 'manage', label: 'admin.perm.alerts.manage' },
  { resource: 'alert_rules', action: 'view', label: 'admin.perm.alertRules.view' }, { resource: 'alert_rules', action: 'create', label: 'admin.perm.alertRules.create' },
  { resource: 'alert_rules', action: 'edit', label: 'admin.perm.alertRules.edit' }, { resource: 'alert_rules', action: 'delete', label: 'admin.perm.alertRules.delete' },
  { resource: 'work_orders', action: 'view', label: 'admin.perm.workOrders.view' }, { resource: 'work_orders', action: 'create', label: 'admin.perm.workOrders.create' },
  { resource: 'work_orders', action: 'edit', label: 'admin.perm.workOrders.edit' }, { resource: 'work_orders', action: 'manage', label: 'admin.perm.workOrders.manage' },
  { resource: 'firmware', action: 'view', label: 'admin.perm.firmware.view' }, { resource: 'firmware', action: 'create', label: 'admin.perm.firmware.create' },
  { resource: 'firmware', action: 'delete', label: 'admin.perm.firmware.delete' },
  { resource: 'ota', action: 'view', label: 'admin.perm.ota.view' }, { resource: 'ota', action: 'create', label: 'admin.perm.ota.create' },
  { resource: 'ota', action: 'control', label: 'admin.perm.ota.control' },
  { resource: 'dashboard', action: 'view', label: 'admin.perm.dashboard.view' }, { resource: 'dashboard', action: 'export', label: 'admin.perm.dashboard.export' },
  { resource: 'stations', action: 'view', label: 'admin.perm.stations.view' }, { resource: 'stations', action: 'create', label: 'admin.perm.stations.create' },
  { resource: 'stations', action: 'edit', label: 'admin.perm.stations.edit' },
  { resource: 'parallel', action: 'view', label: 'admin.perm.parallel.view' }, { resource: 'parallel', action: 'create', label: 'admin.perm.parallel.create' },
  { resource: 'parallel', action: 'control', label: 'admin.perm.parallel.control' },
  { resource: 'audit', action: 'view', label: 'admin.perm.audit.view' },
  { resource: 'admin', action: 'view', label: 'admin.perm.admin.view' }, { resource: 'admin', action: 'manage', label: 'admin.perm.admin.manage' },
]
const ROLE_TABS = [{ key: '0', label: 'admin.superAdminRole' }, { key: '1', label: 'admin.agentRole' }, { key: '2', label: 'admin.installerRole' }, { key: '3', label: 'admin.endUserRole' }]

const PermissionTab: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const [selectedRole, setSelectedRole] = useState<string>('1')
  const [permissions, setPermissions] = useState<Record<string, Set<string>>>({})
  const [originalPermissions, setOriginalPermissions] = useState<Record<string, Set<string>>>({})
  const [saving, setSaving] = useState(false)

  const { isLoading } = useQuery({
    queryKey: queryKeys.admin.permissions(Number(selectedRole)),
    queryFn: () => adminApi.getRolePermissions(Number(selectedRole)).then((r) => {
      const items = (r.data?.data ?? r.data ?? []) as { resource: string; action: string; is_allowed: boolean }[]
      const permSet: Record<string, Set<string>> = {}
      for (const item of items) {
        if (!permSet[item.resource]) permSet[item.resource] = new Set()
        if (item.is_allowed) permSet[item.resource].add(item.action)
      }
      setPermissions(permSet)
      setOriginalPermissions(structuredClone(permSet))
      return permSet
    }),
  })

  const handleToggle = (resource: string, action: string, checked: boolean) => {
    setPermissions((prev) => {
      const next = { ...prev }
      if (!next[resource]) next[resource] = new Set()
      else next[resource] = new Set(next[resource])
      checked ? next[resource].add(action) : next[resource].delete(action)
      return next
    })
  }

  const hasChanged = () => {
    for (const res of RESOURCE_ORDER) {
      const curr = permissions[res] ?? new Set()
      const orig = originalPermissions[res] ?? new Set()
      if (curr.size !== orig.size) return true
      for (const a of curr) { if (!orig.has(a)) return true }
    }
    return false
  }

  const handleSave = async () => {
    const permList = ALL_PERMISSION_DEFS.map((def) => ({ ...def, is_allowed: permissions[def.resource]?.has(def.action) ?? false }))
    setSaving(true)
    try {
      await adminApi.updateRolePermissions(Number(selectedRole), { permissions: permList })
      message.success(t('admin.permissionSaveSuccess'))
      setOriginalPermissions(structuredClone(permissions))
    } catch { message.error(t('admin.permissionSaveFailed')) }
    finally { setSaving(false) }
  }

  const groupedByResource = () => {
    const map: Record<string, typeof ALL_PERMISSION_DEFS> = {}
    for (const def of ALL_PERMISSION_DEFS) { if (!map[def.resource]) map[def.resource] = []; map[def.resource].push(def) }
    return RESOURCE_ORDER.filter((r) => map[r]).map((r) => ({ resource: r, label: t(RESOURCE_LABELS[r] ?? r), actions: map[r] }))
  }

  return (
    <div>
      <Card size="small" bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row justify="space-between" align="middle">
          <Col>
            <Space>
              <span style={{ fontWeight: 500 }}>{t('admin.selectRole')}：</span>
              <Select value={selectedRole} onChange={(val) => {
                if (hasChanged()) Modal.confirm({ title: t('admin.unsavedChanges'), content: t('admin.unsavedHint'), onOk: () => setSelectedRole(val) })
                else setSelectedRole(val)
              }} style={{ width: 160 }} options={ROLE_TABS.map((r) => ({ label: t(r.label), value: r.key }))} />
            </Space>
          </Col>
          <Col><Button type="primary" onClick={handleSave} loading={saving} disabled={!hasChanged()}>{t('admin.savePermissions')}</Button></Col>
        </Row>
      </Card>
      {selectedRole === '0' ? (
        <Card bordered={false} style={{ borderRadius: 12 }}><div style={{ textAlign: 'center', padding: 24, color: '#999', fontSize: 16 }}>{t('admin.superAdminHint')}</div></Card>
      ) : (
        <Spin spinning={isLoading}>
          <Row gutter={[16, 16]}>
            {groupedByResource().map((group) => {
              const allowedSet = permissions[group.resource] ?? new Set()
              return (
                <Col xs={24} sm={12} lg={8} xl={6} key={group.resource}>
                  <Card title={<span style={{ fontWeight: 600, fontSize: 14 }}>{group.label}</span>} size="small" bordered={false} style={{ borderRadius: 12 }}>
                    {group.actions.map((perm) => (
                      <div key={perm.action} style={{ marginBottom: 8 }}>
                        <Checkbox checked={allowedSet.has(perm.action)} onChange={(e) => handleToggle(group.resource, perm.action, e.target.checked)}>{t(perm.label)}</Checkbox>
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

const APIOverviewTab: React.FC<{ onNavigateToPermissions?: () => void }> = ({ onNavigateToPermissions }) => {
  const { t } = useTranslation()
  const [searchText, setSearchText] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['admin', 'route-groups'],
    queryFn: () => adminApi.getRouteGroups().then((r) => r.data?.data ?? r.data),
  })

  const groups = (data as any)?.groups ?? []

  const groupColors: Record<string, string> = {
    public: '#52c41a',
    user: '#1677ff',
    admin: '#ff4d4f',
  }
  const groupLabels: Record<string, string> = {
    public: t('admin.publicGroup'),
    user: t('admin.userGroup'),
    admin: t('admin.adminGroup'),
  }

  const filterRoutes = (routes: any[]) => {
    if (!searchText.trim()) return routes
    const keyword = searchText.toLowerCase()
    return routes.filter((r: any) =>
      r.path.toLowerCase().includes(keyword) ||
      r.description.toLowerCase().includes(keyword)
    )
  }

  return (
    <div>
      <Card size="small" bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row justify="space-between" align="middle">
          <Col>
            <Title level={5} style={{ margin: 0 }}>{t('admin.apiOverview')}</Title>
          </Col>
          <Col>
            <Input.Search
              placeholder={t('admin.searchApi')}
              allowClear
              style={{ width: 300 }}
              onSearch={setSearchText}
              onChange={(e) => !e.target.value && setSearchText('')}
            />
          </Col>
        </Row>
      </Card>
      <Spin spinning={isLoading}>
        <Row gutter={[16, 16]}>
          {groups.map((group: any) => {
            const filteredRoutes = filterRoutes(group.routes ?? [])
            return (
              <Col xs={24} md={8} key={group.name}>
                <Card
                  title={
                    <Space>
                      <Tag color={groupColors[group.name]} style={{ fontWeight: 600 }}>
                        {groupLabels[group.name] ?? group.name}
                      </Tag>
                      <Text type="secondary" style={{ fontSize: 12 }}>{group.description}</Text>
                    </Space>
                  }
                  size="small"
                  bordered={false}
                  style={{ borderRadius: 12 }}
                >
                  <div style={{ marginBottom: 8 }}>
                    <Text type="secondary" style={{ fontSize: 12 }}>
                      {t('admin.routeCount')}: {filteredRoutes.length}
                    </Text>
                  </div>
                  {filteredRoutes.map((route: any, idx: number) => (
                    <div
                      key={idx}
                      style={{
                        padding: '6px 8px',
                        marginBottom: 4,
                        borderRadius: 6,
                        background: '#fafafa',
                        display: 'flex',
                        alignItems: 'center',
                        gap: 8,
                      }}
                    >
                      <Tag
                        color={groupColors[group.name]}
                        style={{ fontSize: 10, lineHeight: '16px', minWidth: 36, textAlign: 'center' }}
                      >
                        {route.method}
                      </Tag>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 12, fontFamily: 'monospace', fontWeight: 500, wordBreak: 'break-all' }}>
                          {route.path}
                        </div>
                        <div style={{ fontSize: 11, color: '#999' }}>{route.description}</div>
                      </div>
                      <Tag style={{ fontSize: 10 }}>{route.backend}</Tag>
                      {group.name === 'admin' && onNavigateToPermissions && (
                        <Button
                          type="link"
                          size="small"
                          style={{ fontSize: 11, padding: '0 4px' }}
                          onClick={() => onNavigateToPermissions()}
                        >
                          {t('admin.viewPermissions') || '查看权限'}
                        </Button>
                      )}
                    </div>
                  ))}
                  {filteredRoutes.length === 0 && (
                    <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('admin.noMatchingRoutes')} />
                  )}
                </Card>
              </Col>
            )
          })}
        </Row>
      </Spin>
    </div>
  )
}

export default AdminPage
