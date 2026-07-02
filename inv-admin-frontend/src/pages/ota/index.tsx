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
  Typography,
  App,
  Steps,
  Radio,
  DatePicker,
  Statistic,
  Descriptions,
  Divider,
  Checkbox,
} from 'antd'
import {
  UploadOutlined,
  PlusOutlined,
  ReloadOutlined,
  DeleteOutlined,
  StopOutlined,
  RedoOutlined,
  InboxOutlined,
  RollbackOutlined,
  CloudUploadOutlined,
  AppleOutlined,
  AndroidOutlined,
  SafetyOutlined,
  RocketOutlined,
  SendOutlined,
  PlayCircleOutlined,
  CheckCircleOutlined,
  CloseCircleOutlined,
  ClockCircleOutlined,
  FileOutlined,
  AppstoreOutlined,
  DesktopOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import type { UploadProps } from 'antd'
import dayjs from 'dayjs'
import { otaApi } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import { modelApi } from '@/services/modelApi'
import { queryKeys } from '@/utils/queryKeys'
import type { Firmware, DeviceUpgrade, Device, UpgradePackage, UpgradeTask } from '@/types'
import useTranslation from '@/hooks/useTranslation'

const { TextArea } = Input
const { Dragger } = Upload
const { Title } = Typography

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

// =================== 任务状态映射 ===================
const TASK_STATUS_MAP: Record<string, { label: string; color: string }> = {
  draft: { label: '草稿', color: 'default' },
  pending: { label: '待执行', color: 'processing' },
  scheduled: { label: '定时等待', color: 'warning' },
  running: { label: '执行中', color: 'processing' },
  completed: { label: '已完成', color: 'success' },
  partial_success: { label: '部分成功', color: 'warning' },
  failed: { label: '失败', color: 'error' },
  cancelled: { label: '已取消', color: 'default' },
}

const UPGRADE_STATUS_MAP: Record<string, { label: string; color: string }> = {
  pending: { label: '待执行', color: '#1677ff' },
  downloading: { label: '下载中', color: '#13c2c2' },
  upgrading: { label: '升级中', color: '#fa8c16' },
  success: { label: '成功', color: '#52c41a' },
  failed: { label: '失败', color: '#ff4d4f' },
  cancelled: { label: '已取消', color: '#d9d9d9' },
}

// =================== 主页面 ===================
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
          { key: 'tasks', label: t('ota.upgradeTasks'), children: <UpgradeTasksTab /> },
          { key: 'firmware', label: t('ota.firmwareLibrary'), children: <FirmwareLibraryTab /> },
          { key: 'appVersion', label: t('ota.appVersionManage'), children: <AppVersionTab /> },
        ]}
      />
    </div>
  )
}

