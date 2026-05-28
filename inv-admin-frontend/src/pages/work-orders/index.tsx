import React, { useState, useEffect, useCallback } from 'react'
import {
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
  Space,
  Row,
  Col,
  Statistic,
  Radio,
  Empty,
  Dropdown,
  Upload,
  Image,
  Tooltip,
  message,
} from 'antd'
import {
  PlusOutlined,
  ReloadOutlined,
  EyeOutlined,
  DownOutlined,
  AppstoreOutlined,
  UnorderedListOutlined,
  UploadOutlined,
  WarningOutlined,
  ClockCircleOutlined,
  CheckCircleOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import type { UploadFile } from 'antd/es/upload/interface'
import dayjs from 'dayjs'
import { workOrderApi, type WorkOrderDetail, type WorkOrderTemplate } from '@/services/workOrderApi'
import { userApi } from '@/services/userApi'
import type { WorkOrder, User } from '@/types'

const { TextArea } = Input

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
const KANBAN_COLUMNS = WO_STATUS_OPTIONS

const SLA_STATUS_MAP: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
  ontime: { label: '正常', color: '#52c41a', icon: <CheckCircleOutlined /> },
  approaching: { label: '即将超时', color: '#fa8c16', icon: <ClockCircleOutlined /> },
  overdue: { label: '已超时', color: '#ff4d4f', icon: <WarningOutlined /> },
}

const TEMPLATE_ICONS: Record<string, string> = {
  installation: '\u2699\uFE0F',
  repair: '\uD83D\uDD27',
  inspection: '\uD83D\uDD0D',
  maintenance: '\uD83D\uDEE0\uFE0F',
}

interface Stats {
  open: number
  inProgress: number
  resolved: number
  closed: number
}

function getSlaStatus(slaDeadline?: string, status?: string): 'ontime' | 'approaching' | 'overdue' | null {
  if (!slaDeadline) return null
  if (status === 'resolved' || status === 'closed') return null
  const now = dayjs()
  const deadline = dayjs(slaDeadline)
  if (now.isAfter(deadline)) return 'overdue'
  const diffHours = deadline.diff(now, 'hour')
  if (diffHours < 2) return 'approaching'
  return 'ontime'
}

