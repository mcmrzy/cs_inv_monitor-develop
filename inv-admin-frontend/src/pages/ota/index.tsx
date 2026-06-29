import React, { useState, useCallback, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Tabs,
  Card,
  Table,
  Button,
  Modal,
  Form,
  Input,
  Upload,
  Select,
  Switch,
  Tag,
  Progress,
  Drawer,
  Space,
  Popconfirm,
  Row,
  Col,
  Tooltip,
  Empty,
  Slider,
  InputNumber,
  Descriptions,
  Typography,
  App,
  DatePicker,
} from 'antd'
import {
  UploadOutlined,
  PlusOutlined,
  ReloadOutlined,
  DeleteOutlined,
  PlayCircleOutlined,
  StopOutlined,
  RedoOutlined,
  InboxOutlined,
  RollbackOutlined,
  CloudUploadOutlined,
  MobileOutlined,
  AppleOutlined,
  AndroidOutlined,
  ClockCircleOutlined,
  CopyOutlined,
  SafetyOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import type { UploadProps } from 'antd'
import dayjs from 'dayjs'
import { otaApi } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import { modelApi } from '@/services/modelApi'
import { queryKeys } from '@/utils/queryKeys'
import type { Firmware, OtaTask, Device } from '@/types'
import useTranslation from '@/hooks/useTranslation'

const { TextArea } = Input
const { Dragger } = Upload
const { Title } = Typography

const TASK_STATUS_COLOR_MAP: Record<string, string> = {
  pending: '#1677ff',
  notifying: '#13c2c2',
  notified: '#722ed1',
  pushing: '#13c2c2',
  in_progress: '#1677ff',
  completed: '#52c41a',
  failed: '#ff4d4f',
  cancelled: '#d9d9d9',
  rolled_back: '#faad14',
}

const DEVICE_STATUS_COLOR_MAP: Record<string, string> = {
  pending: '#d9d9d9',
  notified: '#722ed1',
  downloading: '#1677ff',
  upgrading: '#fa8c16',
  success: '#52c41a',
  failed: '#ff4d4f',
  skipped: '#faad14',
}

const PERCENTAGE_MARKS: Record<number, string> = {
  10: '10%',
  25: '25%',
  50: '50%',
  75: '75%',
  100: '100%',
}

function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

async function computeSha256(file: File): Promise<string> {
  const buffer = await file.arrayBuffer()
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('')
}

interface FirmwareFormValues {
  model: string
  targetChip: string
  version: string
  changelog: string
  forceUpdate: boolean
}

interface TaskFormValues {
  name: string
  firmwareId: string
  model: string
  pushStrategy: string
  pushPercentage: number
  batchSize: number
  scheduledAt: string
  autoRollback: boolean
  rollbackThreshold: number
  targetFirmwareVersion: string
}

interface DeviceProgress {
  sn: string
  oldVersion: string
  newVersion: string
  status: string
  progress: number
  errorMessage: string
}

interface TaskDetail extends OtaTask {
  firmwareVersion: string
  devices: DeviceProgress[]
}

const OtaPage: React.FC = () => {
  const { t } = useTranslation()
  const [activeTab, setActiveTab] = useState('tasks')

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <CloudUploadOutlined style={{ marginRight: 8 }} />
        {t('ota.title')}
      </Title>
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        items={[
          { key: 'tasks', label: t('ota.upgradeTask'), children: <TasksTab /> },
          { key: 'firmware', label: t('ota.firmwareManage'), children: <FirmwareTab /> },
          { key: 'appVersion', label: t('ota.appVersionManage'), children: <AppVersionTab /> },
        ]}
      />
    </div>
  )
}

const FirmwareTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [modelFilter, setModelFilter] = useState<string>()
  const [chipFilter, setChipFilter] = useState<string>()
  const [uploadOpen, setUploadOpen] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [fileList, setFileList] = useState<any[]>([])
  const [computedSha256, setComputedSha256] = useState<string>('')
  const [computingHash, setComputingHash] = useState(false)
  const [form] = Form.useForm<FirmwareFormValues>()

  const TASK_STATUS_MAP: Record<string, { label: string; color: string }> = {
    pending: { label: t('ota.pendingPush'), color: TASK_STATUS_COLOR_MAP.pending },
    notifying: { label: t('ota.notifying'), color: TASK_STATUS_COLOR_MAP.notifying },
    notified: { label: t('ota.notified'), color: TASK_STATUS_COLOR_MAP.notified },
    pushing: { label: t('ota.pushing'), color: TASK_STATUS_COLOR_MAP.pushing },
    in_progress: { label: t('ota.upgrading'), color: TASK_STATUS_COLOR_MAP.in_progress },
    completed: { label: t('ota.completed'), color: TASK_STATUS_COLOR_MAP.completed },
    failed: { label: t('ota.failed'), color: TASK_STATUS_COLOR_MAP.failed },
    cancelled: { label: t('ota.cancelled'), color: TASK_STATUS_COLOR_MAP.cancelled },
    rolled_back: { label: t('ota.rolledBack'), color: TASK_STATUS_COLOR_MAP.rolled_back },
  }

  const queryParams = {
    page,
    pageSize,
    model: modelFilter || undefined,
  }

  const { data: firmwareRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.ota.firmwares(queryParams),
    queryFn: () => otaApi.listFirmware(queryParams).then((r) => {
      const d = r.data
      let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      if (!Array.isArray(list)) list = []
      if (chipFilter) {
        list = list.filter((item: Firmware) => item.target_chip === chipFilter)
      }
      return {
        items: list as Firmware[],
        total: (d?.total ?? d?.data?.total ?? list.length) as number,
      }
    }),
  })

  const { data: allFirmwareList = [] } = useQuery({
    queryKey: queryKeys.ota.firmwares({ all: true }),
    queryFn: () => otaApi.listFirmware({ page: 1, pageSize: 1000 }).then((r) => {
      const d = r.data
      let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      if (!Array.isArray(list)) list = []
      return list as Firmware[]
    }),
  })

  const { data: deviceModels = [] } = useQuery({
    queryKey: ['models', 'all'],
    queryFn: () => modelApi.listModels().then((r) => {
      const d = r.data?.data ?? r.data ?? []
      return Array.isArray(d) ? d : []
    }),
  })

  const uploadMutation = useMutation({
    mutationFn: (formData: FormData) => otaApi.uploadFirmware(formData),
    onSuccess: () => {
      message.success(t('ota.firmwareUploadSuccess'))
      setUploadOpen(false)
      form.resetFields()
      setFileList([])
      queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
    },
    onError: () => { message.error(t('ota.firmwareUploadFailed')) },
    onSettled: () => { setUploading(false) },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => otaApi.deleteFirmware(Number(id)),
    onSuccess: () => {
      message.success(t('ota.firmwareDeleteSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
    },
    onError: () => { message.error(t('ota.firmwareDeleteFailed')) },
  })

  const handleUpload = async () => {
    try {
      const values = await form.validateFields()
      if (fileList.length === 0) {
        message.warning(t('ota.pleaseSelectFirmware'))
        return
      }
      setUploading(true)
      const formData = new FormData()
      const modelValue = Array.isArray(values.model) ? values.model[0] : values.model
      formData.append('file', fileList[0].originFileObj)
      formData.append('model', modelValue)
      formData.append('target_chip', values.targetChip)
      formData.append('version', values.version)
      formData.append('changelog', values.changelog || '')
      formData.append('is_force', String(values.forceUpdate || false))
      uploadMutation.mutate(formData)
    } catch {
      setUploading(false)
    }
  }

  const computeNextVersion = useCallback(
    (model: string, chip: string) => {
      const matched = allFirmwareList.filter(
        (fw) => fw.model === model && fw.target_chip === chip
      )
      if (matched.length === 0) return '1.0.0'
      const versions = matched
        .map((fw) => fw.version)
        .filter(Boolean)
        .map((v) => {
          const parts = v.split('.').map(Number)
          return { major: parts[0] || 0, minor: parts[1] || 0, patch: parts[2] || 0 }
        })
        .sort((a, b) => {
          if (a.major !== b.major) return b.major - a.major
          if (a.minor !== b.minor) return b.minor - a.minor
          return b.patch - a.patch
        })
      if (versions.length === 0) return '1.0.0'
      const latest = versions[0]
      return `${latest.major}.${latest.minor}.${latest.patch + 1}`
    },
    [allFirmwareList]
  )

  const modelOptions = useMemo(() => {
    const firmwareModels = allFirmwareList.map((fw) => fw.model).filter(Boolean)
    const deviceModelNames = deviceModels.map((m: any) => m.model_code || m.model_name).filter(Boolean)
    const allModels = [...new Set([...firmwareModels, ...deviceModelNames])]
    return allModels.map((m) => ({ label: m, value: m }))
  }, [allFirmwareList, deviceModels])

  const uploadProps: UploadProps = {
    accept: '.bin',
    maxCount: 1,
    fileList,
    beforeUpload: async (file) => {
      setComputingHash(true)
      try {
        const sha256 = await computeSha256(file)
        setComputedSha256(sha256)
      } catch {
        setComputedSha256(t('ota.computeFailed'))
      } finally {
        setComputingHash(false)
      }
      setFileList([{ uid: '-1', name: file.name, status: 'done', originFileObj: file }])
      return false
    },
    onRemove: () => {
      setFileList([])
      setComputedSha256('')
    },
  }

  const firmwareData = firmwareRes?.items ?? []
  const firmwareTotal = firmwareRes?.total ?? 0

  const columns: ColumnsType<Firmware> = [
    { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 120 },
    {
      title: t('ota.mainVersion'),
      dataIndex: 'main_version',
      key: 'main_version',
      width: 100,
      render: (val: string) => <Tag color="blue">{val || '-'}</Tag>,
    },
    {
      title: t('ota.targetChip'),
      dataIndex: 'target_chip',
      key: 'target_chip',
      width: 90,
      render: (val: string) => {
        const chipMap: Record<string, { label: string; color: string }> = {
          esp: { label: 'ESP', color: 'green' },
          arm: { label: 'ARM', color: 'blue' },
          dsp: { label: 'DSP', color: 'orange' },
          bms: { label: 'BMS', color: 'purple' },
        }
        const chip = chipMap[val] || { label: val || '-', color: 'default' }
        return <Tag color={chip.color}>{chip.label}</Tag>
      },
    },
    { title: t('ota.subVersion'), dataIndex: 'version', key: 'version', width: 100 },
    {
      title: t('ota.fileSize'),
      dataIndex: 'file_size',
      key: 'file_size',
      width: 100,
      render: (size: number) => formatFileSize(size),
    },
    {
      title: 'MD5',
      dataIndex: 'file_md5',
      key: 'file_md5',
      width: 180,
      ellipsis: true,
      render: (val: string) => (
        <Tooltip title={val}>
          <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{val}</span>
        </Tooltip>
      ),
    },
    {
      title: 'SHA256',
      dataIndex: 'file_sha256',
      key: 'file_sha256',
      width: 200,
      ellipsis: true,
      render: (val: string) => val ? (
        <Tooltip title={val}>
          <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{val.slice(0, 16)}...</span>
        </Tooltip>
      ) : '-',
    },
    {
      title: t('ota.changelog'),
      dataIndex: 'changelog',
      key: 'changelog',
      ellipsis: true,
      render: (val: string) => (
        <Tooltip title={val}>
          <span>{val || '-'}</span>
        </Tooltip>
      ),
    },
    {
      title: t('ota.forceUpdate'),
      dataIndex: 'is_force',
      key: 'is_force',
      width: 110,
      render: (val: boolean) => (val ? <Tag color="red">{t('ota.force')}</Tag> : <Tag>{t('common.no')}</Tag>),
    },
    {
      title: t('ota.uploadTime'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('common.operation'),
      key: 'action',
      width: 80,
      render: (_: any, record: Firmware) => (
        <Popconfirm title={t('ota.confirmDeleteFirmware')} onConfirm={() => deleteMutation.mutate(record.id)}>
          <Button type="link" danger icon={<DeleteOutlined />} size="small" />
        </Popconfirm>
      ),
    },
  ]

  return (
    <div>
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<UploadOutlined />} onClick={() => setUploadOpen(true)}>
              {t('ota.uploadFirmware')}
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByModel')}
              style={{ width: 180 }}
              value={modelFilter}
              onChange={(val) => {
                setModelFilter(val)
                setPage(1)
              }}
              options={[...new Set(firmwareData.map((d) => d.model))].map((m) => ({
                label: m,
                value: m,
              }))}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByChip')}
              style={{ width: 140 }}
              value={chipFilter}
              onChange={(val) => {
                setChipFilter(val)
                setPage(1)
              }}
              options={[
                { label: 'ESP', value: 'esp' },
                { label: 'ARM', value: 'arm' },
                { label: 'DSP', value: 'dsp' },
                { label: 'BMS', value: 'bms' },
              ]}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={() => refetch()}>
              {t('common.refresh')}
            </Button>
          </Col>
        </Row>
      </Card>

      <Table<Firmware>
        rowKey="id"
        columns={columns}
        dataSource={firmwareData}
        loading={isLoading}
        size="small"
        pagination={{
          current: page,
          pageSize,
          total: firmwareTotal,
          showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => {
            setPage(p)
            setPageSize(ps)
          },
        }}
      />

      <Modal
        title={t('ota.uploadFirmwareTitle')}
        open={uploadOpen}
        onCancel={() => {
          setUploadOpen(false)
          form.resetFields()
          setFileList([])
        }}
        onOk={handleUpload}
        confirmLoading={uploading}
        destroyOnClose
        width={560}
      >
        <Form
          form={form}
          layout="vertical"
          onValuesChange={(changedValues, allValues) => {
            if (changedValues.model || changedValues.targetChip) {
              const model = Array.isArray(allValues.model) ? allValues.model[0] : allValues.model
              const { targetChip } = allValues
              if (model && targetChip) {
                const nextVersion = computeNextVersion(model, targetChip)
                form.setFieldsValue({ version: nextVersion })
              }
            }
          }}
        >
          <Form.Item name="model" label={t('ota.model')} rules={[{ required: true, message: t('ota.pleaseSelectOrInputModel') }]}>
            <Select
              showSearch
              allowClear
              mode="tags"
              maxCount={1}
              placeholder={t('ota.selectOrInputModel')}
              options={modelOptions}
              filterOption={(input, option) =>
                (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
              }
            />
          </Form.Item>
          <Form.Item name="targetChip" label={t('ota.targetChip')} rules={[{ required: true, message: t('ota.pleaseSelectTargetChip') }]}>
            <Select placeholder={t('ota.pleaseSelectTargetChip')}>
              <Select.Option value="esp">{t('ota.espChip')}</Select.Option>
              <Select.Option value="arm">{t('ota.armChip')}</Select.Option>
              <Select.Option value="dsp">{t('ota.dspChip')}</Select.Option>
              <Select.Option value="bms">{t('ota.bmsChip')}</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="version" label={t('ota.subVersion')} rules={[{ required: true, message: t('ota.inputSubVersion') }]}>
            <Input placeholder={t('ota.autoFillVersion')} />
          </Form.Item>
          <Form.Item name="changelog" label={t('ota.changelog')}>
            <TextArea rows={3} placeholder={t('ota.inputChangelog')} />
          </Form.Item>
          <Form.Item name="forceUpdate" label={t('ota.forceUpdate')} valuePropName="checked">
            <Switch />
          </Form.Item>
          <Form.Item label={t('ota.firmwareFile')}>
            <Dragger {...uploadProps}>
              <p className="ant-upload-drag-icon">
                <InboxOutlined />
              </p>
              <p className="ant-upload-text">{t('ota.dragFirmware')}</p>
              <p className="ant-upload-hint">{t('ota.firmwareFormat')}</p>
            </Dragger>
          </Form.Item>
          {fileList.length > 0 && (
            <Form.Item label={t('ota.fileSizeLabel')}>
              <span>{formatFileSize(fileList[0]?.originFileObj?.size || 0)}</span>
            </Form.Item>
          )}
        </Form>
      </Modal>
    </div>
  )
}

const TasksTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [createOpen, setCreateOpen] = useState(false)
  const [selectedDeviceSns, setSelectedDeviceSns] = useState<string[]>([])
  const [detailOpen, setDetailOpen] = useState(false)
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null)
  const [pushStrategy, setPushStrategy] = useState<string>('all_at_once')
  const [pushPercentage, setPushPercentage] = useState<number>(100)
  const [batchSize, setBatchSize] = useState<number>(10)
  const [scheduledAt, setScheduledAt] = useState<string>('')
  const [autoRollback, setAutoRollback] = useState<boolean>(false)
  const [rollbackThreshold, setRollbackThreshold] = useState<number>(30)
  const [form] = Form.useForm<TaskFormValues>()

  const TASK_STATUS_MAP: Record<string, { label: string; color: string }> = {
    pending: { label: t('ota.pendingPush'), color: TASK_STATUS_COLOR_MAP.pending },
    notifying: { label: t('ota.notifying'), color: TASK_STATUS_COLOR_MAP.notifying },
    notified: { label: t('ota.notified'), color: TASK_STATUS_COLOR_MAP.notified },
    pushing: { label: t('ota.pushing'), color: TASK_STATUS_COLOR_MAP.pushing },
    in_progress: { label: t('ota.upgrading'), color: TASK_STATUS_COLOR_MAP.in_progress },
    completed: { label: t('ota.completed'), color: TASK_STATUS_COLOR_MAP.completed },
    failed: { label: t('ota.failed'), color: TASK_STATUS_COLOR_MAP.failed },
    cancelled: { label: t('ota.cancelled'), color: TASK_STATUS_COLOR_MAP.cancelled },
    rolled_back: { label: t('ota.rolledBack'), color: TASK_STATUS_COLOR_MAP.rolled_back },
  }

  const DEVICE_STATUS_MAP: Record<string, { label: string; color: string }> = {
    pending: { label: t('ota.waiting'), color: DEVICE_STATUS_COLOR_MAP.pending },
    notified: { label: t('ota.notified'), color: DEVICE_STATUS_COLOR_MAP.notified },
    downloading: { label: t('ota.downloading'), color: DEVICE_STATUS_COLOR_MAP.downloading },
    upgrading: { label: t('ota.upgrading'), color: DEVICE_STATUS_COLOR_MAP.upgrading },
    success: { label: t('ota.success'), color: DEVICE_STATUS_COLOR_MAP.success },
    failed: { label: t('ota.failed'), color: DEVICE_STATUS_COLOR_MAP.failed },
    skipped: { label: t('ota.skipped'), color: DEVICE_STATUS_COLOR_MAP.skipped },
  }

  const PUSH_STRATEGY_MAP: Record<string, string> = {
    all_at_once: t('ota.pushAll'),
    percentage: t('ota.pushGray'),
    batch: t('ota.pushBatch'),
  }

  const queryParams = {
    page,
    pageSize,
    status: statusFilter || undefined,
  }

  const { data: tasksRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.ota.tasks(queryParams),
    queryFn: () => otaApi.listTasks(queryParams).then((r) => {
      const d = r.data
      const list = d?.items ?? d?.data?.items ?? d?.data ?? []
      return {
        items: (Array.isArray(list) ? list : []) as OtaTask[],
        total: (d?.total ?? d?.data?.total ?? (Array.isArray(list) ? list.length : 0)) as number,
      }
    }),
  })

  const { data: firmwareList = [] } = useQuery({
    queryKey: queryKeys.ota.firmwares({ all: true }),
    queryFn: () => otaApi.getAllFirmware().then((r) => {
      const d = r.data
      const list = d?.data?.items ?? d?.data ?? d?.items ?? []
      return (Array.isArray(list) ? list : []) as Firmware[]
    }),
  })

  const { data: deviceList = [] } = useQuery({
    queryKey: ['devices', 'all'],
    queryFn: () => deviceApi.getAll().then((r) => {
      const d = r.data
      const list = d?.data?.items ?? d?.data ?? d?.items ?? []
      return (Array.isArray(list) ? list : []) as Device[]
    }),
    enabled: createOpen,
  })

  const { data: taskDetail, isLoading: detailLoading } = useQuery({
    queryKey: queryKeys.ota.taskDetail(selectedTaskId ?? ''),
    queryFn: () => Promise.all([
      otaApi.getTask(selectedTaskId!),
      otaApi.getTaskDevices(selectedTaskId!),
    ]).then(([taskRes, devicesRes]) => {
      const task = (taskRes.data?.data ?? taskRes.data ?? {}) as OtaTask
      const devicesData = devicesRes.data?.data ?? devicesRes.data
      const devices: DeviceProgress[] = Array.isArray(devicesData) ? devicesData : []
      return { ...task, firmwareVersion: '', devices } as TaskDetail
    }),
    enabled: detailOpen && !!selectedTaskId,
    refetchInterval: (query) => {
      const status = query.state.data?.status
      return (status === 'pushing' || status === 'in_progress') ? 5000 : false
    },
  })

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
  }

  const duplicateTask = (task: OtaTask) => {
    form.setFieldsValue({
      name: `${task.name} (副本)`,
      firmwareId: (task as any).firmwareId || '',
      model: (task as any).model || '',
    })
    setPushStrategy((task as any).pushStrategy || 'all_at_once')
    setPushPercentage((task as any).pushPercentage || 100)
    setBatchSize((task as any).batchSize || 10)
    setScheduledAt('')
    setAutoRollback(false)
    setRollbackThreshold(30)
    setSelectedDeviceSns([])
    setCreateOpen(true)
  }

  const createMutation = useMutation({
    mutationFn: () => {
      const values = form.getFieldsValue()
      return otaApi.createTask({
        name: values.name,
        firmware_id: values.firmwareId,
        model: values.model || '',
        target_type: 'device_list',
        target_value: '',
        device_sns: selectedDeviceSns,
        description: '',
        push_strategy: pushStrategy,
        push_percentage: pushPercentage,
        batch_size: batchSize,
        scheduled_at: scheduledAt || null,
        auto_rollback: autoRollback,
        rollback_threshold: autoRollback ? rollbackThreshold : 0,
      })
    },
    onSuccess: () => {
      message.success(t('ota.taskCreateSuccess'))
      setCreateOpen(false)
      form.resetFields()
      setSelectedDeviceSns([])
      setPushStrategy('all_at_once')
      setPushPercentage(100)
      setBatchSize(10)
      invalidate()
    },
    onError: () => { message.error(t('ota.taskCreateFailed')) },
  })

  const executeMutation = useMutation({
    mutationFn: (id: string) => otaApi.executeTask(id),
    onSuccess: () => {
      message.success(t('ota.taskExecuteSuccess'))
      invalidate()
    },
    onError: () => { message.error(t('ota.taskExecuteFailed')) },
  })

  const notifyMutation = useMutation({
    mutationFn: (id: string) => otaApi.notifyDevices(id),
    onSuccess: () => {
      message.success(t('ota.taskNotifySuccess'))
      invalidate()
    },
    onError: () => { message.error(t('ota.taskNotifyFailed')) },
  })

  const cancelMutation = useMutation({
    mutationFn: (id: string) => otaApi.cancelTask(id),
    onSuccess: () => {
      message.success(t('ota.taskCancelSuccess'))
      invalidate()
      closeDetail()
    },
    onError: () => { message.error(t('ota.taskCancelFailed')) },
  })

  const retryMutation = useMutation({
    mutationFn: ({ taskId, sn }: { taskId: string; sn: string }) => otaApi.retryDevice(taskId, sn),
    onSuccess: () => {
      message.success(t('ota.taskRetrySuccess'))
      if (selectedTaskId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.ota.taskDetail(selectedTaskId) })
      }
    },
    onError: () => { message.error(t('ota.taskRetryFailed')) },
  })

  const rollbackMutation = useMutation({
    mutationFn: (taskId: string) => otaApi.rollbackTask(taskId),
    onSuccess: () => {
      message.success(t('ota.taskRollbackSuccess'))
      invalidate()
      if (selectedTaskId) {
        queryClient.invalidateQueries({ queryKey: queryKeys.ota.taskDetail(selectedTaskId) })
      }
    },
    onError: () => { message.error(t('ota.taskRollbackFailed')) },
  })

  const deleteMutation = useMutation({
    mutationFn: (taskId: string) => otaApi.deleteTask(taskId),
    onSuccess: () => {
      message.success(t('ota.taskDeleteSuccess'))
      invalidate()
      if (taskDetail && taskDetail.id === selectedTaskId) {
        setDetailOpen(false)
        setSelectedTaskId(null)
      }
    },
    onError: () => { message.error(t('ota.taskDeleteFailed')) },
  })

  const openDetail = (id: string) => {
    setSelectedTaskId(id)
    setDetailOpen(true)
  }

  const closeDetail = () => {
    setDetailOpen(false)
    setSelectedTaskId(null)
  }

  const handleCreate = async () => {
    try {
      await form.validateFields()
      if (selectedDeviceSns.length === 0) {
        message.warning(t('ota.pleaseSelectDevice'))
        return
      }
      createMutation.mutate()
    } catch {}
  }

  const openCreateModal = () => {
    setCreateOpen(true)
  }

  const selectedFirmware = firmwareList.find((f) => f.id === (taskDetail?.firmwareId ?? form.getFieldValue('firmwareId')))

  const columns: ColumnsType<OtaTask> = [
    { title: t('ota.taskName'), dataIndex: 'name', key: 'name', width: 160 },
    {
      title: t('ota.firmwareVersion'),
      dataIndex: 'firmwareId',
      key: 'firmwareId',
      width: 150,
      render: (val: string) => {
        const fw = firmwareList.find((f) => f.id === val)
        if (!fw) return val
        const chip = (fw.target_chip || 'esp').toUpperCase()
        return <span>{fw.main_version || fw.version} <Tag>{chip}</Tag></span>
      },
    },
    {
      title: t('ota.pushStrategy'),
      dataIndex: 'pushStrategy',
      key: 'pushStrategy',
      width: 120,
      render: (val: string) => PUSH_STRATEGY_MAP[val] || val || t('ota.allAtOnce'),
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const cfg = TASK_STATUS_MAP[status] || { label: status, color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    { title: t('ota.deviceTotal'), dataIndex: 'totalDevices', key: 'totalDevices', width: 90 },
    { title: t('ota.successCount'), dataIndex: 'successCount', key: 'successCount', width: 80 },
    { title: t('ota.failCount'), dataIndex: 'failedCount', key: 'failedCount', width: 80 },
    {
      title: t('ota.progress'),
      key: 'progress',
      width: 160,
      render: (_: any, record: OtaTask) => {
        const pct = record.totalDevices > 0
          ? Math.round(((record.successCount + record.failedCount) / record.totalDevices) * 100)
          : 0
        return <Progress percent={pct} size="small" />
      },
    },
    {
      title: t('common.createdAt'),
      dataIndex: 'createdAt',
      key: 'createdAt',
      width: 170,
      render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('common.operation'),
      key: 'action',
      width: 220,
      render: (_: any, record: OtaTask) => (
        <Space>
          <Button type="link" size="small" onClick={() => openDetail(record.id)}>
            {t('ota.detail')}
          </Button>
          {record.status === 'pending' && (
            <Popconfirm title={t('ota.confirmNotify')} onConfirm={() => notifyMutation.mutate(record.id)}>
              <Button type="link" size="small" icon={<PlayCircleOutlined />}>
                {t('ota.notify')}
              </Button>
            </Popconfirm>
          )}
          {record.status === 'notified' && (
            <Popconfirm title={t('ota.confirmExecute')} onConfirm={() => executeMutation.mutate(record.id)}>
              <Button type="link" size="small" icon={<PlayCircleOutlined />}>
                {t('ota.execute')}
              </Button>
            </Popconfirm>
          )}
          {(record.status === 'pushing' || record.status === 'in_progress' || record.status === 'notifying') && (
            <Popconfirm title={t('ota.confirmCancel')} onConfirm={() => cancelMutation.mutate(record.id)}>
              <Button type="link" size="small" danger icon={<StopOutlined />}>
                {t('ota.cancel')}
              </Button>
            </Popconfirm>
          )}
          {(record.status === 'completed' || record.status === 'failed') && (
            <Popconfirm title={t('ota.confirmRollback')} onConfirm={() => rollbackMutation.mutate(record.id)}>
              <Button type="link" size="small" icon={<RollbackOutlined />} loading={rollbackMutation.isPending}>
                {t('ota.rollback')}
              </Button>
            </Popconfirm>
          )}
          <Popconfirm title={t('ota.confirmDeleteTask')} onConfirm={() => deleteMutation.mutate(record.id)}>
            <Button type="link" size="small" danger icon={<DeleteOutlined />}>
              {t('common.delete')}
            </Button>
          </Popconfirm>
          <Button type="link" size="small" icon={<CopyOutlined />} onClick={() => duplicateTask(record)}>
            {t('ota.duplicateTask')}
          </Button>
        </Space>
      ),
    },
  ]

  const deviceColumns: ColumnsType<DeviceProgress> = [
    { title: 'SN', dataIndex: 'sn', key: 'sn', width: 140 },
    { title: t('ota.oldVersion'), dataIndex: 'oldVersion', key: 'oldVersion', width: 100 },
    { title: t('ota.newVersion'), dataIndex: 'newVersion', key: 'newVersion', width: 100 },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const cfg = DEVICE_STATUS_MAP[status] || { label: status, color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('ota.progress'),
      dataIndex: 'progress',
      key: 'progress',
      width: 150,
      render: (val: number) => <Progress percent={val} size="small" />,
    },
    {
      title: t('ota.errorInfo'),
      dataIndex: 'errorMessage',
      key: 'errorMessage',
      ellipsis: true,
      render: (val: string) => val || '-',
    },
    {
      title: t('common.operation'),
      key: 'action',
      width: 80,
      render: (_: any, record: DeviceProgress) => (
        record.status === 'failed' && taskDetail ? (
          <Button
            type="link"
            size="small"
            icon={<RedoOutlined />}
            onClick={() => retryMutation.mutate({ taskId: taskDetail.id, sn: record.sn })}
          >
            {t('ota.retry')}
          </Button>
        ) : null
      ),
    },
  ]

  const taskData = tasksRes?.items ?? []
  const taskTotal = tasksRes?.total ?? 0

  return (
    <div>
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={openCreateModal}>
              {t('ota.createTask')}
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByStatus')}
              style={{ width: 140 }}
              value={statusFilter}
              onChange={(val) => {
                setStatusFilter(val)
                setPage(1)
              }}
              options={Object.entries(TASK_STATUS_MAP).map(([k, v]) => ({
                label: v.label,
                value: k,
              }))}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={() => refetch()}>
              {t('common.refresh')}
            </Button>
          </Col>
        </Row>
      </Card>

      <Table<OtaTask>
        rowKey="id"
        columns={columns}
        dataSource={taskData}
        loading={isLoading}
        size="small"
        pagination={{
          current: page,
          pageSize,
          total: taskTotal,
          showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => {
            setPage(p)
            setPageSize(ps)
          },
        }}
      />

      <Modal
        title={t('ota.createTaskTitle')}
        open={createOpen}
        onCancel={() => {
          setCreateOpen(false)
          form.resetFields()
          setSelectedDeviceSns([])
          setPushStrategy('all_at_once')
          setPushPercentage(100)
          setBatchSize(10)
        }}
        onOk={handleCreate}
        confirmLoading={createMutation.isPending}
        destroyOnClose
        width={700}
      >
        <Form form={form} layout="vertical">
          <Form.Item name="name" label={t('ota.taskName')} rules={[{ required: true, message: t('ota.pleaseInputTaskName') }]}>
            <Input placeholder={t('ota.taskNamePlaceholder')} />
          </Form.Item>
          <Form.Item name="firmwareId" label={t('ota.selectFirmware')} rules={[{ required: true, message: t('ota.pleaseSelectFirmware') }]}>
            <Select
              placeholder={t('ota.selectFirmwareVersion')}
              options={firmwareList.map((fw) => ({
                label: `${fw.model} - ${fw.main_version || 'v' + fw.version} [${(fw.target_chip || 'esp').toUpperCase()}]`,
                value: fw.id,
              }))}
              onChange={(val) => {
                const fw = firmwareList.find((f) => f.id === val)
                if (fw) form.setFieldsValue({ model: fw.model })
              }}
            />
          </Form.Item>
          <Form.Item name="model" hidden>
            <Input />
          </Form.Item>
          <Form.Item label={t('ota.pushStrategy')}>
            <Select
              value={pushStrategy}
              onChange={(val) => setPushStrategy(val)}
              options={[
                { label: t('ota.pushAll'), value: 'all_at_once' },
                { label: t('ota.pushGray'), value: 'percentage' },
                { label: t('ota.pushBatch'), value: 'batch' },
              ]}
            />
          </Form.Item>
          {pushStrategy === 'percentage' && (
            <Form.Item label={t('ota.grayPercent')}>
              <Slider
                marks={PERCENTAGE_MARKS}
                step={null}
                min={10}
                max={100}
                value={pushPercentage}
                onChange={(val) => setPushPercentage(val)}
              />
              <div style={{ marginTop: 4, color: '#999' }}>
                {t('ota.grayPercentageDesc', { percent: pushPercentage })}
              </div>
            </Form.Item>
          )}
          {pushStrategy === 'batch' && (
            <Form.Item label={t('ota.batchSize')}>
              <InputNumber
                min={1}
                max={100}
                value={batchSize}
                onChange={(val) => setBatchSize(val || 10)}
                addonAfter={t('ota.devicesPerBatch')}
              />
              <div style={{ marginTop: 4, color: '#999' }}>
                {t('ota.batchDesc')}
              </div>
            </Form.Item>
          )}
          <Form.Item label={t('ota.scheduledPush')}>
            <DatePicker
              showTime
              format="YYYY-MM-DD HH:mm"
              placeholder={t('ota.scheduledPushPlaceholder')}
              value={scheduledAt ? dayjs(scheduledAt) : null}
              onChange={(val) => setScheduledAt(val ? val.toISOString() : '')}
              style={{ width: '100%' }}
              disabledDate={(current) => current && current < dayjs().subtract(1, 'minute')}
            />
            <div style={{ marginTop: 4, color: '#999' }}>
              {t('ota.scheduledPushDesc')}
            </div>
          </Form.Item>
          <Form.Item label={t('ota.autoRollback')}>
            <Space>
              <Switch checked={autoRollback} onChange={setAutoRollback} />
              {autoRollback && (
                <Space>
                  <span>{t('ota.rollbackThresholdPrefix')}</span>
                  <InputNumber
                    min={1}
                    max={100}
                    value={rollbackThreshold}
                    onChange={(val) => setRollbackThreshold(val || 30)}
                    style={{ width: 80 }}
                  />
                  <span>%</span>
                  <span>{t('ota.rollbackThresholdSuffix')}</span>
                </Space>
              )}
            </Space>
            <div style={{ marginTop: 4, color: '#999' }}>
              {t('ota.autoRollbackDesc')}
            </div>
          </Form.Item>
          <Form.Item label={t('ota.selectDevices')}>
            {deviceList.length > 0 ? (
              <Table<Device>
                rowKey="sn"
                size="small"
                rowSelection={{
                  selectedRowKeys: selectedDeviceSns,
                  onChange: (keys) => setSelectedDeviceSns(keys as string[]),
                }}
                dataSource={deviceList}
                columns={[
                  { title: 'SN', dataIndex: 'sn', key: 'sn', width: 140 },
                  { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 100 },
                  {
                    title: t('ota.currentFirmware'),
                    dataIndex: 'firmwareVersion',
                    key: 'firmwareVersion',
                    width: 120,
                    render: (v: string) => v || '-',
                  },
                ]}
                pagination={false}
                scroll={{ y: 300 }}
              />
            ) : (
              <Empty description={t('ota.noDeviceData')} />
            )}
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title={t('ota.taskDetail')}
        open={detailOpen}
        onClose={closeDetail}
        width={860}
        destroyOnClose
      >
        {taskDetail && (
          <div>
            <Card size="small" style={{ marginBottom: 16 }}>
              <Descriptions column={2} size="small">
                <Descriptions.Item label={t('ota.taskName')}>{taskDetail.name}</Descriptions.Item>
                <Descriptions.Item label={t('common.status')}>
                  <Tag color={TASK_STATUS_MAP[taskDetail.status]?.color}>
                    {TASK_STATUS_MAP[taskDetail.status]?.label || taskDetail.status}
                  </Tag>
                </Descriptions.Item>
                <Descriptions.Item label={t('ota.pushStrategy')}>
                  {PUSH_STRATEGY_MAP[taskDetail.pushStrategy] || taskDetail.pushStrategy || t('ota.allAtOnce')}
                </Descriptions.Item>
                <Descriptions.Item label={t('ota.deviceStatistics')}>
                  <span>{t('ota.totalLabel')}: {taskDetail.totalDevices} </span>
                  <span style={{ color: '#52c41a', marginLeft: 8 }}>{t('ota.successLabel')}: {taskDetail.successCount}</span>
                  <span style={{ color: '#ff4d4f', marginLeft: 8 }}>{t('ota.failLabel')}: {taskDetail.failedCount}</span>
                </Descriptions.Item>
                {(taskDetail as any).scheduledAt && (
                  <Descriptions.Item label={t('ota.scheduledTime')}>
                    <ClockCircleOutlined style={{ marginRight: 4 }} />
                    {dayjs((taskDetail as any).scheduledAt).format('YYYY-MM-DD HH:mm')}
                  </Descriptions.Item>
                )}
                <Descriptions.Item label={t('ota.autoRollback')}>
                  {(taskDetail as any).autoRollback ? (
                    <Tag color="green">
                      {t('ota.autoRollbackEnabled')} ({(taskDetail as any).rollbackThreshold || 30}%)
                    </Tag>
                  ) : (
                    <Tag>{t('ota.autoRollbackDisabled')}</Tag>
                  )}
                </Descriptions.Item>
                {taskDetail.pushStrategy === 'batch' && (
                  <Descriptions.Item label={t('ota.batchProgress')}>
                    {t('ota.currentBatch')}: {(taskDetail as any).currentBatch || '-'} / {(taskDetail as any).totalBatches || '-'}
                  </Descriptions.Item>
                )}
                {taskDetail.pushStrategy === 'percentage' && (
                  <Descriptions.Item label={t('ota.grayPercent')}>
                    {taskDetail.pushPercentage || 100}%
                  </Descriptions.Item>
                )}
              </Descriptions>
              <Progress
                percent={
                  taskDetail.totalDevices > 0
                    ? Math.round(((taskDetail.successCount + taskDetail.failedCount) / taskDetail.totalDevices) * 100)
                    : 0
                }
                style={{ marginTop: 12 }}
              />
            </Card>

            {selectedFirmware && (
              <Card size="small" style={{ marginBottom: 16 }}>
                <Descriptions column={2} size="small">
                  <Descriptions.Item label={t('ota.downloadURL')}>
                    <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{selectedFirmware.fileUrl}</span>
                  </Descriptions.Item>
                  <Descriptions.Item label={t('ota.fileSize')}>{formatFileSize(selectedFirmware.fileSize)}</Descriptions.Item>
                  <Descriptions.Item label="MD5">
                    <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{selectedFirmware.fileMd5}</span>
                  </Descriptions.Item>
                  <Descriptions.Item label="SHA256">
                    <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{selectedFirmware.fileSha256 || '-'}</span>
                  </Descriptions.Item>
                </Descriptions>
              </Card>
            )}

            <Table<DeviceProgress>
              rowKey="sn"
              columns={deviceColumns}
              dataSource={taskDetail.devices}
              loading={detailLoading}
              size="small"
              scroll={{ x: 800 }}
              pagination={false}
            />

            <Space style={{ marginTop: 16 }}>
              {taskDetail.status === 'pending' && (
                <Button type="primary" icon={<PlayCircleOutlined />} onClick={() => executeMutation.mutate(taskDetail.id)}>
                  {t('ota.executeTask')}
                </Button>
              )}
              {(taskDetail.status === 'pushing' || taskDetail.status === 'in_progress') && (
                <Button danger icon={<StopOutlined />} onClick={() => cancelMutation.mutate(taskDetail.id)}>
                  {t('ota.cancelTask')}
                </Button>
              )}
              {(taskDetail.status === 'completed' || taskDetail.status === 'failed') && (
                <Popconfirm title={t('ota.confirmRollback')} onConfirm={() => rollbackMutation.mutate(taskDetail.id)}>
                  <Button icon={<RollbackOutlined />} loading={rollbackMutation.isPending}>
                    {t('ota.rollback')}
                  </Button>
                </Popconfirm>
              )}
            </Space>
          </div>
        )}
        {!taskDetail && !detailLoading && <Empty description={t('ota.loading')} />}
      </Drawer>
    </div>
  )
}

const AppVersionTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const [platformFilter, setPlatformFilter] = useState<string>()
  const [createOpen, setCreateOpen] = useState(false)
  const [rolloutModalOpen, setRolloutModalOpen] = useState(false)
  const [rolloutTarget, setRolloutTarget] = useState<any>(null)
  const [rolloutPercent, setRolloutPercent] = useState<number>(100)
  const [form] = Form.useForm()

  const { data: versionData = [], isLoading, refetch } = useQuery({
    queryKey: queryKeys.ota.appVersions(platformFilter ? { platform: platformFilter } : undefined),
    queryFn: () => otaApi.getAppVersions(platformFilter).then((r) => {
      const d = r.data
      const list = d?.data ?? d?.items ?? d ?? []
      return Array.isArray(list) ? list : []
    }),
  })

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: queryKeys.ota.appVersions() })
  }

  const createMutation = useMutation({
    mutationFn: (data: any) => otaApi.createAppVersion(data),
    onSuccess: () => {
      message.success(t('ota.versionPublishSuccess'))
      setCreateOpen(false)
      form.resetFields()
      invalidate()
    },
    onError: () => { message.error(t('ota.versionPublishFailed')) },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => otaApi.deleteAppVersion(id),
    onSuccess: () => {
      message.success(t('ota.appVersionDeleteSuccess'))
      invalidate()
    },
    onError: () => { message.error(t('ota.appVersionDeleteFailed')) },
  })

  const rolloutMutation = useMutation({
    mutationFn: ({ id, percentage }: { id: number; percentage: number }) => otaApi.updateAppVersionRollout(id, percentage),
    onSuccess: () => {
      message.success(t('ota.rolloutUpdateSuccess'))
      setRolloutModalOpen(false)
      invalidate()
    },
    onError: () => { message.error(t('ota.rolloutUpdateFailed')) },
  })

  const rollbackMutation = useMutation({
    mutationFn: (id: number) => otaApi.rollbackAppVersion(id),
    onSuccess: () => {
      message.success(t('ota.appRollbackSuccess'))
      invalidate()
    },
    onError: () => { message.error(t('ota.appRollbackFailed')) },
  })

  const restoreMutation = useMutation({
    mutationFn: (id: number) => otaApi.restoreAppVersion(id),
    onSuccess: () => {
      message.success(t('ota.appRestoreSuccess'))
      invalidate()
    },
    onError: () => { message.error(t('ota.appRestoreFailed')) },
  })

  const handleCreate = async () => {
    try {
      const values = await form.validateFields()
      createMutation.mutate({
        platform: values.platform,
        version_code: values.versionCode,
        version_name: values.versionName,
        download_url: values.downloadUrl,
        file_size: values.fileSize || 0,
        file_md5: values.fileMd5 || '',
        changelog: values.changelog || '',
        is_force: values.isForce || false,
        min_supported_version: values.minSupportedVersion || 0,
        rollout_percentage: values.rolloutPercentage || 100,
      })
    } catch {}
  }

  const openRolloutModal = (record: any) => {
    setRolloutTarget(record)
    setRolloutPercent(record.rollout_percentage ?? 100)
    setRolloutModalOpen(true)
  }

  const handleRollout = () => {
    if (!rolloutTarget) return
    rolloutMutation.mutate({ id: rolloutTarget.id, percentage: rolloutPercent })
  }

  const ROLLOUT_MARKS: Record<number, string> = { 0: '0%', 10: '10%', 25: '25%', 50: '50%', 75: '75%', 100: '100%' }

  const columns: ColumnsType<any> = [
    {
      title: t('ota.platform'),
      dataIndex: 'platform',
      key: 'platform',
      width: 90,
      render: (val: string) => (
        <Tag icon={val === 'ios' ? <AppleOutlined /> : <AndroidOutlined />} color={val === 'ios' ? '#000' : '#52c41a'}>
          {val === 'ios' ? 'iOS' : 'Android'}
        </Tag>
      ),
    },
    {
      title: t('ota.versionCode'),
      dataIndex: 'version_code',
      key: 'version_code',
      width: 80,
      render: (val: number) => <Tag color="blue">{val}</Tag>,
    },
    {
      title: t('ota.versionName'),
      dataIndex: 'version_name',
      key: 'version_name',
      width: 100,
    },
    {
      title: t('ota.downloadUrl'),
      dataIndex: 'download_url',
      key: 'download_url',
      ellipsis: true,
      render: (val: string) => <Tooltip title={val}><span style={{ fontFamily: 'monospace', fontSize: 12 }}>{val || '-'}</span></Tooltip>,
    },
    {
      title: t('ota.forceUpdate'),
      dataIndex: 'is_force',
      key: 'is_force',
      width: 80,
      render: (val: boolean) => (val ? <Tag color="red">{t('ota.force')}</Tag> : <Tag>{t('common.no')}</Tag>),
    },
    {
      title: t('ota.rolloutPercent'),
      dataIndex: 'rollout_percentage',
      key: 'rollout_percentage',
      width: 120,
      render: (val: number, record: any) => {
        if (record.is_rolled_back) return <Tag color="red">{t('ota.rolledBack')}</Tag>
        const pct = val ?? 100
        return (
          <Space>
            <Progress percent={pct} size="small" style={{ width: 60 }} />
            <span style={{ fontSize: 12 }}>{pct}%</span>
          </Space>
        )
      },
    },
    {
      title: t('ota.changelog'),
      dataIndex: 'changelog',
      key: 'changelog',
      ellipsis: true,
      render: (val: string) => <Tooltip title={val}><span>{val || '-'}</span></Tooltip>,
    },
    {
      title: t('ota.publishTime'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 150,
      render: (val: string) => (val ? dayjs(val).format('YYYY-MM-DD HH:mm') : '-'),
    },
    {
      title: t('common.operation'),
      key: 'action',
      width: 200,
      render: (_: any, record: any) => (
        <Space>
          {record.is_rolled_back ? (
            <Popconfirm title={t('ota.confirmRestore')} onConfirm={() => restoreMutation.mutate(record.id)}>
              <Button type="link" size="small" icon={<RedoOutlined />} loading={restoreMutation.isPending}>
                {t('ota.restore')}
              </Button>
            </Popconfirm>
          ) : (
            <>
              <Button type="link" size="small" icon={<SafetyOutlined />} onClick={() => openRolloutModal(record)}>
                {t('ota.grayRelease')}
              </Button>
              <Popconfirm title={t('ota.confirmAppRollback')} onConfirm={() => rollbackMutation.mutate(record.id)}>
                <Button type="link" size="small" danger icon={<RollbackOutlined />} loading={rollbackMutation.isPending}>
                  {t('ota.rollback')}
                </Button>
              </Popconfirm>
            </>
          )}
          <Popconfirm title={t('ota.confirmDeleteVersion')} onConfirm={() => deleteMutation.mutate(record.id)}>
            <Button type="link" danger icon={<DeleteOutlined />} size="small" />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateOpen(true)}>
              {t('ota.publishVersion')}
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByPlatform')}
              style={{ width: 140 }}
              value={platformFilter}
              onChange={(val) => setPlatformFilter(val)}
              options={[{ label: 'Android', value: 'android' }, { label: 'iOS', value: 'ios' }]}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
          </Col>
        </Row>
      </Card>

      <Table
        rowKey="id"
        columns={columns}
        dataSource={versionData}
        loading={isLoading}
        size="small"
        pagination={false}
      />

      {/* 创建版本 Modal */}
      <Modal
        title={t('ota.publishAppVersion')}
        open={createOpen}
        onCancel={() => { setCreateOpen(false); form.resetFields() }}
        onOk={handleCreate}
        confirmLoading={createMutation.isPending}
        destroyOnClose
        width={560}
      >
        <Form form={form} layout="vertical">
          <Form.Item name="platform" label={t('ota.platform')} rules={[{ required: true, message: t('ota.pleaseSelectPlatform') }]}>
            <Select placeholder={t('ota.pleaseSelectPlatform')}>
              <Select.Option value="android"><AndroidOutlined style={{ color: '#52c41a', marginRight: 4 }} /> Android</Select.Option>
              <Select.Option value="ios"><AppleOutlined style={{ marginRight: 4 }} /> iOS</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="versionCode" label={t('ota.versionCode')} rules={[{ required: true, message: t('ota.pleaseInputVersionCode') }]}>
            <InputNumber min={1} style={{ width: '100%' }} placeholder={t('ota.versionCodePlaceholder')} />
          </Form.Item>
          <Form.Item name="versionName" label={t('ota.versionName')} rules={[{ required: true, message: t('ota.pleaseInputVersionName') }]}>
            <Input placeholder={t('ota.versionNamePlaceholder')} />
          </Form.Item>
          <Form.Item name="downloadUrl" label={t('ota.downloadUrl')} rules={[{ required: true, message: t('ota.pleaseInputDownloadUrl') }]}>
            <Input placeholder={t('ota.downloadUrlPlaceholder')} />
          </Form.Item>
          <Form.Item name="fileSize" label={t('ota.fileSizeBytes')}>
            <InputNumber min={0} style={{ width: '100%' }} placeholder={t('ota.fileSizePlaceholder')} />
          </Form.Item>
          <Form.Item name="fileMd5" label={t('ota.fileMD5')}>
            <Input placeholder={t('ota.fileMd5Placeholder')} />
          </Form.Item>
          <Form.Item name="changelog" label={t('ota.changelog')}>
            <Input.TextArea rows={3} placeholder={t('ota.inputChangelog')} />
          </Form.Item>
          <Form.Item name="isForce" label={t('ota.forceUpdate')} valuePropName="checked">
            <Switch />
          </Form.Item>
          <Form.Item name="minSupportedVersion" label={t('ota.minVersion')}>
            <InputNumber min={0} style={{ width: '100%' }} placeholder={t('ota.minVersionPlaceholder')} />
          </Form.Item>
          <Form.Item name="rolloutPercentage" label={t('ota.rolloutPercent')} initialValue={100}>
            <Slider marks={ROLLOUT_MARKS} min={0} max={100} step={null} />
          </Form.Item>
        </Form>
      </Modal>

      {/* 灰度比例调整 Modal */}
      <Modal
        title={t('ota.adjustRollout')}
        open={rolloutModalOpen}
        onCancel={() => setRolloutModalOpen(false)}
        onOk={handleRollout}
        confirmLoading={rolloutMutation.isPending}
        destroyOnClose
      >
        {rolloutTarget && (
          <div>
            <p style={{ marginBottom: 16 }}>
              <strong>{rolloutTarget.platform === 'ios' ? 'iOS' : 'Android'} v{rolloutTarget.version_name}</strong>
              <span style={{ color: '#999', marginLeft: 8 }}>({t('ota.currentRollout')}: {rolloutTarget.rollout_percentage ?? 100}%)</span>
            </p>
            <Slider
              marks={ROLLOUT_MARKS}
              min={0}
              max={100}
              step={null}
              value={rolloutPercent}
              onChange={setRolloutPercent}
            />
            <p style={{ marginTop: 16, color: '#999', fontSize: 13 }}>
              {rolloutPercent === 100
                ? t('ota.rolloutAllUsers')
                : t('ota.rolloutPercentDesc', { percent: rolloutPercent })}
            </p>
          </div>
        )}
      </Modal>
    </div>
  )
}

export default OtaPage