// =================== Tab 1: 升级任务 ===================
const UpgradeTasksTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>('active')
  const [createOpen, setCreateOpen] = useState(false)
  const [currentStep, setCurrentStep] = useState(0)
  const [taskType, setTaskType] = useState<'single' | 'package'>('single')
  const [selectedFirmwareId, setSelectedFirmwareId] = useState<number | null>(null)
  const [selectedPackageId, setSelectedPackageId] = useState<number | null>(null)
  const [selectedDeviceSns, setSelectedDeviceSns] = useState<string[]>([])
  const [executeMode, setExecuteMode] = useState<string>('immediate')
  const [scheduledAt, setScheduledAt] = useState<string>('')
  const [rolloutPercent, setRolloutPercent] = useState(100)
  const [taskName, setTaskName] = useState('')
  const [detailTaskId, setDetailTaskId] = useState<number | string | null>(null)
  const [detailOpen, setDetailOpen] = useState(false)

  // 查询任务列表
  const queryParams: any = { page, pageSize }
  if (statusFilter) queryParams.status = statusFilter

  const { data: tasksRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.ota.tasks(queryParams),
    queryFn: () => otaApi.listTasks(queryParams).then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      const items = d?.items ?? []
      return { items: (Array.isArray(items) ? items : []) as UpgradeTask[], total: (d?.total ?? 0) as number }
    }),
  })

  const { data: statsRes } = useQuery({
    queryKey: queryKeys.ota.taskStats(),
    queryFn: () => otaApi.getTaskStats().then((r) => r.data?.data ?? r.data ?? {}),
  })
  const stats = statsRes as any

  const { data: firmwareList = [] } = useQuery({
    queryKey: queryKeys.ota.firmwares({ all: true }),
    queryFn: () => otaApi.getAllFirmware().then((r) => {
      const d = r.data; const list = d?.data?.items ?? d?.data ?? d?.items ?? []
      return (Array.isArray(list) ? list : []) as Firmware[]
    }),
    enabled: createOpen,
  })

  const { data: packageList = [] } = useQuery({
    queryKey: queryKeys.ota.packages(),
    queryFn: () => otaApi.listPackages().then((r) => {
      const d = r.data?.data ?? r.data ?? []
      return (Array.isArray(d) ? d : []) as UpgradePackage[]
    }),
    enabled: createOpen,
  })

  const { data: deviceList = [] } = useQuery({
    queryKey: ['devices', 'all'],
    queryFn: () => deviceApi.getAll().then((r) => {
      const d = r.data; const list = d?.data?.items ?? d?.data ?? d?.items ?? []
      return (Array.isArray(list) ? list : []) as Device[]
    }),
    enabled: createOpen,
  })

  // 任务详情 - 设备列表
  const { data: taskDevices = [], isLoading: devicesLoading } = useQuery({
    queryKey: queryKeys.ota.taskDevices(detailTaskId ?? 0),
    queryFn: () => otaApi.getTaskDevices(detailTaskId!).then((r) => {
      const payload = r.data?.data ?? r.data ?? {}
      const d = payload?.items ?? (Array.isArray(payload) ? payload : [])
      return d as DeviceUpgrade[]
    }),
    enabled: detailOpen && !!detailTaskId,
    refetchInterval: 5000,
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })

  const createMutation = useMutation({
    mutationFn: (data: any) => otaApi.createTask(data),
    onSuccess: () => {
      message.success(t('ota.taskCreated'))
      resetCreateForm()
      invalidate()
    },
    onError: (err: any) => message.error(t('ota.taskCreateError') + ': ' + (err?.response?.data?.message || err?.message || '')),
  })

  const executeMutation = useMutation({
    mutationFn: (id: number | string) => otaApi.executeTask(id),
    onSuccess: () => { message.success(t('ota.taskExecuted')); invalidate() },
    onError: () => message.error(t('ota.taskExecuteError')),
  })

  const cancelMutation = useMutation({
    mutationFn: (id: number | string) => otaApi.cancelTask(id),
    onSuccess: () => { message.success(t('ota.taskCancelled')); invalidate() },
    onError: () => message.error(t('ota.taskCancelError')),
  })

  const retryMutation = useMutation({
    mutationFn: (id: number | string) => otaApi.retryTask(id),
    onSuccess: () => { message.success(t('ota.taskRetried')); invalidate() },
    onError: () => message.error(t('ota.taskRetryError')),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number | string) => otaApi.deleteTask(id),
    onSuccess: () => { message.success(t('ota.taskDeleted')); invalidate() },
    onError: () => message.error(t('ota.taskDeleteError')),
  })

  const resetCreateForm = () => {
    setCreateOpen(false)
    setCurrentStep(0)
    setTaskType('single')
    setSelectedFirmwareId(null)
    setSelectedPackageId(null)
    setSelectedDeviceSns([])
    setExecuteMode('immediate')
    setScheduledAt('')
    setRolloutPercent(100)
    setTaskName('')
  }

  const handleSubmitTask = () => {
    if (selectedDeviceSns.length === 0) { message.warning(t('ota.pleaseSelectDevice')); return }
    const data: any = {
      name: taskName || undefined,
      task_type: taskType,
      device_sns: selectedDeviceSns,
      execute_mode: executeMode,
      rollout_percent: rolloutPercent,
    }
    if (taskType === 'single') data.firmware_id = selectedFirmwareId
    else data.package_id = selectedPackageId
    if (executeMode === 'scheduled' && scheduledAt) data.scheduled_at = scheduledAt
    createMutation.mutate(data)
  }

  // 根据任务类型和选择获取目标型号
  const targetModel = useMemo(() => {
    if (taskType === 'single' && selectedFirmwareId) {
      return firmwareList.find((f) => Number(f.id) === selectedFirmwareId)?.model || ''
    }
    if (taskType === 'package' && selectedPackageId) {
      return packageList.find((p) => Number(p.id) === selectedPackageId)?.model || ''
    }
    return ''
  }, [taskType, selectedFirmwareId, selectedPackageId, firmwareList, packageList])

  // 根据型号筛选设备
  const filteredDevices = useMemo(() => {
    if (!targetModel) return deviceList
    return deviceList.filter((d) => d.model === targetModel)
  }, [deviceList, targetModel])

  const targetVersion = useMemo(() => {
    if (taskType === 'single' && selectedFirmwareId) {
      const fw = firmwareList.find((f) => Number(f.id) === selectedFirmwareId)
      return fw ? (fw.main_version || fw.version) : ''
    }
    if (taskType === 'package' && selectedPackageId) {
      const pkg = packageList.find((p) => Number(p.id) === selectedPackageId)
      return pkg ? pkg.main_version : ''
    }
    return ''
  }, [taskType, selectedFirmwareId, selectedPackageId, firmwareList, packageList])

  const canNext = () => {
    if (currentStep === 0) {
      return taskType === 'single' ? !!selectedFirmwareId : !!selectedPackageId
    }
    if (currentStep === 1) return selectedDeviceSns.length > 0
    return true
  }

  const tasksData = tasksRes?.items ?? []
  const tasksTotal = tasksRes?.total ?? 0

  // 任务列表列
  const columns: ColumnsType<UpgradeTask> = [
    {
      title: t('ota.taskName'), dataIndex: 'name', key: 'name', width: 160, ellipsis: true,
      render: (val: string, record: UpgradeTask) => val || `#${record.id}`,
    },
    {
      title: t('ota.upgradeType'), key: 'task_type', width: 90,
      render: (_: any, r: UpgradeTask) => (
        <Tag color={r.task_type === 'package' ? 'purple' : 'blue'}>
          {r.task_type === 'package' ? t('ota.packageMode') : t('ota.singleChip')}
        </Tag>
      ),
    },
    { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 100 },
    { title: t('ota.targetVersion'), dataIndex: 'target_version', key: 'target_version', width: 110 },
    { title: t('ota.deviceTotal'), dataIndex: 'total_devices', key: 'total_devices', width: 80 },
    {
      title: t('ota.progress'), key: 'progress', width: 180,
      render: (_: any, r: UpgradeTask) => {
        const total = r.total_devices || 0
        const done = (r.success_count || 0) + (r.failed_count || 0)
        const pct = total > 0 ? Math.round((done / total) * 100) : 0
        return (
          <Space>
            <Progress percent={pct} size="small" style={{ width: 80 }} />
            <span style={{ fontSize: 12, color: '#999' }}>
              <span style={{ color: '#52c41a' }}>{r.success_count}</span>/
              <span style={{ color: '#ff4d4f' }}>{r.failed_count}</span>/
              {total}
            </span>
          </Space>
        )
      },
    },
    {
      title: t('common.status'), key: 'status', width: 100,
      render: (_: any, r: UpgradeTask) => {
        const cfg = TASK_STATUS_MAP[r.status] || { label: r.status, color: 'default' }
        const i18nKey = `ota.taskStatus${r.status.charAt(0).toUpperCase() + r.status.slice(1).replace(/_(\w)/g, (_: string, c: string) => c.toUpperCase())}`
        const translated = t(i18nKey)
        return <Tag color={cfg.color}>{translated !== i18nKey ? translated : cfg.label}</Tag>
      },
    },
    {
      title: t('ota.executeMode'), key: 'execute_mode', width: 90,
      render: (_: any, r: UpgradeTask) => {
        const modeMap: Record<string, string> = { immediate: t('ota.executeModeImmediate'), scheduled: t('ota.executeModeScheduled'), manual: t('ota.executeModeManual') }
        return modeMap[r.execute_mode] || r.execute_mode
      },
    },
    {
      title: t('common.operation'), key: 'action', width: 220, fixed: 'right',
      render: (_: any, r: UpgradeTask) => (
        <Space size={4}>
          <Button type="link" size="small" onClick={() => { setDetailTaskId(r.id); setDetailOpen(true) }}>
            {t('ota.detail')}
          </Button>
          {(r.status === 'pending' || r.status === 'draft') && (
            <Popconfirm title={t('ota.confirmExecuteTask')} onConfirm={() => executeMutation.mutate(r.id)}>
              <Button type="link" size="small" icon={<PlayCircleOutlined />}>{t('ota.execute')}</Button>
            </Popconfirm>
          )}
          {['pending', 'scheduled', 'running', 'draft'].includes(r.status) && (
            <Popconfirm title={t('ota.confirmCancelTask')} onConfirm={() => cancelMutation.mutate(r.id)}>
              <Button type="link" size="small" danger icon={<StopOutlined />}>{t('ota.cancel')}</Button>
            </Popconfirm>
          )}
          {(r.status === 'failed' || r.status === 'partial_success') && (
            <Popconfirm title={t('ota.confirmRetryTask')} onConfirm={() => retryMutation.mutate(r.id)}>
              <Button type="link" size="small" icon={<RedoOutlined />}>{t('ota.retry')}</Button>
            </Popconfirm>
          )}
          {['completed', 'cancelled', 'failed', 'draft'].includes(r.status) && (
            <Popconfirm title={t('ota.confirmDeleteTaskNew')} onConfirm={() => deleteMutation.mutate(r.id)}>
              <Button type="link" size="small" danger icon={<DeleteOutlined />}>{t('ota.delete')}</Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ]

  // 设备升级详情列
  const detailColumns: ColumnsType<DeviceUpgrade> = [
    { title: 'SN', dataIndex: 'device_sn', key: 'device_sn', width: 140 },
    {
      title: t('ota.currentFirmware'), key: 'current_firmware', width: 180,
      render: (_: any, r: DeviceUpgrade) => {
        const parts: string[] = []
        if (r.current_arm_version) parts.push(`ARM: ${r.current_arm_version}`)
        if (r.current_esp_version) parts.push(`ESP: ${r.current_esp_version}`)
        return parts.length > 0 ? parts.join(' / ') : '-'
      },
    },
    { title: t('ota.oldVersion'), dataIndex: 'old_version', key: 'old_version', width: 100 },
    { title: t('ota.targetVersion'), dataIndex: 'firmware_version', key: 'firmware_version', width: 100 },
    {
      title: t('common.status'), dataIndex: 'status', key: 'status', width: 100,
      render: (s: string) => { const c = UPGRADE_STATUS_MAP[s] || { label: s, color: '#d9d9d9' }; return <Tag color={c.color}>{c.label}</Tag> },
    },
    {
      title: t('ota.progress'), dataIndex: 'progress', key: 'progress', width: 150,
      render: (val: number) => <Progress percent={val} size="small" />,
    },
    {
      title: t('ota.errorInfo'), dataIndex: 'error_message', key: 'error_message', ellipsis: true,
      render: (val: string) => val || '-',
    },
  ]

  return (
    <div>
      {/* 统计卡片 */}
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <Card bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statPending')} value={stats?.pending ?? 0} prefix={<ClockCircleOutlined />} valueStyle={{ color: '#1677ff' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statRunning')} value={stats?.running ?? 0} prefix={<RocketOutlined />} valueStyle={{ color: '#fa8c16' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statCompletedToday')} value={stats?.completed_today ?? 0} prefix={<CheckCircleOutlined />} valueStyle={{ color: '#52c41a' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statFailed')} value={stats?.failed ?? 0} prefix={<CloseCircleOutlined />} valueStyle={{ color: '#ff4d4f' }} />
          </Card>
        </Col>
      </Row>

      {/* 工具栏 */}
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateOpen(true)}>
              {t('ota.createUpgradeTask')}
            </Button>
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByStatus')}
              style={{ width: 140 }}
              value={statusFilter}
              onChange={(val) => { setStatusFilter(val); setPage(1) }}
              options={[
                { label: t('ota.taskStatusActive') || '进行中', value: 'active' },
                { label: t('ota.taskStatusPending'), value: 'pending' },
                { label: t('ota.taskStatusRunning'), value: 'running' },
                { label: t('ota.taskStatusCompleted'), value: 'completed' },
                { label: t('ota.taskStatusFailed'), value: 'failed' },
                { label: t('ota.taskStatusCancelled'), value: 'cancelled' },
              ]}
            />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
        </Row>
      </Card>

      {/* 任务列表 */}
      <Table<UpgradeTask>
        rowKey="id"
        columns={columns}
        dataSource={tasksData}
        loading={isLoading}
        size="small"
        scroll={{ x: 1200 }}
        pagination={{
          current: page, pageSize, total: tasksTotal, showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      {/* 创建升级任务 Modal (向导式) */}
      <Modal
        title={t('ota.createUpgradeTask')}
        open={createOpen}
        onCancel={resetCreateForm}
        width={780}
        destroyOnClose
        footer={[
          <Button key="cancel" onClick={resetCreateForm}>{t('ota.cancel')}</Button>,
          currentStep > 0 && <Button key="prev" onClick={() => setCurrentStep(currentStep - 1)}>{t('ota.prev')}</Button>,
          currentStep < 2 && <Button key="next" type="primary" disabled={!canNext()} onClick={() => setCurrentStep(currentStep + 1)}>{t('ota.next')}</Button>,
          currentStep === 2 && <Button key="submit" type="primary" loading={createMutation.isPending} onClick={handleSubmitTask}>{t('ota.submit')}</Button>,
        ].filter(Boolean)}
      >
        <Steps
          current={currentStep}
          style={{ marginBottom: 24 }}
          items={[
            { title: t('ota.selectTargetContent') },
            { title: t('ota.selectTargetDevices') },
            { title: t('ota.executionStrategy') },
          ]}
        />

        {/* Step 1: 选择升级内容 */}
        {currentStep === 0 && (
          <div>
            <Form.Item label={t('ota.taskName')} style={{ marginBottom: 16 }}>
              <Input
                value={taskName}
                onChange={(e) => setTaskName(e.target.value)}
                placeholder={t('ota.taskNamePlaceholder')}
              />
            </Form.Item>
            <Form.Item label={t('ota.taskType')} required style={{ marginBottom: 16 }}>
              <Radio.Group value={taskType} onChange={(e) => { setTaskType(e.target.value); setSelectedFirmwareId(null); setSelectedPackageId(null) }}>
                <Radio.Button value="single"><FileOutlined /> {t('ota.taskTypeSingle')}</Radio.Button>
                <Radio.Button value="package"><AppstoreOutlined /> {t('ota.taskTypePackage')}</Radio.Button>
              </Radio.Group>
            </Form.Item>
            {taskType === 'single' ? (
              <Form.Item label={t('ota.selectFirmware')} required>
                <Select
                  placeholder={t('ota.selectFirmwareVersion')}
                  value={selectedFirmwareId}
                  onChange={setSelectedFirmwareId}
                  showSearch
                  filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())}
                  options={firmwareList.map((fw) => ({
                    label: `${fw.model} - ${fw.main_version || 'v' + fw.version} [${(fw.target_chip || 'esp').toUpperCase()}]`,
                    value: Number(fw.id),
                  }))}
                />
              </Form.Item>
            ) : (
              <Form.Item label={t('ota.selectFirmware')} required>
                <Select
                  placeholder={t('ota.selectFirmwareVersion')}
                  value={selectedPackageId}
                  onChange={setSelectedPackageId}
                  options={packageList.map((pkg) => ({
                    label: `${pkg.model} - ${pkg.main_version}`,
                    value: Number(pkg.id),
                  }))}
                />
              </Form.Item>
            )}
            {targetModel && (
              <Descriptions column={2} size="small" bordered>
                <Descriptions.Item label={t('ota.model')}>{targetModel}</Descriptions.Item>
                <Descriptions.Item label={t('ota.targetVersion')}>{targetVersion}</Descriptions.Item>
              </Descriptions>
            )}
          </div>
        )}

        {/* Step 2: 选择目标设备 */}
        {currentStep === 1 && (
          <div>
            <div style={{ marginBottom: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span>{t('ota.selectedCount', { count: selectedDeviceSns.length })}</span>
              <Checkbox
                checked={selectedDeviceSns.length === filteredDevices.length && filteredDevices.length > 0}
                indeterminate={selectedDeviceSns.length > 0 && selectedDeviceSns.length < filteredDevices.length}
                onChange={(e) => setSelectedDeviceSns(e.target.checked ? filteredDevices.map((d) => d.sn) : [])}
              >
                {t('ota.selectAll')}
              </Checkbox>
            </div>
            <Table<Device>
              rowKey="sn"
              size="small"
              rowSelection={{
                selectedRowKeys: selectedDeviceSns,
                onChange: (keys) => setSelectedDeviceSns(keys as string[]),
              }}
              dataSource={filteredDevices}
              columns={[
                { title: 'SN', dataIndex: 'sn', key: 'sn', width: 140 },
                { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 100 },
                { title: t('ota.currentVersion'), dataIndex: 'firmwareVersion', key: 'firmwareVersion', width: 120, render: (v: string) => v || '-' },
              ]}
              pagination={{ pageSize: 8, size: 'small' }}
              scroll={{ y: 350 }}
              locale={{ emptyText: <Empty description={t('ota.noDeviceData')} /> }}
            />
          </div>
        )}

        {/* Step 3: 执行策略 */}
        {currentStep === 2 && (
          <div>
            <Form.Item label={t('ota.executeMode')} style={{ marginBottom: 16 }}>
              <Radio.Group value={executeMode} onChange={(e) => setExecuteMode(e.target.value)}>
                <Radio.Button value="immediate">
                  <RocketOutlined /> {t('ota.executeModeImmediate')}
                </Radio.Button>
                <Radio.Button value="scheduled">
                  <ClockCircleOutlined /> {t('ota.executeModeScheduled')}
                </Radio.Button>
                <Radio.Button value="manual">
                  <SafetyOutlined /> {t('ota.executeModeManual')}
                </Radio.Button>
              </Radio.Group>
              <div style={{ color: '#999', fontSize: 12, marginTop: 4 }}>
                {executeMode === 'immediate' && t('ota.executeModeImmediateDesc')}
                {executeMode === 'scheduled' && t('ota.executeModeScheduledDesc')}
                {executeMode === 'manual' && t('ota.executeModeManualDesc')}
              </div>
            </Form.Item>
            {executeMode === 'scheduled' && (
              <Form.Item label={t('ota.scheduledTime')} style={{ marginBottom: 16 }}>
                <DatePicker
                  showTime
                  style={{ width: '100%' }}
                  onChange={(val) => setScheduledAt(val ? val.toISOString() : '')}
                />
              </Form.Item>
            )}
            <Form.Item label={t('ota.rolloutPercentLabel')} style={{ marginBottom: 16 }}>
              <Slider min={1} max={100} value={rolloutPercent} onChange={setRolloutPercent}
                marks={{ 1: '1%', 25: '25%', 50: '50%', 75: '75%', 100: '100%' }} />
              <div style={{ color: '#999', fontSize: 12 }}>{t('ota.rolloutPercentHint')}</div>
            </Form.Item>
            <Divider />
            <Descriptions title={t('ota.taskSummary')} column={2} size="small" bordered>
              <Descriptions.Item label={t('ota.taskName')}>{taskName || '-'}</Descriptions.Item>
              <Descriptions.Item label={t('ota.upgradeType')}>
                <Tag color={taskType === 'package' ? 'purple' : 'blue'}>
                  {taskType === 'package' ? t('ota.packageMode') : t('ota.singleChip')}
                </Tag>
              </Descriptions.Item>
              <Descriptions.Item label={t('ota.model')}>{targetModel}</Descriptions.Item>
              <Descriptions.Item label={t('ota.targetVersion')}>{targetVersion}</Descriptions.Item>
              <Descriptions.Item label={t('ota.selectedDevicesCount')}>{selectedDeviceSns.length}</Descriptions.Item>
              <Descriptions.Item label={t('ota.executeMode')}>
                {executeMode === 'immediate' ? t('ota.executeModeImmediate') : executeMode === 'scheduled' ? t('ota.executeModeScheduled') : t('ota.executeModeManual')}
              </Descriptions.Item>
              <Descriptions.Item label={t('ota.rolloutPercentLabel')} span={2}>{rolloutPercent}%</Descriptions.Item>
            </Descriptions>
          </div>
        )}
      </Modal>

      {/* 任务详情 Drawer */}
      <Drawer
        title={t('ota.taskDevices')}
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={900}
        destroyOnClose
        extra={<Button icon={<ReloadOutlined />} size="small" onClick={() => queryClient.invalidateQueries({ queryKey: queryKeys.ota.taskDevices(detailTaskId ?? 0) })} />}
      >
        <Table<DeviceUpgrade>
          rowKey={(r) => `${r.device_sn}-${r.firmware_id}`}
          columns={detailColumns}
          dataSource={taskDevices}
          loading={devicesLoading}
          size="small"
          scroll={{ x: 900 }}
          pagination={false}
        />
      </Drawer>
    </div>
  )
}

// =================== Tab 2: 固件库 (合并固件管理+升级包) ===================
const FirmwareLibraryTab: React.FC = () => {
  const { t } = useTranslation()
  return (
    <Tabs
      defaultActiveKey="firmwareFiles"
      items={[
        { key: 'firmwareFiles', label: t('ota.firmwareFiles'), children: <FirmwareTab /> },
        { key: 'packageTemplates', label: t('ota.packageTemplates'), children: <PackagesTab /> },
      ]}
    />
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
  const [, setComputingHash] = useState(false)
  const [form] = Form.useForm<FirmwareFormValues>()

  // 查看使用该固件的设备 Modal 状态
  const [fwDevicesOpen, setFwDevicesOpen] = useState(false)
  const [fwDevicesTarget, setFwDevicesTarget] = useState<Firmware | null>(null)
  const [fwDevices, setFwDevices] = useState<any[]>([])
  const [fwDevicesLoading, setFwDevicesLoading] = useState(false)

  const openFwDevicesModal = async (record: Firmware) => {
    setFwDevicesTarget(record)
    setFwDevicesOpen(true)
    setFwDevicesLoading(true)
    try {
      const res = await otaApi.getDevicesByFirmware(record.model, record.target_chip, record.version)
      const d = res.data?.data ?? res.data ?? {}
      const list = d?.devices ?? []
      setFwDevices(Array.isArray(list) ? list : [])
    } catch (err: any) {
      message.error('查询设备列表失败: ' + (err?.response?.data?.message || err?.message || ''))
      setFwDevices([])
    } finally {
      setFwDevicesLoading(false)
    }
  }

  const queryParams = { page, pageSize, model: modelFilter || undefined }

  const { data: firmwareRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.ota.firmwares(queryParams),
    queryFn: () => otaApi.listFirmware(queryParams).then((r) => {
      const d = r.data
      let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      if (!Array.isArray(list)) list = []
      if (chipFilter) list = list.filter((item: Firmware) => item.target_chip === chipFilter)
      return { items: list as Firmware[], total: (d?.total ?? d?.data?.total ?? list.length) as number }
    }),
  })

  const { data: allFirmwareList = [] } = useQuery({
    queryKey: queryKeys.ota.firmwares({ all: true }),
    queryFn: () => otaApi.listFirmware({ page: 1, pageSize: 1000 }).then((r) => {
      const d = r.data; let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      return (Array.isArray(list) ? list : []) as Firmware[]
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
      setUploadOpen(false); form.resetFields(); setFileList([])
      queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
    },
    onError: () => message.error(t('ota.firmwareUploadFailed')),
    onSettled: () => setUploading(false),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => otaApi.deleteFirmware(Number(id)),
    onSuccess: () => { message.success(t('ota.firmwareDeleteSuccess')); queryClient.invalidateQueries({ queryKey: queryKeys.ota.all }) },
    onError: () => message.error(t('ota.firmwareDeleteFailed')),
  })

  const handleUpload = async () => {
    try {
      const values = await form.validateFields()
      if (fileList.length === 0) { message.warning(t('ota.pleaseSelectFirmware')); return }
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
    } catch { setUploading(false) }
  }

  const computeNextVersion = useCallback((model: string, chip: string) => {
    const matched = allFirmwareList.filter((fw) => fw.model === model && fw.target_chip === chip)
    if (matched.length === 0) return '1.0.0'
    const versions = matched.map((fw) => fw.version).filter(Boolean).map((v) => {
      const parts = v.split('.').map(Number); return { major: parts[0] || 0, minor: parts[1] || 0, patch: parts[2] || 0 }
    }).sort((a, b) => { if (a.major !== b.major) return b.major - a.major; if (a.minor !== b.minor) return b.minor - a.minor; return b.patch - a.patch })
    if (versions.length === 0) return '1.0.0'
    const latest = versions[0]; return `${latest.major}.${latest.minor}.${latest.patch + 1}`
  }, [allFirmwareList])

  const modelOptions = useMemo(() => {
    const firmwareModels = allFirmwareList.map((fw) => fw.model).filter(Boolean)
    const deviceModelNames = deviceModels.map((m: any) => m.model_code || m.model_name).filter(Boolean)
    return [...new Set([...firmwareModels, ...deviceModelNames])].map((m) => ({ label: m, value: m }))
  }, [allFirmwareList, deviceModels])

  const uploadProps: UploadProps = {
    accept: '.bin', maxCount: 1, fileList,
    beforeUpload: async (file) => {
      setComputingHash(true)
      try { await computeSha256(file) } catch { /* ignore */ }
      finally { setComputingHash(false) }
      setFileList([{ uid: '-1', name: file.name, status: 'done', originFileObj: file }])
      return false
    },
    onRemove: () => { setFileList([]) },
  }

  const firmwareData = firmwareRes?.items ?? []
  const firmwareTotal = firmwareRes?.total ?? 0

  const columns: ColumnsType<Firmware> = [
    { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 120 },
    {
      title: t('ota.targetChip'), dataIndex: 'target_chip', key: 'target_chip', width: 90,
      render: (val: string) => {
        const chipMap: Record<string, { label: string; color: string }> = { esp: { label: 'ESP', color: 'green' }, arm: { label: 'ARM', color: 'blue' }, dsp: { label: 'DSP', color: 'orange' }, bms: { label: 'BMS', color: 'purple' } }
        const chip = chipMap[val] || { label: val || '-', color: 'default' }
        return <Tag color={chip.color}>{chip.label}</Tag>
      },
    },
    { title: t('ota.subVersion'), dataIndex: 'version', key: 'version', width: 100 },
    { title: t('ota.fileSize'), dataIndex: 'file_size', key: 'file_size', width: 100, render: (size: number) => formatFileSize(size) },
    { title: 'MD5', dataIndex: 'file_md5', key: 'file_md5', width: 180, ellipsis: true, render: (val: string) => <Tooltip title={val}><span style={{ fontFamily: 'monospace', fontSize: 12 }}>{val}</span></Tooltip> },
    { title: t('ota.changelog'), dataIndex: 'changelog', key: 'changelog', ellipsis: true, render: (val: string) => <Tooltip title={val}><span>{val || '-'}</span></Tooltip> },
    { title: t('ota.forceUpdate'), dataIndex: 'is_force', key: 'is_force', width: 110, render: (val: boolean) => val ? <Tag color="red">{t('ota.force')}</Tag> : <Tag>{t('common.no')}</Tag> },
    { title: t('ota.uploadTime'), dataIndex: 'created_at', key: 'created_at', width: 170, render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss') },
    {
      title: t('common.operation'), key: 'action', width: 140,
      render: (_: any, record: Firmware) => (
        <Space size={4}>
          <Tooltip title="查看使用该固件的设备">
            <Button type="link" size="small" icon={<DesktopOutlined />} onClick={() => openFwDevicesModal(record)}>
              查看设备
            </Button>
          </Tooltip>
          <Popconfirm title={t('ota.confirmDeleteFirmware')} onConfirm={() => deleteMutation.mutate(record.id)}>
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
          <Col><Button type="primary" icon={<UploadOutlined />} onClick={() => setUploadOpen(true)}>{t('ota.uploadFirmware')}</Button></Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByModel')} style={{ width: 180 }} value={modelFilter}
              onChange={(val) => { setModelFilter(val); setPage(1) }}
              options={[...new Set(firmwareData.map((d) => d.model))].map((m) => ({ label: m, value: m }))} />
          </Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByChip')} style={{ width: 140 }} value={chipFilter}
              onChange={(val) => { setChipFilter(val); setPage(1) }}
              options={[{ label: 'ESP', value: 'esp' }, { label: 'ARM', value: 'arm' }, { label: 'DSP', value: 'dsp' }, { label: 'BMS', value: 'bms' }]} />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
        </Row>
      </Card>
      <Table<Firmware> rowKey="id" columns={columns} dataSource={firmwareData} loading={isLoading} size="small"
        pagination={{ current: page, pageSize, total: firmwareTotal, showSizeChanger: true, showTotal: (total) => t('common.total', { total }), onChange: (p, ps) => { setPage(p); setPageSize(ps) } }} />

      <Modal title={t('ota.uploadFirmwareTitle')} open={uploadOpen}
        onCancel={() => { setUploadOpen(false); form.resetFields(); setFileList([]) }}
        onOk={handleUpload} confirmLoading={uploading} destroyOnClose width={560}>
        <Form form={form} layout="vertical"
          onValuesChange={(changedValues, allValues) => {
            if (changedValues.model || changedValues.targetChip) {
              const model = Array.isArray(allValues.model) ? allValues.model[0] : allValues.model
              const { targetChip } = allValues
              if (model && targetChip) form.setFieldsValue({ version: computeNextVersion(model, targetChip) })
            }
          }}>
          <Form.Item name="model" label={t('ota.model')} rules={[{ required: true, message: t('ota.pleaseSelectOrInputModel') }]}>
            <Select showSearch allowClear mode="tags" maxCount={1} placeholder={t('ota.selectOrInputModel')} options={modelOptions}
              filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())} />
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
          <Form.Item name="changelog" label={t('ota.changelog')}><TextArea rows={3} placeholder={t('ota.inputChangelog')} /></Form.Item>
          <Form.Item name="forceUpdate" label={t('ota.forceUpdate')} valuePropName="checked"><Switch /></Form.Item>
          <Form.Item label={t('ota.firmwareFile')}>
            <Dragger {...uploadProps}>
              <p className="ant-upload-drag-icon"><InboxOutlined /></p>
              <p className="ant-upload-text">{t('ota.dragFirmware')}</p>
              <p className="ant-upload-hint">{t('ota.firmwareFormat')}</p>
            </Dragger>
          </Form.Item>
          {fileList.length > 0 && <Form.Item label={t('ota.fileSizeLabel')}><span>{formatFileSize(fileList[0]?.originFileObj?.size || 0)}</span></Form.Item>}
        </Form>
      </Modal>

      {/* 查看使用该固件的设备 Modal */}
      <Modal
        title="使用该固件的设备"
        open={fwDevicesOpen}
        onCancel={() => { setFwDevicesOpen(false); setFwDevicesTarget(null); setFwDevices([]) }}
        width={780}
        destroyOnClose
        footer={[
          <Button key="close" onClick={() => { setFwDevicesOpen(false); setFwDevicesTarget(null); setFwDevices([]) }}>
            关闭
          </Button>,
        ]}
      >
        {fwDevicesTarget && (
          <div>
            <Descriptions column={3} size="small" bordered style={{ marginBottom: 16 }}>
              <Descriptions.Item label="型号">{fwDevicesTarget.model}</Descriptions.Item>
              <Descriptions.Item label="芯片">
                <Tag color="blue">{(fwDevicesTarget.target_chip || '').toUpperCase()}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="版本">{fwDevicesTarget.version}</Descriptions.Item>
            </Descriptions>
            <Table
              rowKey="sn"
              size="small"
              loading={fwDevicesLoading}
              dataSource={fwDevices}
              pagination={{ pageSize: 10 }}
              locale={{ emptyText: <Empty description="暂无设备使用该固件版本" /> }}
              columns={[
                { title: '设备 SN', dataIndex: 'sn', key: 'sn', width: 140 },
                { title: '型号', dataIndex: 'model', key: 'model', width: 100 },
                { title: '主版本', dataIndex: 'main_version', key: 'main_version', width: 120, render: (v: string) => v || '-' },
                { title: 'ARM', dataIndex: 'firmware_arm', key: 'firmware_arm', width: 110, render: (v: string) => v || '-' },
                { title: 'ESP', dataIndex: 'firmware_esp', key: 'firmware_esp', width: 110, render: (v: string) => v || '-' },
                { title: 'DSP', dataIndex: 'firmware_dsp', key: 'firmware_dsp', width: 110, render: (v: string) => v || '-' },
                { title: 'BMS', dataIndex: 'firmware_bms', key: 'firmware_bms', width: 110, render: (v: string) => v || '-' },
              ]}
            />
          </div>
        )}
      </Modal>
    </div>
  )
}

// =================== 升级包组合 (固件库子Tab，去掉推送按钮) ===================
const PackagesTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const [createOpen, setCreateOpen] = useState(false)
  const [createForm] = Form.useForm()
  const [modelFilter, setModelFilter] = useState<string>()

  // 安装到设备 Modal 状态
  const [installOpen, setInstallOpen] = useState(false)
  const [installPkg, setInstallPkg] = useState<UpgradePackage | null>(null)
  const [installSnInput, setInstallSnInput] = useState('')

  // 查看已安装该升级包的设备 Modal 状态
  const [pkgDevicesOpen, setPkgDevicesOpen] = useState(false)
  const [pkgDevicesTarget, setPkgDevicesTarget] = useState<UpgradePackage | null>(null)
  const [pkgDevices, setPkgDevices] = useState<DeviceUpgrade[]>([])
  const [pkgDevicesLoading, setPkgDevicesLoading] = useState(false)

  const openPkgDevicesModal = async (record: UpgradePackage) => {
    setPkgDevicesTarget(record)
    setPkgDevicesOpen(true)
    setPkgDevicesLoading(true)
    try {
      const res = await otaApi.getUpgradePackageDevices(Number(record.id))
      const d = res.data?.data ?? res.data ?? {}
      const list = d?.devices ?? []
      setPkgDevices(Array.isArray(list) ? list : [])
    } catch (err: any) {
      message.error('查询设备列表失败: ' + (err?.response?.data?.message || err?.message || ''))
      setPkgDevices([])
    } finally {
      setPkgDevicesLoading(false)
    }
  }

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })

  const installMutation = useMutation({
    mutationFn: (data: { package_id: number; device_sns: string[]; immediate?: boolean }) =>
      otaApi.pushPackageUpgrade({ ...data, rollout_percent: 100 }),
    onSuccess: () => {
      message.success('升级指令已下发')
      setInstallOpen(false)
      setInstallPkg(null)
      setInstallSnInput('')
      invalidate()
    },
    onError: (err: any) => {
      message.error('升级指令下发失败: ' + (err?.response?.data?.message || err?.message || ''))
    },
  })

  const handleInstallSubmit = () => {
    if (!installPkg) return
    const sns = installSnInput
      .split(/[,，\s]+/)
      .map((s) => s.trim())
      .filter(Boolean)
    if (sns.length === 0) {
      message.warning('请输入设备 SN')
      return
    }
    installMutation.mutate({ package_id: Number(installPkg.id), device_sns: sns, immediate: true })
  }

  const openInstallModal = (record: UpgradePackage) => {
    setInstallPkg(record)
    setInstallSnInput('')
    setInstallOpen(true)
  }

  const { data: packagesRes, isLoading } = useQuery({
    queryKey: queryKeys.ota.packages(modelFilter ? { model: modelFilter } : undefined),
    queryFn: () => otaApi.listPackages(modelFilter ? { model: modelFilter } : {}).then((r) => r.data?.data ?? r.data ?? []),
  })
  const packages = (Array.isArray(packagesRes) ? packagesRes : []) as UpgradePackage[]

  const { data: firmwareRes } = useQuery({
    queryKey: queryKeys.ota.firmwares(),
    queryFn: () => otaApi.getAllFirmware().then((r) => r.data?.data ?? r.data ?? []),
  })
  const firmwareList = (Array.isArray(firmwareRes) ? firmwareRes : []) as Firmware[]

  const { data: modelsRes } = useQuery({
    queryKey: queryKeys.models.list(),
    queryFn: () => modelApi.listModels().then((r) => r.data?.data ?? r.data ?? []),
  })
  const modelList = (Array.isArray(modelsRes) ? modelsRes : (modelsRes as any)?.items ?? []) as any[]

  const createMutation = useMutation({
    mutationFn: (data: any) => otaApi.createPackage(data),
    onSuccess: () => { message.success(t('ota.packageCreated')); setCreateOpen(false); createForm.resetFields(); invalidate() },
    onError: (err: any) => {
          const msg = err?.response?.data?.message || err?.message || ''
          if (msg.includes('duplicate key') || msg.includes('uq_package_model_version')) {
            message.error('该型号下已存在相同版本号的升级包，请使用不同的版本号')
          } else {
            message.error('创建失败: ' + msg)
          }
        },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => otaApi.deletePackage(id),
    onSuccess: () => { message.success(t('ota.deleted')); invalidate() },
    onError: () => message.error(t('ota.deleteFailed')),
  })

  const handleCreate = async () => {
    try {
      const values = await createForm.validateFields()
      const firmwareIds: number[] = []
      if (values.firmware_arm) firmwareIds.push(Number(values.firmware_arm))
      if (values.firmware_esp) firmwareIds.push(Number(values.firmware_esp))
      if (values.firmware_dsp) firmwareIds.push(Number(values.firmware_dsp))
      if (values.firmware_bms) firmwareIds.push(Number(values.firmware_bms))
      if (firmwareIds.length === 0) { message.warning('请至少选择一个芯片固件'); return }
      createMutation.mutate({ model: values.model, firmware_ids: firmwareIds, changelog: values.changelog, is_force: values.is_force || false })
    } catch { /* validation error */ }
  }

  const selectedModel = Form.useWatch('model', createForm)
  const filteredFirmware = selectedModel ? firmwareList.filter((f: Firmware) => f.model === selectedModel) : firmwareList

  const columns: ColumnsType<UpgradePackage> = [
    { title: t('ota.packageVersion'), dataIndex: 'main_version', key: 'main_version', width: 180, render: (v: string) => <Tag color="blue">{v}</Tag> },
    { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 120 },
    {
      title: t('ota.chipFirmware'), key: 'chips', width: 300,
      render: (_: any, record: UpgradePackage) => <Space wrap>{record.items?.map((item) => <Tag key={item.target_chip}>{item.target_chip.toUpperCase()}: {item.firmware_version}</Tag>)}</Space>,
    },
    { title: t('ota.packageChangelog'), dataIndex: 'changelog', key: 'changelog', width: 200, ellipsis: true },
    { title: t('ota.uploadTime'), dataIndex: 'created_at', key: 'created_at', width: 160, render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm') : '-' },
    {
      title: t('ota.action'), key: 'action', width: 260,
      render: (_: any, record: UpgradePackage) => (
        <Space size={4}>
          <Button
            type="link"
            size="small"
            icon={<DesktopOutlined />}
            onClick={() => openPkgDevicesModal(record)}
          >
            安装设备
          </Button>
          <Button
            type="link"
            size="small"
            icon={<SendOutlined />}
            onClick={() => openInstallModal(record)}
          >
            安装到设备
          </Button>
          <Popconfirm title={t('ota.confirmDeletePackage')} onConfirm={() => deleteMutation.mutate(Number(record.id))}>
            <Button type="link" size="small" danger icon={<DeleteOutlined />}>{t('ota.delete')}</Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }} bodyStyle={{ padding: '12px 16px' }}>
        <Row justify="space-between" align="middle">
          <Col><Space>
            <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateOpen(true)}>{t('ota.createPackage')}</Button>
            <Button icon={<ReloadOutlined />} onClick={invalidate} />
          </Space></Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByModel')} style={{ width: 160 }} value={modelFilter} onChange={setModelFilter}
              options={modelList.map((m: any) => ({ label: m.model_name || m.model_code, value: m.model_code }))} />
          </Col>
        </Row>
      </Card>
      <Table<UpgradePackage> dataSource={packages} columns={columns} rowKey="id" loading={isLoading} scroll={{ x: 900 }}
        pagination={{ pageSize: 20 }} locale={{ emptyText: <Empty description={t('ota.noPackages')} /> }} />

      <Modal title={t('ota.createPackage')} open={createOpen} onOk={handleCreate}
        onCancel={() => { setCreateOpen(false); createForm.resetFields() }}
        confirmLoading={createMutation.isPending} width={560}>
        <Form form={createForm} layout="vertical">
          <Form.Item name="model" label={t('ota.model')} rules={[{ required: true, message: t('ota.selectModel') }]}>
            <Select placeholder={t('ota.selectModel')} options={modelList.map((m: any) => ({ label: m.model_name || m.model_code, value: m.model_code }))} />
          </Form.Item>
          <Form.Item name="firmware_arm" label="ARM 固件">
            <Select allowClear placeholder="选择 ARM 固件"
              options={filteredFirmware.filter((f: Firmware) => f.target_chip === 'arm').map((f: Firmware) => ({ label: `${f.version} (${f.main_version})`, value: Number(f.id) }))} />
          </Form.Item>
          <Form.Item name="firmware_esp" label="ESP 固件">
            <Select allowClear placeholder="选择 ESP 固件"
              options={filteredFirmware.filter((f: Firmware) => f.target_chip === 'esp').map((f: Firmware) => ({ label: `${f.version} (${f.main_version})`, value: Number(f.id) }))} />
          </Form.Item>
          <Form.Item name="firmware_dsp" label="DSP 固件">
            <Select allowClear placeholder="选择 DSP 固件（可选）"
              options={filteredFirmware.filter((f: Firmware) => f.target_chip === 'dsp').map((f: Firmware) => ({ label: `${f.version} (${f.main_version})`, value: Number(f.id) }))} />
          </Form.Item>
          <Form.Item name="firmware_bms" label="BMS 固件">
            <Select allowClear placeholder="选择 BMS 固件（可选）"
              options={filteredFirmware.filter((f: Firmware) => f.target_chip === 'bms').map((f: Firmware) => ({ label: `${f.version} (${f.main_version})`, value: Number(f.id) }))} />
          </Form.Item>
          <Form.Item name="changelog" label={t('ota.packageChangelog')}><TextArea rows={3} /></Form.Item>
          <Form.Item name="is_force" label={t('ota.forceUpdate')} valuePropName="checked"><Switch /></Form.Item>
          <div style={{ color: '#999', fontSize: 12 }}>{t('ota.selectFirmwareHint')}</div>
        </Form>
      </Modal>

      {/* 安装到设备 Modal */}
      <Modal
        title="安装升级包到设备"
        open={installOpen}
        onCancel={() => { setInstallOpen(false); setInstallPkg(null); setInstallSnInput('') }}
        width={520}
        destroyOnClose
        footer={[
          <Button key="cancel" onClick={() => { setInstallOpen(false); setInstallPkg(null); setInstallSnInput('') }}>
            {t('ota.cancel')}
          </Button>,
          <Button
            key="submit"
            type="primary"
            icon={<SendOutlined />}
            loading={installMutation.isPending}
            onClick={handleInstallSubmit}
          >
            立即安装
          </Button>,
        ]}
      >
        {installPkg && (
          <div>
            <Descriptions column={2} size="small" bordered style={{ marginBottom: 20 }}>
              <Descriptions.Item label="升级包版本">
                <Tag color="blue">{installPkg.main_version}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="型号">{installPkg.model}</Descriptions.Item>
            </Descriptions>
            <Form.Item
              label="设备 SN"
              required
              help="输入设备 SN，多个 SN 用逗号或空格分隔"
              style={{ marginBottom: 0 }}
            >
              <TextArea
                rows={4}
                placeholder="例如：SN001, SN002, SN003"
                value={installSnInput}
                onChange={(e) => setInstallSnInput(e.target.value)}
                onPressEnter={(e) => e.preventDefault()}
              />
            </Form.Item>
          </div>
        )}
      </Modal>

      {/* 查看已安装该升级包的设备 Modal */}
      <Modal
        title="已安装该升级包的设备"
        open={pkgDevicesOpen}
        onCancel={() => { setPkgDevicesOpen(false); setPkgDevicesTarget(null); setPkgDevices([]) }}
        width={780}
        destroyOnClose
        footer={[
          <Button key="close" onClick={() => { setPkgDevicesOpen(false); setPkgDevicesTarget(null); setPkgDevices([]) }}>
            关闭
          </Button>,
        ]}
      >
        {pkgDevicesTarget && (
          <div>
            <Descriptions column={2} size="small" bordered style={{ marginBottom: 16 }}>
              <Descriptions.Item label="升级包版本">
                <Tag color="blue">{pkgDevicesTarget.main_version}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="型号">{pkgDevicesTarget.model}</Descriptions.Item>
            </Descriptions>
            <Table<DeviceUpgrade>
              rowKey={(r) => `${r.device_sn}-${r.id}`}
              size="small"
              loading={pkgDevicesLoading}
              dataSource={pkgDevices}
              pagination={{ pageSize: 10 }}
              locale={{ emptyText: <Empty description="暂无设备安装该升级包" /> }}
              columns={[
                { title: '设备 SN', dataIndex: 'device_sn', key: 'device_sn', width: 140 },
                { title: '型号', dataIndex: 'device_model', key: 'device_model', width: 100, render: (v: string) => v || '-' },
                {
                  title: '安装状态',
                  dataIndex: 'status',
                  key: 'status',
                  width: 100,
                  render: (s: string) => {
                    const statusMap: Record<string, { label: string; color: string }> = {
                      success: { label: '成功', color: 'success' },
                      pending: { label: '待执行', color: 'processing' },
                      upgrading: { label: '升级中', color: 'warning' },
                      downloading: { label: '下载中', color: 'cyan' },
                      failed: { label: '失败', color: 'error' },
                      cancelled: { label: '已取消', color: 'default' },
                    }
                    const cfg = statusMap[s] || { label: s, color: 'default' }
                    return <Tag color={cfg.color}>{cfg.label}</Tag>
                  },
                },
                {
                  title: '安装时间',
                  dataIndex: 'created_at',
                  key: 'created_at',
                  width: 170,
                  render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-',
                },
              ]}
            />
          </div>
        )}
      </Modal>
    </div>
  )
}

// =================== Tab 3: App版本管理 (保持不变) ===================
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
      const d = r.data; const list = d?.data ?? d?.items ?? d ?? []
      return Array.isArray(list) ? list : []
    }),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.ota.appVersions() })

  const createMutation = useMutation({
    mutationFn: (data: any) => otaApi.createAppVersion(data),
    onSuccess: () => { message.success(t('ota.versionPublishSuccess')); setCreateOpen(false); form.resetFields(); invalidate() },
    onError: () => message.error(t('ota.versionPublishFailed')),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => otaApi.deleteAppVersion(id),
    onSuccess: () => { message.success(t('ota.appVersionDeleteSuccess')); invalidate() },
    onError: () => message.error(t('ota.appVersionDeleteFailed')),
  })

  const rolloutMutation = useMutation({
    mutationFn: ({ id, percentage }: { id: number; percentage: number }) => otaApi.updateAppVersionRollout(id, percentage),
    onSuccess: () => { message.success(t('ota.rolloutUpdateSuccess')); setRolloutModalOpen(false); invalidate() },
    onError: () => message.error(t('ota.rolloutUpdateFailed')),
  })

  const rollbackMutation = useMutation({
    mutationFn: (id: number) => otaApi.rollbackAppVersion(id),
    onSuccess: () => { message.success(t('ota.appRollbackSuccess')); invalidate() },
    onError: () => message.error(t('ota.appRollbackFailed')),
  })

  const restoreMutation = useMutation({
    mutationFn: (id: number) => otaApi.restoreAppVersion(id),
    onSuccess: () => { message.success(t('ota.appRestoreSuccess')); invalidate() },
    onError: () => message.error(t('ota.appRestoreFailed')),
  })

  const handleCreate = async () => {
    try {
      const values = await form.validateFields()
      createMutation.mutate({
        platform: values.platform, version_code: values.versionCode, version_name: values.versionName,
        download_url: values.downloadUrl, file_size: values.fileSize || 0, file_md5: values.fileMd5 || '',
        changelog: values.changelog || '', is_force: values.isForce || false,
        min_supported_version: values.minSupportedVersion || 0, rollout_percentage: values.rolloutPercentage || 100,
      })
    } catch { /* validation */ }
  }

  const openRolloutModal = (record: any) => {
    setRolloutTarget(record); setRolloutPercent(record.rollout_percentage ?? 100); setRolloutModalOpen(true)
  }

  const handleRollout = () => {
    if (!rolloutTarget) return
    rolloutMutation.mutate({ id: rolloutTarget.id, percentage: rolloutPercent })
  }

  const ROLLOUT_MARKS: Record<number, string> = { 0: '0%', 10: '10%', 25: '25%', 50: '50%', 75: '75%', 100: '100%' }

  const columns: ColumnsType<any> = [
    {
      title: t('ota.platform'), dataIndex: 'platform', key: 'platform', width: 90,
      render: (val: string) => <Tag icon={val === 'ios' ? <AppleOutlined /> : <AndroidOutlined />} color={val === 'ios' ? '#000' : '#52c41a'}>{val === 'ios' ? 'iOS' : 'Android'}</Tag>,
    },
    { title: t('ota.versionCode'), dataIndex: 'version_code', key: 'version_code', width: 80, render: (val: number) => <Tag color="blue">{val}</Tag> },
    { title: t('ota.versionName'), dataIndex: 'version_name', key: 'version_name', width: 100 },
    { title: t('ota.downloadUrl'), dataIndex: 'download_url', key: 'download_url', ellipsis: true, render: (val: string) => <Tooltip title={val}><span style={{ fontFamily: 'monospace', fontSize: 12 }}>{val || '-'}</span></Tooltip> },
    { title: t('ota.forceUpdate'), dataIndex: 'is_force', key: 'is_force', width: 80, render: (val: boolean) => val ? <Tag color="red">{t('ota.force')}</Tag> : <Tag>{t('common.no')}</Tag> },
    {
      title: t('ota.rolloutPercent'), dataIndex: 'rollout_percentage', key: 'rollout_percentage', width: 120,
      render: (val: number, record: any) => {
        if (record.is_rolled_back) return <Tag color="red">{t('ota.rolledBack')}</Tag>
        const pct = val ?? 100
        return <Space><Progress percent={pct} size="small" style={{ width: 60 }} /><span style={{ fontSize: 12 }}>{pct}%</span></Space>
      },
    },
    { title: t('ota.changelog'), dataIndex: 'changelog', key: 'changelog', ellipsis: true, render: (val: string) => <Tooltip title={val}><span>{val || '-'}</span></Tooltip> },
    { title: t('ota.publishTime'), dataIndex: 'created_at', key: 'created_at', width: 150, render: (val: string) => val ? dayjs(val).format('YYYY-MM-DD HH:mm') : '-' },
    {
      title: t('common.operation'), key: 'action', width: 200,
      render: (_: any, record: any) => (
        <Space>
          {record.is_rolled_back ? (
            <Popconfirm title={t('ota.confirmRestore')} onConfirm={() => restoreMutation.mutate(record.id)}>
              <Button type="link" size="small" icon={<RedoOutlined />} loading={restoreMutation.isPending}>{t('ota.restore')}</Button>
            </Popconfirm>
          ) : (
            <>
              <Button type="link" size="small" icon={<SafetyOutlined />} onClick={() => openRolloutModal(record)}>{t('ota.grayRelease')}</Button>
              <Popconfirm title={t('ota.confirmAppRollback')} onConfirm={() => rollbackMutation.mutate(record.id)}>
                <Button type="link" size="small" danger icon={<RollbackOutlined />} loading={rollbackMutation.isPending}>{t('ota.rollback')}</Button>
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
          <Col><Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateOpen(true)}>{t('ota.publishVersion')}</Button></Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByPlatform')} style={{ width: 140 }} value={platformFilter}
              onChange={(val) => setPlatformFilter(val)} options={[{ label: 'Android', value: 'android' }, { label: 'iOS', value: 'ios' }]} />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
        </Row>
      </Card>
      <Table rowKey="id" columns={columns} dataSource={versionData} loading={isLoading} size="small" pagination={false} />

      <Modal title={t('ota.publishAppVersion')} open={createOpen} onCancel={() => { setCreateOpen(false); form.resetFields() }}
        onOk={handleCreate} confirmLoading={createMutation.isPending} destroyOnClose width={560}>
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
          <Form.Item name="fileSize" label={t('ota.fileSizeBytes')}><InputNumber min={0} style={{ width: '100%' }} placeholder={t('ota.fileSizePlaceholder')} /></Form.Item>
          <Form.Item name="fileMd5" label={t('ota.fileMD5')}><Input placeholder={t('ota.fileMd5Placeholder')} /></Form.Item>
          <Form.Item name="changelog" label={t('ota.changelog')}><Input.TextArea rows={3} placeholder={t('ota.inputChangelog')} /></Form.Item>
          <Form.Item name="isForce" label={t('ota.forceUpdate')} valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="minSupportedVersion" label={t('ota.minVersion')}><InputNumber min={0} style={{ width: '100%' }} placeholder={t('ota.minVersionPlaceholder')} /></Form.Item>
          <Form.Item name="rolloutPercentage" label={t('ota.rolloutPercent')} initialValue={100}>
            <Slider marks={ROLLOUT_MARKS} min={0} max={100} step={null} />
          </Form.Item>
        </Form>
      </Modal>

      <Modal title={t('ota.adjustRollout')} open={rolloutModalOpen} onCancel={() => setRolloutModalOpen(false)}
        onOk={handleRollout} confirmLoading={rolloutMutation.isPending} destroyOnClose>
        {rolloutTarget && (
          <div>
            <p style={{ marginBottom: 16 }}>
              <strong>{rolloutTarget.platform === 'ios' ? 'iOS' : 'Android'} v{rolloutTarget.version_name}</strong>
              <span style={{ color: '#999', marginLeft: 8 }}>({t('ota.currentRollout')}: {rolloutTarget.rollout_percentage ?? 100}%)</span>
            </p>
            <Slider marks={ROLLOUT_MARKS} min={0} max={100} step={null} value={rolloutPercent} onChange={setRolloutPercent} />
            <p style={{ marginTop: 16, color: '#999', fontSize: 13 }}>
              {rolloutPercent === 100 ? t('ota.rolloutAllUsers') : t('ota.rolloutPercentDesc', { percent: rolloutPercent })}
            </p>
          </div>
        )}
      </Modal>
    </div>
  )
}

export default OtaPage