const WorkOrdersPage: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<WorkOrder[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [priorityFilter, setPriorityFilter] = useState<string>()
  const [slaFilter, setSlaFilter] = useState<string>()
  const [viewMode, setViewMode] = useState<'table' | 'kanban'>('table')
  const [stats, setStats] = useState<Stats>({ open: 0, inProgress: 0, resolved: 0, closed: 0 })
  const [templateOpen, setTemplateOpen] = useState(false)
  const [createOpen, setCreateOpen] = useState(false)
  const [creating, setCreating] = useState(false)
  const [templates, setTemplates] = useState<WorkOrderTemplate[]>([])
  const [selectedTemplate, setSelectedTemplate] = useState<string | null>(null)
  const [installers, setInstallers] = useState<User[]>([])
  const [detailOpen, setDetailOpen] = useState(false)
  const [detail, setDetail] = useState<WorkOrderDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [uploadingFiles, setUploadingFiles] = useState(false)
  const [form] = Form.useForm()

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const params: any = {
        page,
        pageSize,
        status: statusFilter || undefined,
        priority: priorityFilter || undefined,
      }
      const res = await workOrderApi.list(params)
      let items = res.data.data?.items ?? []
      if (slaFilter) {
        items = items.filter((item: WorkOrder) => {
          const sla = getSlaStatus(item.sla_deadline, item.status)
          return sla === slaFilter
        })
      }
      setData(items)
      setTotal(res.data.data?.total ?? 0)
    } catch {
      message.error('获取工单列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, statusFilter, priorityFilter, slaFilter])

  const fetchStats = async () => {
    try {
      const res = await workOrderApi.getStats()
      if (res.data.data) {
        setStats(res.data.data)
      }
    } catch {}
  }

  useEffect(() => {
    fetchData()
    fetchStats()
  }, [fetchData])

  const openCreateWithTemplate = async () => {
    try {
      const res = await workOrderApi.getTemplates()
      setTemplates(res.data?.data ?? [])
    } catch {
      setTemplates([])
    }
    setTemplateOpen(true)
  }

  const handleTemplateSelect = async (templateId: string) => {
    setSelectedTemplate(templateId)
    setTemplateOpen(false)
    setCreateOpen(true)

    const template = templates.find((t) => t.templateId === templateId)
    if (template) {
      form.setFieldsValue({
        title: template.title,
        description: template.description,
        priority: String(template.priority),
        templateType: templateId,
      })
    }

    try {
      const res = await userApi.getInstallers()
      setInstallers(res.data.data ?? [])
    } catch {}
  }

  const handleCreate = async () => {
    try {
      const values = await form.validateFields()
      setCreating(true)
      await workOrderApi.create({
        ...values,
        templateType: selectedTemplate || undefined,
      })
      message.success('工单创建成功')
      setCreateOpen(false)
      setTemplateOpen(false)
      form.resetFields()
      setSelectedTemplate(null)
      fetchData()
      fetchStats()
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
      setDetail(res.data.data ?? null)
    } catch {
      message.error('获取详情失败')
    } finally {
      setDetailLoading(false)
    }
  }

  const handleStatusChange = async (id: string, newStatus: string) => {
    try {
      await workOrderApi.updateStatus(id, newStatus)
      message.success('状态更新成功')
      fetchData()
      fetchStats()
      if (detailOpen) openDetail(id)
    } catch {
      message.error('状态更新失败')
    }
  }

  const handleEscalate = async (id: string) => {
    try {
      await workOrderApi.escalate(id)
      message.success('工单已升级')
      fetchData()
      fetchStats()
      if (detailOpen) openDetail(id)
    } catch {
      message.error('升级失败')
    }
  }

  const handleUploadAttachment = async (info: { fileList: UploadFile[]; file: UploadFile }) => {
    if (info.file.status === 'uploading') {
      setUploadingFiles(true)
      return
    }
    setUploadingFiles(false)
    if (info.file.status === 'done') {
      message.success('图片上传成功')
      if (detail) openDetail(detail.id)
    } else if (info.file.status === 'error') {
      message.error('图片上传失败')
    }
  }

  const columns: ColumnsType<WorkOrder> = [
    { title: '标题', dataIndex: 'title', key: 'title', width: 200, ellipsis: true },
    {
      title: 'SLA',
      key: 'sla',
      width: 90,
      render: (_: any, record: WorkOrder) => {
        const sla = getSlaStatus(record.sla_deadline, record.status)
        if (!sla) return <span style={{ color: '#d9d9d9' }}>-</span>
        const cfg = SLA_STATUS_MAP[sla]
        return (
          <Tooltip title={`${cfg.label}${record.sla_deadline ? ' - ' + dayjs(record.sla_deadline).format('MM-DD HH:mm') : ''}`}>
            <Tag color={cfg.color} icon={cfg.icon}>
              {cfg.label}
            </Tag>
          </Tooltip>
        )
      },
    },
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
      width: 220,
      render: (_: any, record: WorkOrder) => (
        <Space>
          <Button type="link" size="small" icon={<EyeOutlined />} onClick={() => openDetail(record.id)}>
            详情
          </Button>
          <Dropdown
            menu={{
              items: WO_STATUS_OPTIONS.map((s) => ({
                key: s,
                label: WO_STATUS_MAP[s]?.label || s,
              })),
              onClick: ({ key }) => handleStatusChange(record.id, key),
            }}
          >
            <Button type="link" size="small">
              状态 <DownOutlined />
            </Button>
          </Dropdown>
          {record.status !== 'resolved' && record.status !== 'closed' && (
            <Button
              type="link"
              size="small"
              danger
              onClick={() => handleEscalate(record.id)}
            >
              升级
            </Button>
          )}
        </Space>
      ),
    },
  ]

  const renderKanban = () => (
    <Row gutter={16} style={{ flexWrap: 'nowrap', overflowX: 'auto' }}>
      {KANBAN_COLUMNS.map((status) => {
        const items = data.filter((d) => d.status === status)
        const cfg = WO_STATUS_MAP[status]
        return (
          <Col key={status} style={{ minWidth: 280, maxWidth: 350 }}>
            <Card
              size="small"
              title={
                <Space>
                  <Tag color={cfg?.color}>{cfg?.label || status}</Tag>
                  <span style={{ fontWeight: 'normal', color: '#999' }}>({items.length})</span>
                </Space>
              }
              style={{ height: '100%', minHeight: 400, background: '#fafafa' }}
            >
              {items.length > 0 ? (
                items.map((item) => (
                  <Card
                    key={item.id}
                    size="small"
                    style={{ marginBottom: 8, cursor: 'pointer' }}
                    onClick={() => openDetail(item.id)}
                  >
                    <div style={{ fontWeight: 500, marginBottom: 4 }}>{item.title}</div>
                    <Space>
                      <Tag color={WO_PRIORITY_MAP[item.priority]?.color}>
                        {WO_PRIORITY_MAP[item.priority]?.label}
                      </Tag>
                      {getSlaStatus(item.sla_deadline, item.status) && (
                        <Tag
                          color={SLA_STATUS_MAP[getSlaStatus(item.sla_deadline, item.status)!]?.color}
                        >
                          {SLA_STATUS_MAP[getSlaStatus(item.sla_deadline, item.status)!]?.label}
                        </Tag>
                      )}
                      <span style={{ color: '#999', fontSize: 12 }}>
                        {dayjs(item.createdAt).format('MM-DD HH:mm')}
                      </span>
                    </Space>
                  </Card>
                ))
              ) : (
                <Empty description="暂无工单" image={Empty.PRESENTED_IMAGE_SIMPLE} />
              )}
            </Card>
          </Col>
        )
      })}
    </Row>
  )

  return (
    <div>
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <Card size="small">
            <Statistic title="待处理" value={stats.open} valueStyle={{ color: '#1677ff' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic title="处理中" value={stats.inProgress} valueStyle={{ color: '#1677ff' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic title="已解决" value={stats.resolved} valueStyle={{ color: '#52c41a' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small">
            <Statistic title="已关闭" value={stats.closed} />
          </Card>
        </Col>
      </Row>

      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={openCreateWithTemplate}>
              创建工单
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="SLA状态"
              style={{ width: 130 }}
              value={slaFilter}
              onChange={(val) => { setSlaFilter(val); setPage(1) }}
              options={Object.entries(SLA_STATUS_MAP).map(([k, v]) => ({ label: v.label, value: k }))}
            />
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
          <Col flex="auto" style={{ textAlign: 'right' }}>
            <Radio.Group value={viewMode} onChange={(e) => setViewMode(e.target.value)}>
              <Radio.Button value="table"><UnorderedListOutlined /> 表格</Radio.Button>
              <Radio.Button value="kanban"><AppstoreOutlined /> 看板</Radio.Button>
            </Radio.Group>
          </Col>
        </Row>
      </Card>

      {viewMode === 'table' ? (
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
      ) : (
        renderKanban()
      )}

      <Modal
        title="选择工单模板"
        open={templateOpen}
        onCancel={() => setTemplateOpen(false)}
        footer={null}
        width={720}
        destroyOnClose
      >
        <Row gutter={[16, 16]}>
          {templates.map((tpl) => (
            <Col key={tpl.templateId} span={6}>
              <Card
                hoverable
                size="small"
                style={{ textAlign: 'center', height: '100%' }}
                onClick={() => handleTemplateSelect(tpl.templateId)}
              >
                <div style={{ fontSize: 32, marginBottom: 8 }}>
                  {TEMPLATE_ICONS[tpl.templateId] || '\uD83D\uDCCB'}
                </div>
                <div style={{ fontWeight: 600, marginBottom: 4 }}>{tpl.title}</div>
                <div style={{ fontSize: 12, color: '#999', marginBottom: 8 }}>{tpl.description}</div>
                <Tag color={WO_PRIORITY_MAP[String(tpl.priority)]?.color}>
                  {WO_PRIORITY_MAP[String(tpl.priority)]?.label}优先级
                </Tag>
                <div style={{ fontSize: 12, color: '#999', marginTop: 4 }}>
                  预计 {tpl.estimatedHours}h
                </div>
              </Card>
            </Col>
          ))}
        </Row>
      </Modal>

      <Modal
        title={selectedTemplate ? '创建工单（模板预填）' : '创建工单'}
        open={createOpen}
        onCancel={() => {
          setCreateOpen(false)
          form.resetFields()
          setSelectedTemplate(null)
        }}
        onOk={handleCreate}
        confirmLoading={creating}
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Form.Item name="templateType" hidden>
            <Input />
          </Form.Item>
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
              {detail.slaDeadline && (
                <p>
                  <strong>SLA截止：</strong>
                  {dayjs(detail.slaDeadline).format('YYYY-MM-DD HH:mm:ss')}
                  {getSlaStatus(detail.slaDeadline, detail.status) && (
                    <Tag
                      color={SLA_STATUS_MAP[getSlaStatus(detail.slaDeadline, detail.status)!]?.color}
                      style={{ marginLeft: 8 }}
                    >
                      {SLA_STATUS_MAP[getSlaStatus(detail.slaDeadline, detail.status)!]?.label}
                    </Tag>
                  )}
                </p>
              )}
              <p><strong>描述：</strong>{detail.description}</p>
              <p><strong>创建人：</strong>{detail.creatorName || '-'}</p>
              <p><strong>指派人：</strong>{detail.assigneeName || '-'}</p>
              <p><strong>创建时间：</strong>{dayjs(detail.createdAt).format('YYYY-MM-DD HH:mm:ss')}</p>
              {detail.resolution && <p><strong>解决方案：</strong>{detail.resolution}</p>}
              {detail.templateType && (
                <p><strong>模板类型：</strong>
                  <Tag>{detail.templateType}</Tag>
                </p>
              )}
            </Card>

            <Card title="附件照片" size="small" style={{ marginBottom: 16 }}>
              {detail.attachments && detail.attachments.length > 0 ? (
                <div>
                  <Image.PreviewGroup>
                    <Row gutter={[8, 8]}>
                      {detail.attachments.map((att, idx) => (
                        <Col key={idx} span={8}>
                          <Image
                            src={att.url}
                            alt={att.name}
                            style={{ width: '100%', height: 120, objectFit: 'cover', borderRadius: 4 }}
                            fallback="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
                          />
                          <div style={{ fontSize: 11, color: '#999', marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {att.name}
                          </div>
                        </Col>
                      ))}
                    </Row>
                  </Image.PreviewGroup>
                </div>
              ) : (
                <span style={{ color: '#999' }}>暂无附件</span>
              )}
              <div style={{ marginTop: 12 }}>
                <Upload
                  multiple
                  maxCount={5}
                  accept="image/*"
                  showUploadList={false}
                  customRequest={async ({ file, onSuccess, onError }) => {
                    const formData = new FormData()
                    formData.append('files', file as File)
                    try {
                      await workOrderApi.uploadAttachment(detail.id, formData)
                      onSuccess?.({})
                    } catch (err) {
                      onError?.(err as Error)
                    }
                  }}
                  onChange={handleUploadAttachment}
                  disabled={uploadingFiles}
                >
                  <Button icon={<UploadOutlined />} loading={uploadingFiles}>
                    上传照片
                  </Button>
                </Upload>
                <span style={{ marginLeft: 8, fontSize: 12, color: '#999' }}>
                  最多10张，每次最多5张
                </span>
              </div>
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

            <Space>
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
              {detail.status !== 'resolved' && detail.status !== 'closed' && (
                <Button danger onClick={() => handleEscalate(detail.id)}>
                  升级工单
                </Button>
              )}
            </Space>
          </div>
        )}
        {!detail && !detailLoading && <div style={{ textAlign: 'center', color: '#999' }}>加载中...</div>}
      </Drawer>
    </div>
  )
}

export default WorkOrdersPage
