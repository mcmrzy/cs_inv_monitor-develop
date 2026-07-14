import { useState, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Modal, Form, Input, Select, Tag, Drawer,
  Timeline, Space, Row, Col, Statistic, Radio, Empty, Dropdown,
  Upload, Image, Tooltip, Typography, App, AutoComplete,
} from 'antd'
import {
  PlusOutlined, ReloadOutlined, EyeOutlined, DownOutlined,
  AppstoreOutlined, UnorderedListOutlined, UploadOutlined,
  WarningOutlined, ClockCircleOutlined, CheckCircleOutlined, FileTextOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import type { UploadFile } from 'antd/es/upload/interface'
import dayjs from 'dayjs'
import { workOrderApi, type WorkOrderDetail, type WorkOrderTemplate } from '@/services/workOrderApi'
import { deviceApi } from '@/services/deviceApi'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'
import useTranslation from '@/hooks/useTranslation'
import { queryKeys } from '@/utils/queryKeys'
import type { WorkOrder, User } from '@/types'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'

const { TextArea } = Input
const { Title } = Typography

const TEMPLATE_ICONS: Record<string, string> = {
  installation: '\u2699\uFE0F', repair: '\uD83D\uDD27', inspection: '\uD83D\uDD0D', maintenance: '\uD83D\uDEE0\uFE0F',
}

function getSlaStatus(slaDeadline?: string, status?: string): 'ontime' | 'approaching' | 'overdue' | null {
  if (!slaDeadline) return null
  if (status === 'resolved' || status === 'closed') return null
  const now = dayjs()
  const deadline = dayjs(slaDeadline)
  if (now.isAfter(deadline)) return 'overdue'
  if (deadline.diff(now, 'hour') < 2) return 'approaching'
  return 'ontime'
}

const WorkOrdersPage: React.FC = () => {
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const { user } = useAuthStore()
  const isEndUser = user?.role === Role.END_USER
  const isInstaller = user?.role === Role.INSTALLER
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [priorityFilter, setPriorityFilter] = useState<string>()
  const [slaFilter, setSlaFilter] = useState<string>()
  const [viewMode, setViewMode] = useState<'table' | 'kanban'>('table')
  const [templateOpen, setTemplateOpen] = useState(false)
  const [createOpen, setCreateOpen] = useState(false)
  const [selectedTemplate, setSelectedTemplate] = useState<string | null>(null)
  const [detailOpen, setDetailOpen] = useState(false)
  const [detailId, setDetailId] = useState<string | null>(null)
  const [form] = Form.useForm()

  // 设备列表查询（用于工单关联设备SN下拉选择）
  const { data: devicesRes } = useQuery({
    queryKey: ['devices', 'for-work-order', user?.id, user?.role],
    queryFn: () => {
      const params: any = { page_size: 200 }
      if (isInstaller) params.installerId = user?.id
      if (isEndUser) params.userId = user?.id
      return deviceApi.getDevices(params)
    },
    enabled: createOpen,
  })

  const deviceOptions = useMemo(() => {
    const d = devicesRes?.data?.data ?? devicesRes?.data ?? []
    const items = Array.isArray(d) ? d : (d?.items ?? [])
    return items.map((device: any) => ({
      value: device.sn,
      label: `${device.sn} (${device.model || '-'})`,
    }))
  }, [devicesRes])

  const WO_PRIORITY_MAP: Record<string, { label: string; color: string }> = {
    low: { label: t('wo.low'), color: '#d9d9d9' },
    medium: { label: t('wo.medium'), color: '#1677ff' },
    high: { label: t('wo.high'), color: '#fa8c16' },
    urgent: { label: t('wo.urgent'), color: '#ff4d4f' },
  }
  const WO_STATUS_MAP: Record<string, { label: string; color: string }> = {
    open: { label: t('wo.pending'), color: '#1677ff' },
    in_progress: { label: t('wo.processing'), color: '#1677ff' },
    resolved: { label: t('wo.resolved'), color: '#52c41a' },
    closed: { label: t('wo.closed'), color: '#d9d9d9' },
  }
  const WO_STATUS_OPTIONS = Object.keys(WO_STATUS_MAP)
  const KANBAN_COLUMNS = WO_STATUS_OPTIONS

  const SLA_STATUS_MAP: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
    ontime: { label: t('wo.normal'), color: '#52c41a', icon: <CheckCircleOutlined /> },
    approaching: { label: t('wo.expiringSoon'), color: '#fa8c16', icon: <ClockCircleOutlined /> },
    overdue: { label: t('wo.expired'), color: '#ff4d4f', icon: <WarningOutlined /> },
  }

  const queryParams = { page, page_size: pageSize, status: statusFilter || undefined, priority: priorityFilter || undefined }

  const { data: listRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.workOrders.list(queryParams),
    queryFn: () => workOrderApi.list(queryParams).then((r) => {
      let items = r.data?.data?.items ?? []
      if (slaFilter) {
        items = items.filter((item: WorkOrder) => getSlaStatus(item.sla_deadline, item.status) === slaFilter)
      }
      return { items, total: r.data?.data?.total ?? 0 }
    }),
  })

  const { data: stats } = useQuery({
    queryKey: queryKeys.workOrders.stats(),
    queryFn: () => workOrderApi.getStats().then((r) => r.data?.data ?? { open: 0, inProgress: 0, resolved: 0, closed: 0 }),
  })

  const { data: templates } = useQuery({
    queryKey: ['work-orders', 'templates'],
    queryFn: () => workOrderApi.getTemplates().then((r) => {
      const data = r.data?.data
      // 兼容数组格式和分页格式
      if (Array.isArray(data)) return data as WorkOrderTemplate[]
      if (data?.items && Array.isArray(data.items)) return data.items as WorkOrderTemplate[]
      return [] as WorkOrderTemplate[]
    }),
    enabled: templateOpen,
  })

  const { data: detail, isLoading: detailLoading } = useQuery({
    queryKey: queryKeys.workOrders.detail(detailId ?? ''),
    queryFn: () => workOrderApi.getDetail(detailId!).then((r) => r.data?.data ?? null as WorkOrderDetail | null),
    enabled: !!detailId,
  })

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: queryKeys.workOrders.all })
  }

  const createMutation = useMutation({
    mutationFn: (data: any) => workOrderApi.create(data),
    onSuccess: () => { message.success(t('wo.createSuccess')); setCreateOpen(false); setTemplateOpen(false); form.resetFields(); setSelectedTemplate(null); invalidate() },
    onError: () => { message.error(t('wo.createFailed')) },
  })

  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: string }) => workOrderApi.updateStatus(id, status),
    onSuccess: () => { message.success(t('wo.statusUpdateSuccess')); invalidate(); if (detailId) queryClient.invalidateQueries({ queryKey: queryKeys.workOrders.detail(detailId) }) },
    onError: () => { message.error(t('wo.statusUpdateFailed')) },
  })

  const escalateMutation = useMutation({
    mutationFn: (id: string) => workOrderApi.escalate(id),
    onSuccess: () => { message.success(t('wo.escalateSuccess')); invalidate(); if (detailId) queryClient.invalidateQueries({ queryKey: queryKeys.workOrders.detail(detailId) }) },
    onError: () => { message.error(t('wo.escalateFailed')) },
  })

  const handleTemplateSelect = (templateId: string) => {
    setSelectedTemplate(templateId)
    setTemplateOpen(false)
    setCreateOpen(true)
    const template = Array.isArray(templates) ? templates.find((t: WorkOrderTemplate) => t.templateId === templateId) : undefined
    if (template) {
      form.setFieldsValue({ title: template.title, description: template.description, priority: String(template.priority), templateType: templateId })
    }
  }

  const handleCreate = async () => {
    try {
      const values = await form.validateFields()
      createMutation.mutate({ ...values, templateType: selectedTemplate || undefined })
    } catch { /* validation failed */ }
  }

  const columns: ColumnsType<WorkOrder> = [
    { title: t('wo.orderTitle'), dataIndex: 'title', key: 'title', width: 200, ellipsis: true },
    {
      title: t('wo.slaStatus'), key: 'sla', width: 90,
      render: (_: any, record: WorkOrder) => {
        const sla = getSlaStatus(record.sla_deadline, record.status)
        if (!sla) return <span style={{ color: '#d9d9d9' }}>-</span>
        const cfg = SLA_STATUS_MAP[sla]
        return <Tooltip title={`${cfg.label}${record.sla_deadline ? ' - ' + formatInTimezone(record.sla_deadline, timezone, 'MM-DD HH:mm') : ''}`}><Tag color={cfg.color} icon={cfg.icon}>{cfg.label}</Tag></Tooltip>
      },
    },
    {
      title: t('wo.priority'), dataIndex: 'priority', key: 'priority', width: 80,
      render: (val: string) => { const cfg = WO_PRIORITY_MAP[val] || { label: val, color: '#d9d9d9' }; return <Tag color={cfg.color}>{cfg.label}</Tag> },
    },
    {
      title: t('wo.status'), dataIndex: 'status', key: 'status', width: 90,
      render: (val: string) => { const cfg = WO_STATUS_MAP[val] || { label: val, color: '#d9d9d9' }; return <Tag color={cfg.color}>{cfg.label}</Tag> },
    },
    { title: t('common.createdAt'), dataIndex: 'createdAt', key: 'createdAt', width: 170, render: (val: string) => formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') },
    {
      title: t('common.operation'), key: 'action', width: 220,
      render: (_: any, record: WorkOrder) => (
        <Space>
          <Button type="link" size="small" icon={<EyeOutlined />} onClick={() => { setDetailId(record.id); setDetailOpen(true) }}>{t('wo.viewDetail')}</Button>
          <Dropdown menu={{ items: WO_STATUS_OPTIONS.map((s) => ({ key: s, label: WO_STATUS_MAP[s]?.label || s })), onClick: ({ key }) => statusMutation.mutate({ id: record.id, status: key }) }}>
            <Button type="link" size="small">{t('wo.changeStatus')} <DownOutlined /></Button>
          </Dropdown>
          {record.status !== 'resolved' && record.status !== 'closed' && (
            <Button type="link" size="small" danger onClick={() => escalateMutation.mutate(record.id)}>{t('wo.escalateOrder')}</Button>
          )}
        </Space>
      ),
    },
  ]

  const renderKanban = () => (
    <Row gutter={16} style={{ flexWrap: 'nowrap', overflowX: 'auto' }}>
      {KANBAN_COLUMNS.map((status) => {
        const items = (listRes?.items ?? []).filter((d: WorkOrder) => d.status === status)
        const cfg = WO_STATUS_MAP[status]
        return (
          <Col key={status} style={{ minWidth: 280, maxWidth: 350 }}>
            <Card size="small" bordered={false}
              title={<Space><Tag color={cfg?.color}>{cfg?.label || status}</Tag><span style={{ fontWeight: 'normal', color: '#999' }}>({items.length})</span></Space>}
              style={{ height: '100%', minHeight: 400, background: '#fafafa', borderRadius: 12 }}>
              {items.length > 0 ? items.map((item: WorkOrder) => (
                <Card key={item.id} size="small" bordered={false} style={{ marginBottom: 8, cursor: 'pointer', borderRadius: 12 }}
                  onClick={() => { setDetailId(item.id); setDetailOpen(true) }}>
                  <div style={{ fontWeight: 500, marginBottom: 4 }}>{item.title}</div>
                  <Space>
                    <Tag color={WO_PRIORITY_MAP[item.priority]?.color}>{WO_PRIORITY_MAP[item.priority]?.label}</Tag>
                    {getSlaStatus(item.sla_deadline, item.status) && <Tag color={SLA_STATUS_MAP[getSlaStatus(item.sla_deadline, item.status)!]?.color}>{SLA_STATUS_MAP[getSlaStatus(item.sla_deadline, item.status)!]?.label}</Tag>}
                    <span style={{ color: '#999', fontSize: 12 }}>{formatInTimezone(item.createdAt, timezone, 'MM-DD HH:mm')}</span>
                  </Space>
                </Card>
              )) : <Empty description={t('wo.noOrders')} image={Empty.PRESENTED_IMAGE_SIMPLE} />}
            </Card>
          </Col>
        )
      })}
    </Row>
  )

  const data = listRes?.items ?? []
  const total = listRes?.total ?? 0

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}><FileTextOutlined style={{ marginRight: 8 }} />{t('wo.title')}</Title>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('wo.pending')} value={stats?.open ?? 0} valueStyle={{ color: '#1677ff' }} /></Card></Col>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('wo.processing')} value={stats?.inProgress ?? 0} valueStyle={{ color: '#1677ff' }} /></Card></Col>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('wo.resolved')} value={stats?.resolved ?? 0} valueStyle={{ color: '#52c41a' }} /></Card></Col>
        <Col span={6}><Card size="small" bordered={false} style={{ borderRadius: 12 }}><Statistic title={t('wo.closed')} value={stats?.closed ?? 0} /></Card></Col>
      </Row>

      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col><Button type="primary" icon={<PlusOutlined />} onClick={() => { setTemplateOpen(true); setSelectedTemplate(null) }}>{t('wo.createOrder')}</Button></Col>
          <Col><Select allowClear placeholder={t('wo.slaStatus')} style={{ width: 130 }} value={slaFilter} onChange={(val) => { setSlaFilter(val); setPage(1) }} options={Object.entries(SLA_STATUS_MAP).map(([k, v]) => ({ label: v.label, value: k }))} /></Col>
          <Col><Select allowClear placeholder={t('wo.status')} style={{ width: 120 }} value={statusFilter} onChange={(val) => { setStatusFilter(val); setPage(1) }} options={Object.entries(WO_STATUS_MAP).map(([k, v]) => ({ label: v.label, value: k }))} /></Col>
          <Col><Select allowClear placeholder={t('wo.templateHint')} style={{ width: 120 }} value={priorityFilter} onChange={(val) => { setPriorityFilter(val); setPage(1) }} options={Object.entries(WO_PRIORITY_MAP).map(([k, v]) => ({ label: v.label, value: k }))} /></Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
          <Col flex="auto" style={{ textAlign: 'right' }}>
            <Radio.Group value={viewMode} onChange={(e) => setViewMode(e.target.value)}>
              <Radio.Button value="table"><UnorderedListOutlined /> {t('wo.viewModeTable')}</Radio.Button>
              <Radio.Button value="kanban"><AppstoreOutlined /> {t('wo.viewModeBoard')}</Radio.Button>
            </Radio.Group>
          </Col>
        </Row>
      </Card>

      {viewMode === 'table' ? (
        <Table<WorkOrder> rowKey="id" columns={columns} dataSource={data} loading={isLoading} size="small"
          locale={{ emptyText: <Empty description={t('wo.noOrders')} /> }}
          pagination={{ current: page, pageSize, total, showSizeChanger: true, showTotal: (totalCount) => t('common.total', { total: totalCount }), onChange: (p, ps) => { setPage(p); setPageSize(ps) } }} />
      ) : renderKanban()}

      <Modal title={t('wo.selectTemplate')} open={templateOpen} onCancel={() => setTemplateOpen(false)} footer={null} width={720} destroyOnClose>
        <Row gutter={[16, 16]}>
          {Array.isArray(templates) && templates.map((tpl: WorkOrderTemplate) => (
            <Col key={tpl.templateId} span={6}>
              <Card hoverable size="small" style={{ textAlign: 'center', height: '100%' }} onClick={() => handleTemplateSelect(tpl.templateId)}>
                <div style={{ fontSize: 32, marginBottom: 8 }}>{TEMPLATE_ICONS[tpl.templateId] || '\uD83D\uDCCB'}</div>
                <div style={{ fontWeight: 600, marginBottom: 4 }}>{tpl.title}</div>
                <div style={{ fontSize: 12, color: '#999', marginBottom: 8 }}>{tpl.description}</div>
                <Tag color={WO_PRIORITY_MAP[String(tpl.priority)]?.color}>{WO_PRIORITY_MAP[String(tpl.priority)]?.label}{t('wo.templateHint')}</Tag>
                <div style={{ fontSize: 12, color: '#999', marginTop: 4 }}>{t('wo.estimatedHours', { hours: tpl.estimatedHours })}</div>
              </Card>
            </Col>
          ))}
        </Row>
      </Modal>

      <Modal title={selectedTemplate ? t('wo.createOrder') + t('wo.templatePrefill') : t('wo.createOrder')} open={createOpen}
        onCancel={() => { setCreateOpen(false); form.resetFields(); setSelectedTemplate(null) }}
        onOk={handleCreate} confirmLoading={createMutation.isPending} destroyOnClose>
        <Form form={form} layout="vertical">
          <Form.Item name="templateType" hidden><Input /></Form.Item>
          <Form.Item name="title" label={t('wo.orderTitle')} rules={[{ required: true, message: t('common.pleaseInput') + t('wo.orderTitle') }]}><Input placeholder={t('wo.orderTitle')} /></Form.Item>
          <Form.Item name="description" label={t('wo.description')} rules={[{ required: true, message: t('common.pleaseInput') + t('wo.description') }]}><TextArea rows={3} placeholder={t('wo.description')} /></Form.Item>
          <Form.Item name="deviceSn" label={t('wo.deviceSN')}>
            <AutoComplete
              placeholder={t('wo.deviceSNHint')}
              options={deviceOptions}
              filterOption={(inputValue, option) =>
                String(option?.value ?? '').toLowerCase().includes(inputValue.toLowerCase())
              }
              allowClear
              suffixIcon={<DownOutlined />}
            />
          </Form.Item>
          <Form.Item name="priority" label={t('wo.priority')} rules={[{ required: true, message: t('wo.selectPriority') }]}>
            <Select placeholder={t('wo.selectPriority')} options={Object.entries(WO_PRIORITY_MAP).map(([k, v]) => ({ label: v.label, value: k }))} />
          </Form.Item>
        </Form>
      </Modal>

      <Drawer title={t('wo.orderDetail')} open={detailOpen} onClose={() => { setDetailOpen(false); setDetailId(null) }} width={640} destroyOnClose>
        {detail && (
          <div>
            <Card size="small" style={{ marginBottom: 16 }}>
              <p><strong>{t('wo.orderTitle')}：</strong>{detail.title}</p>
              <p><strong>{t('wo.priority')}：</strong><Tag color={WO_PRIORITY_MAP[detail.priority]?.color}>{WO_PRIORITY_MAP[detail.priority]?.label || detail.priority}</Tag></p>
              <p><strong>{t('wo.status')}：</strong><Tag color={WO_STATUS_MAP[detail.status]?.color}>{WO_STATUS_MAP[detail.status]?.label || detail.status}</Tag></p>
              {detail.slaDeadline && <p><strong>{t('wo.slaDeadline')}：</strong>{formatInTimezone(detail.slaDeadline, timezone, 'YYYY-MM-DD HH:mm:ss')} {getSlaStatus(detail.slaDeadline, detail.status) && <Tag color={SLA_STATUS_MAP[getSlaStatus(detail.slaDeadline, detail.status)!]?.color} style={{ marginLeft: 8 }}>{SLA_STATUS_MAP[getSlaStatus(detail.slaDeadline, detail.status)!]?.label}</Tag>}</p>}
              <p><strong>{t('wo.description')}：</strong>{detail.description}</p>
              <p><strong>{t('wo.creator')}：</strong>{detail.creatorName || '-'}</p>
              <p><strong>{t('wo.assignee')}：</strong>{detail.assigneeName || '-'}</p>
              <p><strong>{t('common.createdAt')}：</strong>{formatInTimezone(detail.createdAt, timezone, 'YYYY-MM-DD HH:mm:ss')}</p>
              {detail.resolution && <p><strong>{t('wo.solution')}：</strong>{detail.resolution}</p>}
            </Card>

            <Card title={t('wo.attachments')} size="small" style={{ marginBottom: 16 }}>
              {detail.attachments && detail.attachments.length > 0 ? (
                <Image.PreviewGroup>
                  <Row gutter={[8, 8]}>
                    {detail.attachments.map((att: any, idx: number) => (
                      <Col key={idx} span={8}>
                        <Image src={att.url} alt={att.name} style={{ width: '100%', height: 120, objectFit: 'cover', borderRadius: 4 }}
                          fallback="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" />
                        <div style={{ fontSize: 11, color: '#999', marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{att.name}</div>
                      </Col>
                    ))}
                  </Row>
                </Image.PreviewGroup>
              ) : <span style={{ color: '#999' }}>{t('wo.noAttachments')}</span>}
              <div style={{ marginTop: 12 }}>
                <Upload multiple maxCount={5} accept="image/*" showUploadList={false}
                  customRequest={async ({ file, onSuccess, onError }) => {
                    const formData = new FormData(); formData.append('files', file as File)
                    try { await workOrderApi.uploadAttachment(detail.id, formData); onSuccess?.({}) } catch (err) { onError?.(err as Error) }
                  }}>
                  <Button icon={<UploadOutlined />}>{t('wo.uploadPhotos')}</Button>
                </Upload>
                <span style={{ marginLeft: 8, fontSize: 12, color: '#999' }}>{t('wo.uploadHint')}</span>
              </div>
            </Card>

            <Card title={t('wo.statusTimeline')} size="small" style={{ marginBottom: 16 }}>
              {detail.timeline && detail.timeline.length > 0 ? (
                <Timeline items={detail.timeline.map((t: any) => ({
                  children: <div><Tag color={WO_STATUS_MAP[t.status]?.color}>{WO_STATUS_MAP[t.status]?.label || t.status}</Tag><span style={{ marginLeft: 8 }}>{t.operator}</span><div style={{ color: '#999', fontSize: 12 }}>{formatInTimezone(t.timestamp, timezone, 'YYYY-MM-DD HH:mm:ss')}</div>{t.remark && <div>{t.remark}</div>}</div>,
                }))} />
              ) : <span style={{ color: '#999' }}>{t('wo.noRecords')}</span>}
            </Card>

            <Space>
              <Dropdown menu={{ items: WO_STATUS_OPTIONS.map((s) => ({ key: s, label: WO_STATUS_MAP[s]?.label || s })), onClick: ({ key }) => statusMutation.mutate({ id: detail.id, status: key }) }}>
                <Button>{t('wo.changeStatus')} <DownOutlined /></Button>
              </Dropdown>
              {detail.status !== 'resolved' && detail.status !== 'closed' && (
                <Button danger onClick={() => escalateMutation.mutate(detail.id)}>{t('wo.escalate')}</Button>
              )}
            </Space>
          </div>
        )}
        {!detail && !detailLoading && <div style={{ textAlign: 'center', color: '#999' }}>{t('common.loading')}</div>}
      </Drawer>
    </div>
  )
}

export default WorkOrdersPage
