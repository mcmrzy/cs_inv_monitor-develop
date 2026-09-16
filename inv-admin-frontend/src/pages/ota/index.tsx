import React, { useEffect, useMemo, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { buildFirmwareUploadFormData } from './firmwareUpload'
import {
  Tabs,
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
  Alert,
} from 'antd'
import Popconfirm from '@/components/LocalizedPopconfirm'
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
  CheckCircleOutlined,
  CloseCircleOutlined,
  ClockCircleOutlined,
  FileOutlined,
  DesktopOutlined,
} from '@ant-design/icons'
import type { ProColumns } from '@ant-design/pro-components'
import { ProTable, ProCard } from '@ant-design/pro-components'
import type { UploadProps } from 'antd'
import { otaApi, createOtaIdempotencyKey } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import { modelApi } from '@/services/modelApi'
import { queryKeys } from '@/utils/queryKeys'
import type { Firmware, FirmwarePublishRequest, DeviceUpgrade, Device, UpgradeTask } from '@/types'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import {
  canAccessOtaTab,
  canMutateOta,
  resolveOtaTab,
  type OtaTabKey,
} from '@/router/routeAccess'
import { firmwareModuleLabel, sanitizeLegacyFirmwareLabel } from './firmwarePresentation'
import DeviceFirmwareUpgradeTab from './DeviceFirmwareUpgradeTab'
import UpgradeHistoryTab from './UpgradeHistoryTab'
import FirmwarePublishModal from './components/FirmwarePublishModal'

const { TextArea } = Input
const { Dragger } = Upload
const { Title, Text } = Typography

function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

interface FirmwareFormValues {
  model: string
  targetChip: string
  version: string
  changelog: string
}

// =================== 任务状态映射 ===================
const TASK_STATUS_MAP: Record<string, { i18nKey: string; color: string }> = {
  draft: { i18nKey: 'ota.taskStatusDraft', color: 'default' },
  pending: { i18nKey: 'ota.taskStatusPending', color: 'processing' },
  scheduled: { i18nKey: 'ota.taskStatusScheduled', color: 'warning' },
  running: { i18nKey: 'ota.taskStatusRunning', color: 'processing' },
  completed: { i18nKey: 'ota.taskStatusCompleted', color: 'success' },
  partial_success: { i18nKey: 'ota.taskStatusPartialSuccess', color: 'warning' },
  failed: { i18nKey: 'ota.taskStatusFailed', color: 'error' },
  cancelled: { i18nKey: 'ota.taskStatusCancelled', color: 'default' },
  blocked: { i18nKey: 'ota.statusBlocked', color: 'orange' },
  skipped: { i18nKey: 'ota.statusSkipped', color: 'default' },
  timeout: { i18nKey: 'ota.statusTimeout', color: 'error' },
}

const UPGRADE_STATUS_MAP: Record<string, { i18nKey: string; color: string }> = {
  pending: { i18nKey: 'ota.taskStatusPending', color: '#1677ff' },
  downloading: { i18nKey: 'ota.downloading', color: '#13c2c2' },
  upgrading: { i18nKey: 'ota.upgrading', color: '#fa8c16' },
  success: { i18nKey: 'ota.success', color: '#52c41a' },
  failed: { i18nKey: 'ota.failed', color: '#ff4d4f' },
  cancelled: { i18nKey: 'ota.cancelled', color: '#d9d9d9' },
  blocked: { i18nKey: 'ota.statusBlocked', color: '#fa8c16' },
  skipped: { i18nKey: 'ota.statusSkipped', color: '#d9d9d9' },
}

// 设备上报的原始阶段(device_upgrades.stage)
const UPGRADE_STAGE_MAP: Record<string, string> = {
  accepted: 'ota.stageAccepted',
  downloading: 'ota.stageDownloading',
  receiving: 'ota.stageDownloading',
  verifying: 'ota.stageVerifying',
  installing: 'ota.stageInstalling',
  rebooting: 'ota.stageRebooting',
  succeeded: 'ota.stageSucceeded',
  failed: 'ota.stageFailed',
  cancelled: 'ota.stageCancelled',
  rolled_back: 'ota.stageRolledBack',
}

const RELEASE_STATUS_MAP: Record<string, { i18nKey: string; color: string }> = {
  draft: { i18nKey: 'ota.draft', color: 'default' },
  published: { i18nKey: 'ota.statusPublished', color: 'success' },
  disabled: { i18nKey: 'ota.statusDisabled', color: 'error' },
}

// =================== 主页面：五 Tab + 权限深链 ===================
const OtaPage: React.FC = () => {
  const { t } = useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  const hasAnyPermission = useAuthStore((s) => s.hasAnyPermission)

  const activeTab = resolveOtaTab(searchParams.get('tab'), isSystemAdmin, hasAnyPermission)

  // 深链无权 Tab 时自动回落设备 Tab，并同步 URL
  useEffect(() => {
    const requested = searchParams.get('tab')
    if (requested && requested !== activeTab) {
      setSearchParams({ tab: activeTab }, { replace: true })
    }
  }, [searchParams, activeTab, setSearchParams])

  const onTabChange = (key: string) => {
    setSearchParams({ tab: key }, { replace: true })
  }

  const items: { key: string; label: string; children: React.ReactNode }[] = [
    {
      key: 'deviceFirmware',
      label: t('ota.deviceFirmwareUpgrade'),
      children: <DeviceFirmwareUpgradeTab />,
    },
  ]
  if (canAccessOtaTab('firmware', isSystemAdmin, hasAnyPermission)) {
    items.push({
      key: 'firmware',
      label: t('ota.firmwareManage'),
      children: <FirmwareTab />,
    })
  }
  if (canAccessOtaTab('tasks', isSystemAdmin, hasAnyPermission)) {
    items.push({
      key: 'tasks',
      label: t('ota.upgradeTasks'),
      children: <UpgradeTasksTab />,
    })
  }
  if (canAccessOtaTab('history', isSystemAdmin, hasAnyPermission)) {
    items.push({
      key: 'history',
      label: t('ota.upgradeHistory'),
      children: <UpgradeHistoryTab />,
    })
  }
  if (canAccessOtaTab('appVersion', isSystemAdmin, hasAnyPermission)) {
    items.push({
      key: 'appVersion',
      label: t('ota.appVersionManage'),
      children: <AppVersionTab />,
    })
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <CloudUploadOutlined style={{ marginRight: 8 }} />
        {t('ota.title')}
      </Title>
      <Tabs activeKey={activeTab} onChange={onTabChange} items={items} />
    </div>
  )
}

