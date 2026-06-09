import React, { useState, useEffect, useCallback, useRef } from 'react'
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
  message,
  Row,
  Col,
  Tooltip,
  Empty,
  Slider,
  InputNumber,
  Descriptions,
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
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import type { UploadProps } from 'antd'
import dayjs from 'dayjs'
import { otaApi } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import type { Firmware, OtaTask, Device } from '@/types'

const { TextArea } = Input
const { Dragger } = Upload

const TASK_STATUS_MAP: Record<string, { label: string; color: string }> = {
  pending: { label: '待推送', color: '#1677ff' },
  notifying: { label: '通知中', color: '#13c2c2' },
  notified: { label: '已通知', color: '#722ed1' },
  pushing: { label: '推送中', color: '#13c2c2' },
  in_progress: { label: '升级中', color: '#1677ff' },
  completed: { label: '已完成', color: '#52c41a' },
  failed: { label: '失败', color: '#ff4d4f' },
  cancelled: { label: '已取消', color: '#d9d9d9' },
  rolled_back: { label: '已回滚', color: '#faad14' },
}

const DEVICE_STATUS_MAP: Record<string, { label: string; color: string }> = {
  pending: { label: '等待中', color: '#d9d9d9' },
  notified: { label: '已通知', color: '#722ed1' },
  downloading: { label: '下载中', color: '#1677ff' },
  upgrading: { label: '升级中', color: '#fa8c16' },
  success: { label: '成功', color: '#52c41a' },
  failed: { label: '失败', color: '#ff4d4f' },
  skipped: { label: '跳过', color: '#faad14' },
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

const PUSH_STRATEGY_MAP: Record<string, string> = {
  all_at_once: '全部同时推送',
  percentage: '按百分比灰度',
  batch: '分批推送',
}

const PERCENTAGE_MARKS: Record<number, string> = {
  10: '10%',
  25: '25%',
  50: '50%',
  75: '75%',
  100: '100%',
}

const OtaPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState('firmware')

  return (
    <div>
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        items={[
          { key: 'firmware', label: '固件管理', children: <FirmwareTab /> },
          { key: 'tasks', label: '升级任务', children: <TasksTab /> },
        ]}
      />
    </div>
  )
}

const FirmwareTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<Firmware[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [modelFilter, setModelFilter] = useState<string>()
  const [chipFilter, setChipFilter] = useState<string>()
  const [uploadOpen, setUploadOpen] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [fileList, setFileList] = useState<any[]>([])
  const [computedSha256, setComputedSha256] = useState<string>('')
  const [computingHash, setComputingHash] = useState(false)
  const [allFirmwareList, setAllFirmwareList] = useState<Firmware[]>([])
  const [form] = Form.useForm<FirmwareFormValues>()

  // 提取已有型号列表
  const modelOptions = React.useMemo(() => {
    const models = [...new Set(allFirmwareList.map((fw) => fw.model).filter(Boolean))]
    return models.map((m) => ({ label: m, value: m }))
  }, [allFirmwareList])

  // 计算下一个子版本号
  const computeNextVersion = useCallback(
    (model: string, chip: string) => {
      const matched = allFirmwareList.filter(
        (fw) => fw.model === model && fw.target_chip === chip
      )
      if (matched.length === 0) return '1.0.0'
      // 解析版本号，取最大的
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

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await otaApi.listFirmware({
        page,
        pageSize,
        model: modelFilter || undefined,
      })
      const d = res.data
      let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      if (!Array.isArray(list)) list = []
      // 前端按芯片筛选
      if (chipFilter) {
        list = list.filter((item: Firmware) => item.target_chip === chipFilter)
      }
      setData(list)
      setTotal((d?.total ?? d?.data?.total ?? list.length) as number)
    } catch {
      message.error('获取固件列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, modelFilter, chipFilter])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  // 获取全部固件（用于型号列表和版本递增）
  const fetchAllFirmware = useCallback(async () => {
    try {
      const res = await otaApi.listFirmware({ page: 1, pageSize: 1000 })
      const d = res.data
      let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      if (!Array.isArray(list)) list = []
      setAllFirmwareList(list)
    } catch {
      // 静默失败
    }
  }, [])

  const handleUpload = async () => {
    try {
      const values = await form.validateFields()
      if (fileList.length === 0) {
        message.warning('请选择固件文件')
        return
      }
      setUploading(true)
      const formData = new FormData()
      // mode="tags" 返回数组，提取第一个值
      const modelValue = Array.isArray(values.model) ? values.model[0] : values.model
      formData.append('file', fileList[0].originFileObj)
      formData.append('model', modelValue)
      formData.append('target_chip', values.targetChip)
      formData.append('version', values.version)
      formData.append('changelog', values.changelog || '')
      formData.append('is_force', String(values.forceUpdate || false))

      await otaApi.uploadFirmware(formData)
      message.success('固件上传成功')
      setUploadOpen(false)
      form.resetFields()
      setFileList([])
      fetchData()
    } catch {
      message.error('固件上传失败')
    } finally {
      setUploading(false)
    }
  }

  const handleDelete = async (id: string) => {
    try {
      await otaApi.deleteFirmware(Number(id))
      message.success('删除成功')
      fetchData()
    } catch {
      message.error('删除失败')
    }
  }

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
        setComputedSha256('计算失败')
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

  const columns: ColumnsType<Firmware> = [
    { title: '型号', dataIndex: 'model', key: 'model', width: 120 },
    {
      title: '主版本号',
      dataIndex: 'main_version',
      key: 'main_version',
      width: 100,
      render: (val: string) => <Tag color="blue">{val || '-'}</Tag>,
    },
    {
      title: '目标芯片',
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
    { title: '子版本号', dataIndex: 'version', key: 'version', width: 100 },
    {
      title: '文件大小',
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
      title: '更新日志',
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
      title: '是否强制更新',
      dataIndex: 'is_force',
      key: 'is_force',
      width: 110,
      render: (val: boolean) => (val ? <Tag color="red">强制</Tag> : <Tag>否</Tag>),
    },
    {
      title: '上传时间',
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: '操作',
      key: 'action',
      width: 80,
      render: (_: any, record: Firmware) => (
        <Popconfirm title="确认删除该固件？" onConfirm={() => handleDelete(record.id)}>
          <Button type="link" danger icon={<DeleteOutlined />} size="small" />
        </Popconfirm>
      ),
    },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<UploadOutlined />} onClick={() => { setUploadOpen(true); fetchAllFirmware() }}>
              上传固件
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="按型号筛选"
              style={{ width: 180 }}
              value={modelFilter}
              onChange={(val) => {
                setModelFilter(val)
                setPage(1)
              }}
              options={[...new Set(data.map((d) => d.model))].map((m) => ({
                label: m,
                value: m,
              }))}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="按芯片筛选"
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
            <Button icon={<ReloadOutlined />} onClick={fetchData}>
              刷新
            </Button>
          </Col>
        </Row>
      </Card>

      <Table<Firmware>
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
        title="上传固件"
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
            // 当型号或芯片变化时，自动填充子版本号
            if (changedValues.model || changedValues.targetChip) {
              // mode="tags" 返回数组，提取第一个值
              const model = Array.isArray(allValues.model) ? allValues.model[0] : allValues.model
              const { targetChip } = allValues
              if (model && targetChip) {
                const nextVersion = computeNextVersion(model, targetChip)
                form.setFieldsValue({ version: nextVersion })
              }
            }
          }}
        >
          <Form.Item name="model" label="型号" rules={[{ required: true, message: '请选择或输入型号' }]}>
            <Select
              showSearch
              allowClear
              mode="tags"
              maxCount={1}
              placeholder="选择已有型号或输入新型号"
              options={modelOptions}
              filterOption={(input, option) =>
                (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
              }
            />
          </Form.Item>
          <Form.Item name="targetChip" label="目标芯片" rules={[{ required: true, message: '请选择目标芯片' }]}>
            <Select placeholder="请选择目标芯片">
              <Select.Option value="esp">ESP (主控)</Select.Option>
              <Select.Option value="arm">ARM (电机控制)</Select.Option>
              <Select.Option value="dsp">DSP (数字信号)</Select.Option>
              <Select.Option value="bms">BMS (电池管理)</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="version" label="子版本号" rules={[{ required: true, message: '请输入子版本号' }]}>
            <Input placeholder="选择型号和芯片后自动填充" />
          </Form.Item>
          <Form.Item name="changelog" label="更新日志">
            <TextArea rows={3} placeholder="请输入更新内容" />
          </Form.Item>
          <Form.Item name="forceUpdate" label="强制更新" valuePropName="checked">
            <Switch />
          </Form.Item>
          <Form.Item label="固件文件">
            <Dragger {...uploadProps}>
              <p className="ant-upload-drag-icon">
                <InboxOutlined />
              </p>
              <p className="ant-upload-text">点击或拖拽固件文件到此区域上传</p>
              <p className="ant-upload-hint">支持 .bin 等格式，最大200MB</p>
            </Dragger>
          </Form.Item>
          {fileList.length > 0 && (
            <Form.Item label="文件大小">
              <span>{formatFileSize(fileList[0]?.originFileObj?.size || 0)}</span>
            </Form.Item>
          )}
        </Form>
      </Modal>
    </div>
  )
}

const TasksTab: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<OtaTask[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>()
  const [createOpen, setCreateOpen] = useState(false)
  const [creating, setCreating] = useState(false)
  const [firmwareList, setFirmwareList] = useState<Firmware[]>([])
  const [deviceList, setDeviceList] = useState<Device[]>([])
  const [selectedDeviceSns, setSelectedDeviceSns] = useState<string[]>([])
  const [detailOpen, setDetailOpen] = useState(false)
  const [taskDetail, setTaskDetail] = useState<TaskDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [pushStrategy, setPushStrategy] = useState<string>('all_at_once')
  const [pushPercentage, setPushPercentage] = useState<number>(100)
  const [batchSize, setBatchSize] = useState<number>(10)
  const [rollingBack, setRollingBack] = useState(false)
  const [form] = Form.useForm<TaskFormValues>()
  const pollingRef = useRef<ReturnType<typeof setInterval>>()

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await otaApi.listTasks({
        page,
        pageSize,
        status: statusFilter || undefined,
      })
      const d = res.data
      const list = d?.items ?? d?.data?.items ?? d?.data ?? []
      setData(Array.isArray(list) ? list : [])
      setTotal((d?.total ?? d?.data?.total ?? (Array.isArray(list) ? list.length : 0)) as number)
    } catch {
      message.error('获取升级任务列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, statusFilter])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  useEffect(() => {
    const loadFirmwareList = async () => {
      try {
        const res = await otaApi.getAllFirmware()
        const d = res.data
        const list = d?.data?.items ?? d?.data ?? d?.items ?? []
        setFirmwareList(Array.isArray(list) ? list : [])
      } catch {}
    }
    loadFirmwareList()
  }, [])

  const fetchTaskDetail = async (id: string) => {
    setDetailLoading(true)
    try {
      const [taskRes, devicesRes] = await Promise.all([
        otaApi.getTask(id),
        otaApi.getTaskDevices(id),
      ])
      const task = (taskRes.data?.data ?? taskRes.data ?? {}) as OtaTask
      const devicesData = devicesRes.data?.data ?? devicesRes.data
      const devices: DeviceProgress[] = Array.isArray(devicesData) ? devicesData : []
      setTaskDetail({
        ...task,
        firmwareVersion: '',
        devices,
      } as TaskDetail)
      setDetailOpen(true)

      if (task.status === 'pushing' || task.status === 'in_progress') {
        pollingRef.current = setInterval(async () => {
          try {
            const r = await otaApi.getTaskDevices(id)
            const d = r.data?.data ?? r.data
            const deviceList: DeviceProgress[] = Array.isArray(d) ? d : []
            setTaskDetail((prev) => (prev ? { ...prev, devices: deviceList } : prev))
          } catch {}
        }, 5000)
      }
    } catch {
      message.error('获取任务详情失败')
    } finally {
      setDetailLoading(false)
    }
  }

  const closeDetail = () => {
    setDetailOpen(false)
    setTaskDetail(null)
    if (pollingRef.current) {
      clearInterval(pollingRef.current)
      pollingRef.current = undefined
    }
  }

  const handleCreate = async () => {
    try {
      const values = await form.validateFields()
      if (selectedDeviceSns.length === 0) {
        message.warning('请选择至少一个设备')
        return
      }
      setCreating(true)
      await otaApi.createTask({
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
      })
      message.success('升级任务创建成功')
      setCreateOpen(false)
      form.resetFields()
      setSelectedDeviceSns([])
      setPushStrategy('all_at_once')
      setPushPercentage(100)
      setBatchSize(10)
      fetchData()
    } catch {
      message.error('创建任务失败')
    } finally {
      setCreating(false)
    }
  }

  const openCreateModal = async () => {
    setCreateOpen(true)
    try {
      const [fwRes, devRes] = await Promise.all([
        otaApi.getAllFirmware(),
        deviceApi.getAll(),
      ])
      const fwList = fwRes.data?.data?.items ?? fwRes.data?.data ?? fwRes.data?.items ?? []
      const devList = devRes.data?.data?.items ?? devRes.data?.data ?? devRes.data?.items ?? []
      setFirmwareList(Array.isArray(fwList) ? fwList : [])
      setDeviceList(Array.isArray(devList) ? devList : [])
    } catch {}
  }

  const handleExecute = async (id: string) => {
    try {
      await otaApi.executeTask(id)
      message.success('任务已开始执行')
      fetchData()
    } catch {
      message.error('执行任务失败')
    }
  }

  const handleNotify = async (id: string) => {
    try {
      await otaApi.notifyDevices(id)
      message.success('已通知设备有新版本')
      fetchData()
    } catch {
      message.error('通知设备失败')
    }
  }

  const handleCancel = async (id: string) => {
    try {
      await otaApi.cancelTask(id)
      message.success('任务已取消')
      fetchData()
      closeDetail()
    } catch {
      message.error('取消任务失败')
    }
  }

  const handleRetry = async (taskId: string, sn: string) => {
    try {
      await otaApi.retryDevice(taskId, sn)
      message.success('重试已提交')
      if (taskDetail && taskDetail.id === taskId) {
        fetchTaskDetail(taskId)
      }
    } catch {
      message.error('重试失败')
    }
  }

  const handleRollback = async (taskId: string) => {
    setRollingBack(true)
    try {
      await otaApi.rollbackTask(taskId)
      message.success('回滚指令已发送')
      fetchData()
      if (taskDetail && taskDetail.id === taskId) {
        fetchTaskDetail(taskId)
      }
    } catch {
      message.error('回滚失败')
    } finally {
      setRollingBack(false)
    }
  }

  const handleDeleteTask = async (taskId: string) => {
    try {
      await otaApi.deleteTask(taskId)
      message.success('任务已删除')
      fetchData()
      if (taskDetail && taskDetail.id === taskId) {
        setTaskDetail(null)
      }
    } catch {
      message.error('删除任务失败')
    }
  }

  const columns: ColumnsType<OtaTask> = [
    { title: '任务名称', dataIndex: 'name', key: 'name', width: 160 },
    {
      title: '固件版本',
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
      title: '推送策略',
      dataIndex: 'pushStrategy',
      key: 'pushStrategy',
      width: 120,
      render: (val: string) => PUSH_STRATEGY_MAP[val] || val || '全部同时',
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const cfg = TASK_STATUS_MAP[status] || { label: status, color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    { title: '设备总数', dataIndex: 'totalDevices', key: 'totalDevices', width: 90 },
    { title: '成功数', dataIndex: 'successCount', key: 'successCount', width: 80 },
    { title: '失败数', dataIndex: 'failedCount', key: 'failedCount', width: 80 },
    {
      title: '进度',
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
      render: (_: any, record: OtaTask) => (
        <Space>
          <Button type="link" size="small" onClick={() => fetchTaskDetail(record.id)}>
            详情
          </Button>
          {record.status === 'pending' && (
            <Popconfirm title="确认通知设备有新版本？" onConfirm={() => handleNotify(record.id)}>
              <Button type="link" size="small" icon={<PlayCircleOutlined />}>
                推送通知
              </Button>
            </Popconfirm>
          )}
          {record.status === 'notified' && (
            <Popconfirm title="确认执行升级？设备将开始下载固件" onConfirm={() => handleExecute(record.id)}>
              <Button type="link" size="small" icon={<PlayCircleOutlined />}>
                执行升级
              </Button>
            </Popconfirm>
          )}
          {(record.status === 'pushing' || record.status === 'in_progress' || record.status === 'notifying') && (
            <Popconfirm title="确认取消该任务？" onConfirm={() => handleCancel(record.id)}>
              <Button type="link" size="small" danger icon={<StopOutlined />}>
                取消
              </Button>
            </Popconfirm>
          )}
          {(record.status === 'completed' || record.status === 'failed') && (
            <Popconfirm title="确认回滚该任务？已升级的设备将恢复到旧版本" onConfirm={() => handleRollback(record.id)}>
              <Button type="link" size="small" icon={<RollbackOutlined />} loading={rollingBack}>
                回滚
              </Button>
            </Popconfirm>
          )}
          <Popconfirm title="确认删除该任务？删除后不可恢复" onConfirm={() => handleDeleteTask(record.id)}>
            <Button type="link" size="small" danger icon={<DeleteOutlined />}>
              删除
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  const deviceColumns: ColumnsType<DeviceProgress> = [
    { title: 'SN', dataIndex: 'sn', key: 'sn', width: 140 },
    { title: '旧版本', dataIndex: 'oldVersion', key: 'oldVersion', width: 100 },
    { title: '新版本', dataIndex: 'newVersion', key: 'newVersion', width: 100 },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const cfg = DEVICE_STATUS_MAP[status] || { label: status, color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '进度',
      dataIndex: 'progress',
      key: 'progress',
      width: 150,
      render: (val: number) => <Progress percent={val} size="small" />,
    },
    {
      title: '错误信息',
      dataIndex: 'errorMessage',
      key: 'errorMessage',
      ellipsis: true,
      render: (val: string) => val || '-',
    },
    {
      title: '操作',
      key: 'action',
      width: 80,
      render: (_: any, record: DeviceProgress) => (
        record.status === 'failed' && taskDetail ? (
          <Button
            type="link"
            size="small"
            icon={<RedoOutlined />}
            onClick={() => handleRetry(taskDetail.id, record.sn)}
          >
            重试
          </Button>
        ) : null
      ),
    },
  ]

  const selectedFirmware = firmwareList.find((f) => f.id === (taskDetail?.firmwareId ?? form.getFieldValue('firmwareId')))

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={openCreateModal}>
              创建任务
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="状态筛选"
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
            <Button icon={<ReloadOutlined />} onClick={fetchData}>
              刷新
            </Button>
          </Col>
        </Row>
      </Card>

      <Table<OtaTask>
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
        title="创建升级任务"
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
        confirmLoading={creating}
        destroyOnClose
        width={700}
      >
        <Form form={form} layout="vertical">
          <Form.Item name="name" label="任务名称" rules={[{ required: true, message: '请输入任务名称' }]}>
            <Input placeholder="如: 批量升级v1.0.2" />
          </Form.Item>
          <Form.Item name="firmwareId" label="选择固件" rules={[{ required: true, message: '请选择固件' }]}>
            <Select
              placeholder="选择固件版本"
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
          <Form.Item label="推送策略">
            <Select
              value={pushStrategy}
              onChange={(val) => setPushStrategy(val)}
              options={[
                { label: '全部同时推送', value: 'all_at_once' },
                { label: '按百分比灰度', value: 'percentage' },
                { label: '分批推送', value: 'batch' },
              ]}
            />
          </Form.Item>
          {pushStrategy === 'percentage' && (
            <Form.Item label="灰度百分比">
              <Slider
                marks={PERCENTAGE_MARKS}
                step={null}
                min={10}
                max={100}
                value={pushPercentage}
                onChange={(val) => setPushPercentage(val)}
              />
              <div style={{ marginTop: 4, color: '#999' }}>
                将随机选择 {pushPercentage}% 的待推送设备进行升级
              </div>
            </Form.Item>
          )}
          {pushStrategy === 'batch' && (
            <Form.Item label="每批设备数量">
              <InputNumber
                min={1}
                max={100}
                value={batchSize}
                onChange={(val) => setBatchSize(val || 10)}
                addonAfter="台/批"
              />
              <div style={{ marginTop: 4, color: '#999' }}>
                每批推送完成后等待下一批
              </div>
            </Form.Item>
          )}
          <Form.Item label="选择设备">
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
                  { title: '型号', dataIndex: 'model', key: 'model', width: 100 },
                  {
                    title: '当前固件',
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
              <Empty description="暂无设备数据" />
            )}
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title="任务详情"
        open={detailOpen}
        onClose={closeDetail}
        width={860}
        destroyOnClose
      >
        {taskDetail && (
          <div>
            <Card size="small" style={{ marginBottom: 16 }}>
              <Descriptions column={2} size="small">
                <Descriptions.Item label="任务名称">{taskDetail.name}</Descriptions.Item>
                <Descriptions.Item label="状态">
                  <Tag color={TASK_STATUS_MAP[taskDetail.status]?.color}>
                    {TASK_STATUS_MAP[taskDetail.status]?.label || taskDetail.status}
                  </Tag>
                </Descriptions.Item>
                <Descriptions.Item label="推送策略">
                  {PUSH_STRATEGY_MAP[taskDetail.pushStrategy] || taskDetail.pushStrategy || '全部同时'}
                </Descriptions.Item>
                <Descriptions.Item label="设备统计">
                  <span>总数: {taskDetail.totalDevices} </span>
                  <span style={{ color: '#52c41a', marginLeft: 8 }}>成功: {taskDetail.successCount}</span>
                  <span style={{ color: '#ff4d4f', marginLeft: 8 }}>失败: {taskDetail.failedCount}</span>
                </Descriptions.Item>
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
                  <Descriptions.Item label="下载URL">
                    <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{selectedFirmware.fileUrl}</span>
                  </Descriptions.Item>
                  <Descriptions.Item label="文件大小">{formatFileSize(selectedFirmware.fileSize)}</Descriptions.Item>
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
                <Button type="primary" icon={<PlayCircleOutlined />} onClick={() => handleExecute(taskDetail.id)}>
                  执行任务
                </Button>
              )}
              {(taskDetail.status === 'pushing' || taskDetail.status === 'in_progress') && (
                <Button danger icon={<StopOutlined />} onClick={() => handleCancel(taskDetail.id)}>
                  取消任务
                </Button>
              )}
              {(taskDetail.status === 'completed' || taskDetail.status === 'failed') && (
                <Popconfirm title="确认回滚该任务？已升级的设备将恢复到旧版本" onConfirm={() => handleRollback(taskDetail.id)}>
                  <Button icon={<RollbackOutlined />} loading={rollingBack}>
                    回滚
                  </Button>
                </Popconfirm>
              )}
            </Space>
          </div>
        )}
        {!taskDetail && !detailLoading && <Empty description="加载中..." />}
      </Drawer>
    </div>
  )
}

export default OtaPage