// =================== Tab: 升级任务（仅单固件，无 package 写路径） ===================
const UpgradeTasksTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  const hasAnyPermission = useAuthStore((s) => s.hasAnyPermission)
  const canCreate = canMutateOta('create', isSystemAdmin, hasAnyPermission)
  const canControl = canMutateOta('control', isSystemAdmin, hasAnyPermission)
  const canDelete = canMutateOta('delete', isSystemAdmin, hasAnyPermission)

  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [statusFilter, setStatusFilter] = useState<string>('')
  const [createOpen, setCreateOpen] = useState(false)
  const [currentStep, setCurrentStep] = useState(0)
  const [selectedFirmwareId, setSelectedFirmwareId] = useState<number | null>(null)
  const [selectedDeviceSns, setSelectedDeviceSns] = useState<string[]>([])
  const [executeMode, setExecuteMode] = useState<string>('immediate')
  const [scheduledAt, setScheduledAt] = useState<string>('')
  const [rolloutPercent, setRolloutPercent] = useState(100)
  const [taskName, setTaskName] = useState('')
  const [detailTaskId, setDetailTaskId] = useState<number | string | null>(null)
  const [detailOpen, setDetailOpen] = useState(false)

  // 固件回退 Modal（独立模块，替代 package 回退）
  const [rollbackOpen, setRollbackOpen] = useState(false)
  const [rollbackSn, setRollbackSn] = useState('')
  const [rollbackFirmwareId, setRollbackFirmwareId] = useState<number | null>(null)
  const [forceReason, setForceReason] = useState('')

  const [searchParams, setSearchParams] = useSearchParams()
  useEffect(() => {
    if (searchParams.get('create') === '1') {
      const sns = (searchParams.get('sns') || '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
      if (sns.length > 0 && canCreate) {
        setSelectedDeviceSns(sns)
        setCreateOpen(true)
      }
      const nextParams = new URLSearchParams(searchParams)
      nextParams.delete('create')
      nextParams.delete('sns')
      nextParams.set('tab', 'tasks')
      setSearchParams(nextParams, { replace: true })
    }
  }, [searchParams, setSearchParams, canCreate])

  const queryParams: any = { page, pageSize }
  if (statusFilter) queryParams.status = statusFilter

  const { data: tasksRes, isLoading, error: tasksError, refetch } = useQuery({
    queryKey: queryKeys.ota.tasks(queryParams),
    queryFn: () => otaApi.listTasks(queryParams).then((r) => {
      const d = r.data?.data ?? r.data ?? {}
      const items = d?.items ?? []
      return { items: (Array.isArray(items) ? items : []) as UpgradeTask[], total: (d?.total ?? 0) as number }
    }),
  })

  const { data: statsRes, error: statsError, refetch: refetchStats } = useQuery({
    queryKey: queryKeys.ota.taskStats(),
    queryFn: () => otaApi.getTaskStats().then((r) => r.data?.data ?? r.data ?? {}),
  })
  const stats = statsRes as any

  const { data: firmwareList = [], error: firmwareListError, refetch: refetchFirmwareList } = useQuery({
    queryKey: queryKeys.ota.firmwares({ all: true }),
    queryFn: () => otaApi.getAllFirmware().then((r) => {
      const d = r.data; const list = d?.data?.items ?? d?.data ?? d?.items ?? []
      return (Array.isArray(list) ? list : []) as Firmware[]
    }),
    enabled: createOpen,
  })

  const { data: deviceList = [], error: deviceListError, refetch: refetchDeviceList } = useQuery({
    queryKey: ['devices', 'all'],
    queryFn: () => deviceApi.getAll().then((r) => {
      const d = r.data; const list = d?.data?.items ?? d?.data ?? d?.items ?? []
      return (Array.isArray(list) ? list : []) as Device[]
    }),
    enabled: createOpen,
  })

  const { data: taskDevices = [], isLoading: devicesLoading, error: taskDevicesError, refetch: refetchTaskDevices } = useQuery({
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

  const rollbackMutation = useMutation({
    mutationFn: (data: { device_sn: string; firmware_id: number; idempotency_key: string; force_reason?: string }) =>
      otaApi.rollbackFirmware(data),
    onSuccess: () => {
      message.success(t('ota.triggerSuccess'))
      setRollbackOpen(false)
      setRollbackSn('')
      setRollbackFirmwareId(null)
      setForceReason('')
      invalidate()
    },
    onError: (err: any) => {
      const code = err?.response?.data?.error
      message.error(
        code === 'legacy_package_retired'
          ? t('ota.legacyPackageRetired')
          : `${t('ota.rollbackFailed')}: ${err?.response?.data?.message || err?.message || t('common.unknownError')}`,
      )
    },
  })

  const openRollbackModal = (sn: string) => {
    setRollbackSn(sn)
    setRollbackFirmwareId(null)
    setForceReason('')
    setRollbackOpen(true)
  }

  const handleRollback = () => {
    if (!rollbackSn || !rollbackFirmwareId) {
      message.warning(t('ota.selectFirmwareToUpgrade'))
      return
    }
    rollbackMutation.mutate({
      device_sn: rollbackSn,
      firmware_id: rollbackFirmwareId,
      idempotency_key: createOtaIdempotencyKey('rollback'),
      force_reason: forceReason || undefined,
    })
  }

  const resetCreateForm = () => {
    setCreateOpen(false)
    setCurrentStep(0)
    setSelectedFirmwareId(null)
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
      task_type: 'single',
      device_sns: selectedDeviceSns,
      execute_mode: executeMode,
      rollout_percent: rolloutPercent,
      firmware_id: selectedFirmwareId,
    }
    if (executeMode === 'scheduled' && scheduledAt) data.scheduled_at = scheduledAt
    createMutation.mutate(data)
  }

  const targetModel = useMemo(() => {
    if (selectedFirmwareId) {
      return firmwareList.find((f) => Number(f.id) === selectedFirmwareId)?.model || ''
    }
    return ''
  }, [selectedFirmwareId, firmwareList])

  const filteredDevices = useMemo(() => {
    if (!targetModel) return deviceList
    return deviceList.filter((d) => d.model === targetModel)
  }, [deviceList, targetModel])

  const targetVersion = useMemo(() => {
    if (selectedFirmwareId) {
      const fw = firmwareList.find((f) => Number(f.id) === selectedFirmwareId)
      return fw?.version || ''
    }
    return ''
  }, [selectedFirmwareId, firmwareList])

  const canNext = () => {
    if (currentStep === 0) return !!selectedFirmwareId
    if (currentStep === 1) return selectedDeviceSns.length > 0
    return true
  }

  const tasksData = tasksRes?.items ?? []
  const tasksTotal = tasksRes?.total ?? 0

  const columns: ProColumns<UpgradeTask>[] = [
    {
      title: t('ota.taskName'), dataIndex: 'name', key: 'name', width: 140, ellipsis: true,
      render: (_, record: UpgradeTask) => record.name || `#${record.id}`,
    },
    {
      title: t('ota.upgradeType'), key: 'task_type', width: 90,
      render: (_: any, r: UpgradeTask) => (
        <Tag color={r.task_type === 'package' ? 'default' : 'blue'}>
          {r.task_type === 'package' ? t('ota.legacyTask') : t('ota.singleChip')}
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
        const cfg = TASK_STATUS_MAP[r.status]
        return <Tag color={cfg?.color || 'default'}>{cfg ? t(cfg.i18nKey) : r.status}</Tag>
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
      title: t('ota.source'), key: 'source', width: 100,
      render: (_: any, r: UpgradeTask) => {
        const sourceMap: Record<string, { label: string; color: string }> = {
          admin: { label: t('ota.sourceAdmin'), color: 'blue' },
          app: { label: t('ota.sourceApp'), color: 'green' },
          local: { label: t('ota.sourceLocal'), color: 'orange' },
        }
        const cfg = sourceMap[r.source || ''] || { label: r.source || '-', color: 'default' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('common.createdAt'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 150,
      render: (_: any, r: UpgradeTask) =>
        r.created_at ? formatInTimezone(r.created_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('ota.scheduledTime'),
      dataIndex: 'scheduled_at',
      key: 'scheduled_at',
      width: 150,
      render: (_: any, r: UpgradeTask) =>
        r.scheduled_at ? formatInTimezone(r.scheduled_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('ota.executeTime'),
      dataIndex: 'executed_at',
      key: 'executed_at',
      width: 150,
      render: (_: any, r: UpgradeTask) =>
        r.executed_at ? formatInTimezone(r.executed_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('ota.completeTime'),
      dataIndex: 'completed_at',
      key: 'completed_at',
      width: 150,
      render: (_: any, r: UpgradeTask) =>
        r.completed_at ? formatInTimezone(r.completed_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('common.operation'), key: 'action', width: 280, fixed: 'right',
      render: (_: any, r: UpgradeTask) => (
        <Space size={4}>
          <Button type="link" size="small" onClick={() => { setDetailTaskId(r.id); setDetailOpen(true) }}>
            {t('ota.detail')}
          </Button>
          {canControl && r.status === 'completed' && (
            <Button
              type="link"
              size="small"
              icon={<RollbackOutlined />}
              onClick={() => {
                otaApi.getTaskDevices(r.id).then((res) => {
                  const devices = res.data?.data?.items ?? []
                  if (devices.length > 0) {
                    openRollbackModal(devices[0].device_sn)
                  } else {
                    message.warning(t('ota.taskHasNoDevices'))
                  }
                })
              }}
            >
              {t('ota.rollbackFirmware')}
            </Button>
          )}
          {canControl && (r.status === 'pending' || r.status === 'draft') && (
            <Popconfirm title={t('ota.confirmExecuteTask')} onConfirm={() => executeMutation.mutate(r.id)}>
              <Button type="link" size="small" icon={<RocketOutlined />}>{t('ota.execute')}</Button>
            </Popconfirm>
          )}
          {canControl && ['pending', 'scheduled', 'running', 'draft'].includes(r.status) && (
            <Popconfirm title={t('ota.confirmCancelTask')} onConfirm={() => cancelMutation.mutate(r.id)}>
              <Button type="link" size="small" danger icon={<StopOutlined />}>{t('ota.cancel')}</Button>
            </Popconfirm>
          )}
          {canControl && (r.status === 'failed' || r.status === 'partial_success') && (
            <Popconfirm title={t('ota.confirmRetryTask')} onConfirm={() => retryMutation.mutate(r.id)}>
              <Button type="link" size="small" icon={<RedoOutlined />}>{t('ota.retry')}</Button>
            </Popconfirm>
          )}
          {canDelete && ['completed', 'cancelled', 'failed', 'draft'].includes(r.status) && (
            <Popconfirm title={t('ota.confirmDeleteTaskNew')} onConfirm={() => deleteMutation.mutate(r.id)}>
              <Button type="link" size="small" danger icon={<DeleteOutlined />}>{t('ota.delete')}</Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ]

  const detailColumns: ProColumns<DeviceUpgrade>[] = [
    { title: 'SN', dataIndex: 'device_sn', key: 'device_sn', width: 140 },
    {
      title: t('ota.currentFirmware'), key: 'current_firmware', width: 180,
      render: (_: any, r: DeviceUpgrade) => {
        const parts: string[] = []
        if (r.current_arm_version) parts.push(`${firmwareModuleLabel('arm', t)}: ${r.current_arm_version}`)
        if (r.current_esp_version) parts.push(`${firmwareModuleLabel('esp', t)}: ${r.current_esp_version}`)
        return parts.length > 0 ? parts.join(' / ') : '-'
      },
    },
    { title: t('ota.oldVersion'), dataIndex: 'old_version', key: 'old_version', width: 100 },
    { title: t('ota.targetVersion'), dataIndex: 'firmware_version', key: 'firmware_version', width: 100 },
    {
      title: t('ota.module'), dataIndex: 'target_chip', key: 'target_chip', width: 110,
      render: (_: any, r: DeviceUpgrade) => firmwareModuleLabel(r.target_chip, t),
    },
    {
      title: t('common.status'), dataIndex: 'status', key: 'status', width: 100,
      render: (_: any, record: DeviceUpgrade) => {
        const s = record.status
        const c = UPGRADE_STATUS_MAP[s]
        return <Tag color={c?.color || '#d9d9d9'}>{c ? t(c.i18nKey) : s}</Tag>
      },
    },
    {
      title: t('ota.progress'), dataIndex: 'progress', key: 'progress', width: 150,
      render: (_: any, record: DeviceUpgrade) => {
        const stageKey = UPGRADE_STAGE_MAP[record.stage]
        const statusCfg = UPGRADE_STATUS_MAP[record.status]
        const label = stageKey ? t(stageKey) : statusCfg ? t(statusCfg.i18nKey) : record.status
        return (
          <Space direction="vertical" size={0} style={{ width: '100%' }}>
            <span style={{ fontSize: 12, color: '#8c8c8c' }}>{label}</span>
            <Progress percent={record.progress} size="small" />
          </Space>
        )
      },
    },
    {
      title: t('ota.errorInfo'), dataIndex: 'error_message', key: 'error_message', ellipsis: true,
      render: (_: any, record: DeviceUpgrade) => record.error_message || '-',
    },
  ]

  const queryFailure = [
    { error: tasksError, retry: refetch },
    { error: statsError, retry: refetchStats },
    { error: firmwareListError, retry: refetchFirmwareList },
    { error: deviceListError, retry: refetchDeviceList },
    { error: taskDevicesError, retry: refetchTaskDevices },
  ].find((item) => item.error)

  const publishedFirmwareOptions = firmwareList
    .filter((fw) => (fw.release_status || 'published') === 'published')
    .map((fw) => ({
      label: `${sanitizeLegacyFirmwareLabel(fw.model) || fw.model} · ${firmwareModuleLabel(fw.target_chip, t)} · ${fw.version}`,
      value: Number(fw.id),
    }))

  return (
    <div>
      {queryFailure && <QueryErrorAlert error={queryFailure.error} onRetry={() => { void queryFailure.retry() }} style={{ marginBottom: 16 }} />}
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <ProCard style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statPending')} value={stats?.pending ?? 0} prefix={<ClockCircleOutlined />} valueStyle={{ color: '#1677ff' }} />
          </ProCard>
        </Col>
        <Col span={6}>
          <ProCard style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statRunning')} value={stats?.running ?? 0} prefix={<RocketOutlined />} valueStyle={{ color: '#fa8c16' }} />
          </ProCard>
        </Col>
        <Col span={6}>
          <ProCard style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statCompletedToday')} value={stats?.completed_today ?? 0} prefix={<CheckCircleOutlined />} valueStyle={{ color: '#52c41a' }} />
          </ProCard>
        </Col>
        <Col span={6}>
          <ProCard style={{ borderRadius: 12 }}>
            <Statistic title={t('ota.statFailed')} value={stats?.failed ?? 0} prefix={<CloseCircleOutlined />} valueStyle={{ color: '#ff4d4f' }} />
          </ProCard>
        </Col>
      </Row>

      <ProCard style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            {canCreate && (
              <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreateOpen(true)}>
                {t('ota.createUpgradeTask')}
              </Button>
            )}
          </Col>
          <Col>
            <Select
              allowClear
              placeholder={t('ota.filterByStatus')}
              style={{ width: 140 }}
              value={statusFilter}
              onChange={(val) => { setStatusFilter(val); setPage(1) }}
              options={[
                { label: t('common.all'), value: '' },
                { label: t('ota.taskStatusActive'), value: 'active' },
                { label: t('ota.taskStatusPending'), value: 'pending' },
                { label: t('ota.taskStatusRunning'), value: 'running' },
                { label: t('ota.taskStatusCompleted'), value: 'completed' },
                { label: t('ota.taskStatusFailed'), value: 'failed' },
                { label: t('ota.taskStatusCancelled'), value: 'cancelled' },
                { label: t('ota.statusBlocked'), value: 'blocked' },
                { label: t('ota.statusSkipped'), value: 'skipped' },
              ]}
            />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
        </Row>
      </ProCard>

      <ProTable<UpgradeTask>
        rowKey="id"
        columns={columns}
        dataSource={tasksData}
        loading={isLoading}
        size="small"
        search={false}
        options={{ density: true, reload: () => refetch(), setting: true }}
        scroll={{ x: 1600 }}
        pagination={{
          current: page, pageSize, total: tasksTotal, showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      {/* 创建升级任务 Modal（仅单固件模式） */}
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

        {currentStep === 0 && (
          <div>
            <Form.Item label={t('ota.taskName')} style={{ marginBottom: 16 }}>
              <Input
                value={taskName}
                onChange={(e) => setTaskName(e.target.value)}
                placeholder={t('ota.taskNamePlaceholder')}
              />
            </Form.Item>
            <Form.Item label={t('ota.selectFirmware')} required>
              <Select
                placeholder={t('ota.selectFirmwareVersion')}
                value={selectedFirmwareId}
                onChange={setSelectedFirmwareId}
                showSearch
                filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())}
                options={publishedFirmwareOptions}
              />
            </Form.Item>
            {targetModel && (
              <Descriptions column={2} size="small" bordered>
                <Descriptions.Item label={t('ota.model')}>{targetModel}</Descriptions.Item>
                <Descriptions.Item label={t('ota.targetVersion')}>{targetVersion}</Descriptions.Item>
              </Descriptions>
            )}
          </div>
        )}

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
            <ProTable<Device>
              rowKey="sn"
              size="small"
              search={false}
              rowSelection={{
                selectedRowKeys: selectedDeviceSns,
                onChange: (keys) => setSelectedDeviceSns(keys as string[]),
              }}
              dataSource={filteredDevices}
              columns={[
                { title: 'SN', dataIndex: 'sn', key: 'sn', width: 140 },
                { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 100 },
                { title: t('ota.currentVersion'), dataIndex: 'firmwareVersion', key: 'firmwareVersion', width: 120, render: (_: any, record: Device) => record.firmwareVersion || '-' },
              ]}
              pagination={{ pageSize: 8, size: 'small' }}
              scroll={{ y: 350 }}
              locale={{ emptyText: <Empty description={t('ota.noDeviceData')} /> }}
            />
          </div>
        )}

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

      <Drawer
        title={t('ota.taskDevices')}
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={900}
        destroyOnClose
        extra={<Button icon={<ReloadOutlined />} size="small" onClick={() => queryClient.invalidateQueries({ queryKey: queryKeys.ota.taskDevices(detailTaskId ?? 0) })} />}
      >
        <ProTable<DeviceUpgrade>
          rowKey={(r) => `${r.device_sn}-${r.firmware_id}`}
          columns={detailColumns}
          dataSource={taskDevices}
          loading={devicesLoading}
          size="small"
          search={false}
          scroll={{ x: 900 }}
          pagination={false}
        />
      </Drawer>

      {/* 独立模块固件回退 Modal */}
      <Modal
        title={t('ota.rollbackFirmware')}
        open={rollbackOpen}
        onCancel={() => { setRollbackOpen(false); setRollbackSn(''); setRollbackFirmwareId(null); setForceReason('') }}
        onOk={handleRollback}
        confirmLoading={rollbackMutation.isPending}
        width={500}
        destroyOnClose
        okButtonProps={{ disabled: !canControl }}
      >
        <Alert
          message={t('ota.rollbackInstructions')}
          description={t('ota.confirmRollbackFirmware')}
          type="warning"
          showIcon
          style={{ marginBottom: 16 }}
        />
        <Form layout="vertical">
          <Form.Item label={t('common.deviceSN')}>
            <Input value={rollbackSn} disabled />
          </Form.Item>
          <Form.Item label={t('ota.selectFirmware')} required>
            <Select
              placeholder={t('ota.selectFirmwareToUpgrade')}
              value={rollbackFirmwareId}
              onChange={setRollbackFirmwareId}
              showSearch
              options={publishedFirmwareOptions}
            />
          </Form.Item>
          <Form.Item label={t('ota.forceReason')}>
            <Input.TextArea
              rows={2}
              value={forceReason}
              onChange={(e) => setForceReason(e.target.value)}
              placeholder={t('ota.forceReasonPlaceholder')}
            />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

// =================== Tab: 固件管理（含发布生命周期） ===================
const FirmwareTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  const hasAnyPermission = useAuthStore((s) => s.hasAnyPermission)
  const canCreate = canMutateOta('create', isSystemAdmin, hasAnyPermission)
  const canControl = canMutateOta('control', isSystemAdmin, hasAnyPermission)
  const canDelete = canMutateOta('delete', isSystemAdmin, hasAnyPermission)

  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [modelFilter, setModelFilter] = useState<string>()
  const [chipFilter, setChipFilter] = useState<string>()
  const [uploadOpen, setUploadOpen] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [fileList, setFileList] = useState<any[]>([])
  const [form] = Form.useForm<FirmwareFormValues>()
  const [publishOpen, setPublishOpen] = useState(false)
  const [publishTarget, setPublishTarget] = useState<Firmware | null>(null)

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
      message.error(`${t('ota.queryDevicesFailed')}: ${err?.response?.data?.message || err?.message || t('common.unknownError')}`)
      setFwDevices([])
    } finally {
      setFwDevicesLoading(false)
    }
  }

  const queryParams = { page, pageSize, model: modelFilter || undefined }

  const { data: firmwareRes, isLoading, error: firmwareError, refetch } = useQuery({
    queryKey: queryKeys.ota.firmwares(queryParams),
    queryFn: () => otaApi.listFirmware(queryParams).then((r) => {
      const d = r.data
      let list = d?.items ?? d?.data?.items ?? d?.data ?? []
      if (!Array.isArray(list)) list = []
      if (chipFilter) list = list.filter((item: Firmware) => item.target_chip === chipFilter)
      return { items: list as Firmware[], total: (d?.total ?? d?.data?.total ?? list.length) as number }
    }),
  })

  const { data: allFirmwareList = [], error: allFirmwareError, refetch: refetchAllFirmware } = useQuery({
    queryKey: queryKeys.ota.firmwares({ all: true }),
    queryFn: () => otaApi.listFirmware({ page: 1, pageSize: 1000 }).then((r) => {
      const d = r.data; const list = d?.items ?? d?.data?.items ?? d?.data ?? []
      return (Array.isArray(list) ? list : []) as Firmware[]
    }),
  })

  const { data: deviceModels = [], error: deviceModelsError, refetch: refetchDeviceModels } = useQuery({
    queryKey: ['models', 'all'],
    queryFn: () => modelApi.listModels().then((r) => {
      const d = r.data?.data ?? r.data ?? []
      return Array.isArray(d) ? d : []
    }),
  })

  const uploadMutation = useMutation({
    mutationFn: (formData: FormData) => otaApi.uploadFirmware(formData),
    onSuccess: (res: any) => {
      const created = res?.data?.data
      if (created?.version) {
        message.success(
          t('ota.firmwareUploadDetail', {
            chip: firmwareModuleLabel(created.target_chip, t),
            version: created.version,
            size: formatFileSize(created.file_size || 0),
            sha: String(created.file_sha256 || '').slice(0, 12),
          }),
        )
      } else {
        message.success(t('ota.firmwareUploadSuccess'))
      }
      setUploadOpen(false); form.resetFields(); setFileList([])
      queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
    },
    onError: (err: any) => {
      message.error(err?.response?.data?.message || err?.message || t('ota.firmwareUploadFailed'))
    },
    onSettled: () => setUploading(false),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => otaApi.deleteFirmware(Number(id)),
    onSuccess: () => { message.success(t('ota.firmwareDeleteSuccess')); queryClient.invalidateQueries({ queryKey: queryKeys.ota.all }) },
    onError: () => message.error(t('ota.firmwareDeleteFailed')),
  })

  const publishMutation = useMutation({
    mutationFn: ({ id, data }: { id: string | number; data?: FirmwarePublishRequest }) =>
      otaApi.publishFirmware(id, data),
    onSuccess: () => {
      message.success(t('ota.firmwarePublishSuccess'))
      setPublishOpen(false)
      setPublishTarget(null)
      queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
    },
    onError: (err: any) => message.error(err?.response?.data?.message || err?.message || t('ota.firmwarePublishFailed')),
  })

  const rolloutMutation = useMutation({
    mutationFn: ({ id, data }: { id: string | number; data: FirmwarePublishRequest }) =>
      otaApi.updateFirmwareRollout(id, data),
    onSuccess: () => {
      message.success(t('ota.firmwareRolloutUpdateSuccess'))
      setPublishOpen(false)
      setPublishTarget(null)
      queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })
    },
    onError: (err: any) =>
      message.error(err?.response?.data?.message || err?.message || t('ota.firmwareRolloutUpdateFailed')),
  })

  const disableMutation = useMutation({
    mutationFn: (id: string | number) => otaApi.disableFirmware(id),
    onSuccess: () => { message.success(t('ota.firmwareDisableSuccess')); queryClient.invalidateQueries({ queryKey: queryKeys.ota.all }) },
    onError: (err: any) => message.error(err?.response?.data?.message || err?.message || t('ota.firmwareDisableFailed')),
  })

  const handleUpload = async () => {
    try {
      const values = await form.validateFields()
      if (fileList.length === 0) { message.warning(t('ota.pleaseSelectFirmware')); return }
      setUploading(true)
      const modelValue = Array.isArray(values.model) ? values.model[0] : values.model
      const formData = buildFirmwareUploadFormData({
        file: fileList[0].originFileObj,
        model: modelValue,
        targetChip: values.targetChip,
        changelog: values.changelog,
      })
      uploadMutation.mutate(formData)
    } catch { setUploading(false) }
  }

  const modelOptions = useMemo(() => {
    const firmwareModels = allFirmwareList.map((fw) => fw.model).filter(Boolean)
    const deviceModelNames = deviceModels.map((m: any) => m.model_code || m.model_name).filter(Boolean)
    return [...new Set([...firmwareModels, ...deviceModelNames])].map((m) => ({ label: m, value: m }))
  }, [allFirmwareList, deviceModels])

  const uploadProps: UploadProps = {
    accept: '.bin', maxCount: 1, fileList,
    beforeUpload: (file) => {
      setFileList([{ uid: '-1', name: file.name, status: 'done', originFileObj: file }])
      return false
    },
    onRemove: () => { setFileList([]) },
  }

  const firmwareData = firmwareRes?.items ?? []
  const queryFailure = firmwareError
    ? { error: firmwareError, retry: refetch }
    : allFirmwareError
      ? { error: allFirmwareError, retry: refetchAllFirmware }
      : deviceModelsError
        ? { error: deviceModelsError, retry: refetchDeviceModels }
        : null
  const firmwareTotal = firmwareRes?.total ?? 0

  const columns: ProColumns<Firmware>[] = [
    { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 120 },
    {
      title: t('ota.module'), dataIndex: 'target_chip', key: 'target_chip', width: 120,
      render: (_, record: Firmware) => (
        <Tag>{firmwareModuleLabel(record.target_chip, t)}</Tag>
      ),
    },
    {
      title: t('ota.releaseStatus'), dataIndex: 'release_status', key: 'release_status', width: 100,
      render: (_, record: Firmware) => {
        const st = record.release_status || 'published'
        const cfg = RELEASE_STATUS_MAP[st] || RELEASE_STATUS_MAP.published
        return <Tag color={cfg.color}>{t(cfg.i18nKey)}</Tag>
      },
    },
    {
      title: t('ota.subVersion'), dataIndex: 'version', key: 'version', width: 130,
      render: (_, record: Firmware) => (
        <Space size={6}>
          <span>{record.version}</span>
        </Space>
      ),
    },
    { title: t('ota.fileSize'), dataIndex: 'file_size', key: 'file_size', width: 100, render: (_: any, record: Firmware) => formatFileSize(record.file_size) },
    {
      title: t('ota.sha256Label'), dataIndex: 'file_sha256', key: 'file_sha256', width: 140,
      render: (_, record: Firmware) => record.file_sha256 ? (
        <Tooltip title={record.file_sha256}>
          <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{record.file_sha256.slice(0, 12)}…</span>
        </Tooltip>
      ) : <span style={{ color: '#bfbfbf' }}>-</span>,
    },
    { title: t('ota.changelog'), dataIndex: 'changelog', key: 'changelog', ellipsis: true, render: (_, record: Firmware) => <Tooltip title={record.changelog}><span>{record.changelog || '-'}</span></Tooltip> },
    {
      title: t('ota.uploadTime'), dataIndex: 'created_at', key: 'created_at', width: 160,
      render: (_: any, record: Firmware) => record.created_at ? formatInTimezone(record.created_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('ota.publishedAt'), dataIndex: 'published_at', key: 'published_at', width: 160,
      render: (_: any, record: Firmware) =>
        record.published_at ? formatInTimezone(record.published_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('ota.rolloutPercentLabel'), key: 'rollout', width: 130,
      render: (_: any, record: Firmware) => {
        const st = record.release_status || 'published'
        if (st !== 'published') return <span style={{ color: '#bfbfbf' }}>-</span>
        const pct = record.rollout_percent ?? 100
        const scope = record.rollout_type === 'device' ? t('ota.rolloutByDevice') : t('ota.rolloutAll')
        return (
          <Space direction="vertical" size={0}>
            <Tag color={pct < 100 ? 'orange' : 'blue'}>{pct}%</Tag>
            <Text type="secondary" style={{ fontSize: 12 }}>{scope}</Text>
          </Space>
        )
      },
    },
    {
      title: t('common.operation'), key: 'action', width: 240,
      render: (_: any, record: Firmware) => {
        const st = record.release_status || 'published'
        return (
          <Space size={4} wrap>
            <Tooltip title={t('ota.viewFirmwareDevices')}>
              <Button type="link" size="small" icon={<DesktopOutlined />} onClick={() => openFwDevicesModal(record)}>
                {t('ota.viewDevices')}
              </Button>
            </Tooltip>
            {canControl && st !== 'published' && (
              <Button
                type="link"
                size="small"
                onClick={() => {
                  setPublishTarget(record)
                  setPublishOpen(true)
                }}
              >
                {t('ota.publishFirmware')}
              </Button>
            )}
            {canControl && st === 'published' && (
              <Button
                type="link"
                size="small"
                onClick={() => {
                  setPublishTarget(record)
                  setPublishOpen(true)
                }}
              >
                {t('ota.adjustFirmwareRollout')}
              </Button>
            )}
            {canControl && st === 'published' && (
              <Popconfirm title={t('ota.confirmDisableFirmware')} onConfirm={() => disableMutation.mutate(record.id)}>
                <Button type="link" size="small" danger>{t('ota.disableFirmware')}</Button>
              </Popconfirm>
            )}
            {canDelete && st === 'draft' && (
              <Popconfirm title={t('ota.confirmDeleteFirmware')} onConfirm={() => deleteMutation.mutate(record.id)}>
                <Button type="link" danger icon={<DeleteOutlined />} size="small" />
              </Popconfirm>
            )}
          </Space>
        )
      },
    },
  ]

  return (
    <div>
      {queryFailure && <QueryErrorAlert error={queryFailure.error} onRetry={() => { void queryFailure.retry() }} style={{ marginBottom: 16 }} />}
      <ProCard style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            {canCreate && (
              <Button type="primary" icon={<UploadOutlined />} onClick={() => setUploadOpen(true)}>{t('ota.uploadFirmware')}</Button>
            )}
          </Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByModel')} style={{ width: 180 }} value={modelFilter}
              onChange={(val) => { setModelFilter(val); setPage(1) }}
              options={[...new Set(firmwareData.map((d) => d.model))].map((m) => ({ label: m, value: m }))} />
          </Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByModule')} style={{ width: 140 }} value={chipFilter}
              onChange={(val) => { setChipFilter(val); setPage(1) }}
              options={[
                { label: firmwareModuleLabel('esp', t), value: 'esp' },
                { label: firmwareModuleLabel('arm', t), value: 'arm' },
                { label: firmwareModuleLabel('dsp', t), value: 'dsp' },
                { label: firmwareModuleLabel('bms', t), value: 'bms' },
              ]} />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
          <Col>
            <span style={{ color: '#999', fontSize: 12 }}>{t('ota.firmwareLifecycleHint')}</span>
          </Col>
        </Row>
      </ProCard>
      <ProTable<Firmware> rowKey="id" columns={columns} dataSource={firmwareData} loading={isLoading} size="middle"
        search={false}
        options={{ density: true, reload: () => refetch(), setting: true }}
        pagination={{ current: page, pageSize, total: firmwareTotal, showSizeChanger: true, showTotal: (total) => t('common.total', { total }), onChange: (p, ps) => { setPage(p); setPageSize(ps) } }} />

      <FirmwarePublishModal
        open={publishOpen}
        firmware={publishTarget}
        publishedPeers={allFirmwareList as Firmware[]}
        confirmLoading={publishMutation.isPending || rolloutMutation.isPending}
        onCancel={() => { setPublishOpen(false); setPublishTarget(null) }}
        onOk={(values) => {
          if (!publishTarget) return
          if ((publishTarget.release_status || 'draft') === 'published') {
            rolloutMutation.mutate({ id: publishTarget.id, data: values })
          } else {
            publishMutation.mutate({ id: publishTarget.id, data: values })
          }
        }}
      />

      <Modal title={t('ota.uploadFirmwareTitle')} open={uploadOpen}
        onCancel={() => { setUploadOpen(false); form.resetFields(); setFileList([]) }}
        onOk={handleUpload} confirmLoading={uploading} destroyOnClose width={560}>
        <Form form={form} layout="vertical">
          <Form.Item name="model" label={t('ota.model')} rules={[{ required: true, message: t('ota.pleaseSelectOrInputModel') }]}>
            <Select showSearch allowClear mode="tags" maxCount={1} placeholder={t('ota.selectOrInputModel')} options={modelOptions}
              filterOption={(input, option) => (option?.label as string)?.toLowerCase().includes(input.toLowerCase())} />
          </Form.Item>
          <Form.Item name="targetChip" label={t('ota.module')} rules={[{ required: true, message: t('ota.pleaseSelectTargetChip') }]}>
            {/* 管理员上传需展示芯片型号括号，与用户侧「通信采集/系统中控」区分 */}
            <Select placeholder={t('ota.pleaseSelectTargetChip')}>
              <Select.Option value="esp">{t('ota.espChip')}</Select.Option>
              <Select.Option value="arm">{t('ota.armChip')}</Select.Option>
              <Select.Option value="dsp">{t('ota.dspChip')}</Select.Option>
              <Select.Option value="bms">{t('ota.bmsChip')}</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="changelog" label={t('ota.changelog')}><TextArea rows={3} placeholder={t('ota.inputChangelog')} /></Form.Item>
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

      <Modal
        title={t('ota.firmwareDevices')}
        open={fwDevicesOpen}
        onCancel={() => { setFwDevicesOpen(false); setFwDevicesTarget(null); setFwDevices([]) }}
        width={780}
        destroyOnClose
        footer={[
          <Button key="close" onClick={() => { setFwDevicesOpen(false); setFwDevicesTarget(null); setFwDevices([]) }}>
            {t('common.close')}
          </Button>,
        ]}
      >
        {fwDevicesTarget && (
          <div>
            <Descriptions column={3} size="small" bordered style={{ marginBottom: 16 }}>
              <Descriptions.Item label={t('ota.model')}>{fwDevicesTarget.model}</Descriptions.Item>
              <Descriptions.Item label={t('ota.module')}>
                <Tag>{firmwareModuleLabel(fwDevicesTarget.target_chip, t)}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label={t('ota.versionName')}>{fwDevicesTarget.version}</Descriptions.Item>
            </Descriptions>
            <ProTable
              rowKey="sn"
              size="small"
              search={false}
              loading={fwDevicesLoading}
              dataSource={fwDevices}
              pagination={{ pageSize: 10 }}
              locale={{ emptyText: <Empty description={t('ota.noFirmwareDevices')} /> }}
              columns={[
                { title: t('common.deviceSN'), dataIndex: 'sn', key: 'sn', width: 140 },
                { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 100 },
                { title: firmwareModuleLabel('arm', t), dataIndex: 'firmware_arm', key: 'firmware_arm', width: 110, render: (_: any, record: any) => record.firmware_arm || '-' },
                { title: firmwareModuleLabel('esp', t), dataIndex: 'firmware_esp', key: 'firmware_esp', width: 110, render: (_: any, record: any) => record.firmware_esp || '-' },
                { title: firmwareModuleLabel('dsp', t), dataIndex: 'firmware_dsp', key: 'firmware_dsp', width: 110, render: (_: any, record: any) => record.firmware_dsp || '-' },
                { title: firmwareModuleLabel('bms', t), dataIndex: 'firmware_bms', key: 'firmware_bms', width: 110, render: (_: any, record: any) => record.firmware_bms || '-' },
              ]}
            />
          </div>
        )}
      </Modal>
    </div>
  )
}

// =================== Tab: App版本管理 ===================
const AppVersionTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  const hasAnyPermission = useAuthStore((s) => s.hasAnyPermission)
  const canCreate = canMutateOta('create', isSystemAdmin, hasAnyPermission)
  const canControl = canMutateOta('control', isSystemAdmin, hasAnyPermission)
  const canDelete = canMutateOta('delete', isSystemAdmin, hasAnyPermission)

  const [platformFilter, setPlatformFilter] = useState<string>()
  const [createOpen, setCreateOpen] = useState(false)
  const [apkList, setApkList] = useState<any[]>([])
  const [uploading, setUploading] = useState(false)
  const [rolloutModalOpen, setRolloutModalOpen] = useState(false)
  const [rolloutTarget, setRolloutTarget] = useState<any>(null)
  const [rolloutPercent, setRolloutPercent] = useState<number>(100)
  const [form] = Form.useForm()

  const { data: versionData = [], isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.ota.appVersions(platformFilter ? { platform: platformFilter } : undefined),
    queryFn: () => otaApi.getAppVersions(platformFilter).then((r) => {
      const d = r.data; const list = d?.data ?? d?.items ?? d ?? []
      return Array.isArray(list) ? list : []
    }),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.ota.appVersionsAll() })

  const resetCreateForm = () => {
    setCreateOpen(false); form.resetFields(); setApkList([]); setUploading(false)
  }

  const createMutation = useMutation({
    mutationFn: (formData: FormData) => otaApi.uploadAppPackage(formData),
    onSuccess: (res: any) => {
      const created = res?.data?.data
      message.success(
        created
          ? t('ota.appVersionUploadSuccess', { version: created.version_name, version_code: created.version_code })
          : t('ota.versionPublishSuccess'),
      )
      resetCreateForm(); invalidate()
    },
    onError: (err: any) => {
      message.error(err?.response?.data?.message || err?.message || t('ota.versionPublishFailed'))
    },
    onSettled: () => setUploading(false),
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
      if (apkList.length === 0) { message.warning(t('ota.apkRequired')); return }
      setUploading(true)
      const formData = new FormData()
      formData.append('file', apkList[0].originFileObj)
      formData.append('platform', values.platform || 'android')
      formData.append('changelog', values.changelog || '')
      formData.append('is_force', values.isForce ? 'true' : 'false')
      formData.append('min_supported_version', String(values.minSupportedVersion || 0))
      formData.append('rollout_percentage', String(values.rolloutPercentage ?? 100))
      createMutation.mutate(formData)
    } catch { setUploading(false) }
  }

  const apkUploadProps: UploadProps = {
    accept: '.apk', maxCount: 1, fileList: apkList,
    beforeUpload: (file) => {
      setApkList([{ uid: '-1', name: file.name, status: 'done', originFileObj: file }])
      return false
    },
    onRemove: () => { setApkList([]) },
  }

  const openRolloutModal = (record: any) => {
    setRolloutTarget(record); setRolloutPercent(record.rollout_percentage ?? 100); setRolloutModalOpen(true)
  }

  const handleRollout = () => {
    if (!rolloutTarget) return
    rolloutMutation.mutate({ id: rolloutTarget.id, percentage: rolloutPercent })
  }

  const ROLLOUT_MARKS: Record<number, string> = { 0: '0%', 10: '10%', 25: '25%', 50: '50%', 75: '75%', 100: '100%' }

  const columns: ProColumns<any>[] = [
    {
      title: t('ota.platform'), dataIndex: 'platform', key: 'platform', width: 90,
      render: (_, record: any) => <Tag icon={record.platform === 'ios' ? <AppleOutlined /> : <AndroidOutlined />} color={record.platform === 'ios' ? '#000' : '#52c41a'}>{record.platform === 'ios' ? 'iOS' : 'Android'}</Tag>,
    },
    {
      title: t('ota.versionName'), dataIndex: 'version_name', key: 'version_name', width: 130,
      render: (_, record: any) => (
        <Space size={6}>
          <Tag color="blue">v{record.version_name}</Tag>
          <span style={{ fontSize: 12, color: '#8c8c8c' }}>#{record.version_code}</span>
        </Space>
      ),
    },
    {
      title: t('ota.packageName'), dataIndex: 'package_name', key: 'package_name', width: 170, ellipsis: true,
      render: (_, record: any) => record.package_name
        ? <Tooltip title={record.package_name}><span style={{ fontFamily: 'monospace', fontSize: 12 }}>{record.package_name}</span></Tooltip>
        : <span style={{ color: '#bfbfbf' }}>-</span>,
    },
    {
      title: t('ota.fileSize'), dataIndex: 'file_size', key: 'file_size', width: 100,
      render: (_, record: any) => (record.file_size ? formatFileSize(record.file_size) : '-'),
    },
    {
      title: t('ota.sha256Label'), dataIndex: 'file_sha256', key: 'file_sha256', width: 150,
      render: (_, record: any) => record.file_sha256 ? (
        <Tooltip title={record.file_sha256}>
          <span style={{ fontFamily: 'monospace', fontSize: 12 }}>{record.file_sha256.slice(0, 12)}…</span>
        </Tooltip>
      ) : <span style={{ color: '#bfbfbf' }}>-</span>,
    },
    { title: t('ota.downloadUrl'), dataIndex: 'download_url', key: 'download_url', ellipsis: true, render: (_, record: any) => <Tooltip title={record.download_url}><span style={{ fontFamily: 'monospace', fontSize: 12 }}>{record.download_url || '-'}</span></Tooltip> },
    { title: t('ota.forceUpdate'), dataIndex: 'is_force', key: 'is_force', width: 80, render: (_, record: any) => record.is_force ? <Tag color="red">{t('ota.force')}</Tag> : <Tag>{t('common.no')}</Tag> },
    {
      title: t('ota.rolloutPercent'), dataIndex: 'rollout_percentage', key: 'rollout_percentage', width: 120,
      render: (_, record: any) => {
        if (record.is_rolled_back) return <Tag color="red">{t('ota.rolledBack')}</Tag>
        const pct = record.rollout_percentage ?? 100
        return <Space><Progress percent={pct} size="small" style={{ width: 60 }} /><span style={{ fontSize: 12 }}>{pct}%</span></Space>
      },
    },
    { title: t('ota.changelog'), dataIndex: 'changelog', key: 'changelog', ellipsis: true, render: (_, record: any) => <Tooltip title={record.changelog}><span>{record.changelog || '-'}</span></Tooltip> },
    { title: t('ota.publishTime'), dataIndex: 'created_at', key: 'created_at', width: 150, render: (_, record: any) => record.created_at ? formatInTimezone(record.created_at, timezone, 'YYYY-MM-DD HH:mm') : '-' },
    {
      title: t('common.operation'), key: 'action', width: 200,
      render: (_: any, record: any) => (
        <Space>
          {record.is_rolled_back ? (
            canControl && (
              <Popconfirm title={t('ota.confirmRestore')} onConfirm={() => restoreMutation.mutate(record.id)}>
                <Button type="link" size="small" icon={<RedoOutlined />} loading={restoreMutation.isPending}>{t('ota.restore')}</Button>
              </Popconfirm>
            )
          ) : (
            <>
              {canControl && (
                <Button type="link" size="small" icon={<SafetyOutlined />} onClick={() => openRolloutModal(record)}>{t('ota.grayRelease')}</Button>
              )}
              {canControl && (
                <Popconfirm title={t('ota.confirmAppRollback')} onConfirm={() => rollbackMutation.mutate(record.id)}>
                  <Button type="link" size="small" danger icon={<RollbackOutlined />} loading={rollbackMutation.isPending}>{t('ota.rollback')}</Button>
                </Popconfirm>
              )}
            </>
          )}
          {canDelete && (
            <Popconfirm title={t('ota.confirmDeleteVersion')} onConfirm={() => deleteMutation.mutate(record.id)}>
              <Button type="link" danger icon={<DeleteOutlined />} size="small" />
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ]

  return (
    <div>
      {error && <QueryErrorAlert error={error} onRetry={() => { void refetch() }} style={{ marginBottom: 16 }} />}
      <ProCard style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            {canCreate && (
              <Button type="primary" icon={<CloudUploadOutlined />} onClick={() => setCreateOpen(true)}>{t('ota.uploadApk')}</Button>
            )}
          </Col>
          <Col>
            <Select allowClear placeholder={t('ota.filterByPlatform')} style={{ width: 140 }} value={platformFilter}
              onChange={(val) => setPlatformFilter(val)} options={[{ label: 'Android', value: 'android' }, { label: 'iOS', value: 'ios' }]} />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
        </Row>
      </ProCard>
      <ProTable rowKey="id" columns={columns} dataSource={versionData} loading={isLoading} size="middle"
        search={false}
        options={{ density: true, reload: () => refetch(), setting: true }}
        pagination={false} />

      <Modal title={t('ota.uploadApkTitle')} open={createOpen} onCancel={resetCreateForm}
        onOk={handleCreate} okText={t('ota.uploadAndPublish')}
        confirmLoading={uploading || createMutation.isPending} destroyOnClose width={600}>
        <Form form={form} layout="vertical">
          <Alert type="info" showIcon style={{ marginBottom: 16 }} message={t('ota.apkAutoParseHint')} />
          <Form.Item name="platform" label={t('ota.platform')} initialValue="android">
            <Select>
              <Select.Option value="android"><AndroidOutlined style={{ color: '#52c41a', marginRight: 4 }} /> Android</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item label={t('ota.uploadApk')} required>
            <Dragger {...apkUploadProps}>
              <p className="ant-upload-drag-icon"><InboxOutlined /></p>
              <p className="ant-upload-text">{t('ota.dragApk')}</p>
              <p className="ant-upload-hint">{t('ota.apkFormatHint')}</p>
            </Dragger>
          </Form.Item>
          {apkList.length > 0 && (
            <Form.Item label={t('ota.detectedMeta')}>
              <Space direction="vertical" size={2} style={{ width: '100%' }}>
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                  {formatFileSize(apkList[0]?.originFileObj?.size || 0)}
                </Typography.Text>
                <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                  {t('ota.versionName')} / {t('ota.packageName')} / {t('ota.sha256Label')}：{t('ota.pendingParse')}
                </Typography.Text>
              </Space>
            </Form.Item>
          )}
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
