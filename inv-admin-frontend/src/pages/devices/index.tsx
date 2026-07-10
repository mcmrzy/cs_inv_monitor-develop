import { useState, useCallback, useEffect, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Button, Input, Select, Space, Modal, Form,
  Drawer, Descriptions, Slider, Tooltip, Popconfirm, message, Typography,
  Dropdown, Tag, DatePicker, Divider, Spin, Empty, Upload, Tabs, Timeline,
  Input as AntInput, InputNumber, Switch, Alert, List, Grid,
} from 'antd'
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table'
import type { MenuProps } from 'antd'
import {
  PlusOutlined, SearchOutlined, ReloadOutlined, SettingOutlined,
  DownloadOutlined, DeleteOutlined, LinkOutlined, EditOutlined,
  EyeOutlined, ExclamationCircleOutlined, ThunderboltOutlined,
  UploadOutlined, InboxOutlined, CheckOutlined, CloseOutlined,
  DisconnectOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import ReactECharts from 'echarts-for-react'
import { deviceApi } from '@/services/deviceApi'
import api from '@/services/api'
import { commandApi } from '@/services/commandApi'
import { modelApi } from '@/services/modelApi'
import { userApi } from '@/services/userApi'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import useTranslation from '@/hooks/useTranslation'
import StatusBadge from '@/components/StatusBadge'
import { useModelFields, DynamicFieldRenderer, DynamicStatCards } from '@/components/dyna'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'

const { Text, Title } = Typography
const { RangePicker } = DatePicker
const { Dragger } = Upload

interface DeviceRecord {
  id: string
  sn: string
  model: string
  ratedPower: number
  firmwareVersion: string
  hardwareVersion?: string
  status: number
  lastOnlineAt: string
  userId: string
  installerId: string
  timezone?: string
  station_id?: number
  station_name?: string
  user_phone?: string
  owner?: { phone: string; nickname: string }
  installer?: { nickname: string; phone: string }
}

interface RealtimeData {
  ac?: { voltage: number; current: number; power: number; frequency: number; powerFactor: number }
  pv?: { voltage: number; current: number; power: number }
  battery?: { soc: number; voltage: number; current: number; temp: number }
  system?: { state: string; fault_code: number; temp_inv: number; temp_ambient: number }
  online?: { online: boolean; rssi: number; ip: string }
  [key: string]: any
}

interface DeviceFilters {
  keyword?: string
  status?: string
  model?: string
  lastOnlineRange?: [string, string]
}

interface ExcelPreviewRow {
  SN: string
  Model: string
  'RatedPower(kW)': number | string
  FirmwareVersion: string
  HardwareVersion: string
  StationName: string
  error?: string
}

interface UnbindRequestRecord {
  id: number
  device_sn: string
  requested_by: number
  reason: string
  status: string
  reviewed_by: number
  review_comment: string
  reviewed_at: string
  created_at: string
}

interface LifecycleRecord {
  id: number
  device_sn: string
  event_type: string
  description: string
  triggered_by: number
  metadata: any
  created_at: string
}

interface CommandParam {
  name: string
  label: string
  type: 'number' | 'string' | 'boolean' | 'select'
  required: boolean
  options?: { label: string; value: any }[]
  min?: number
  max?: number
  defaultValue?: any
  unit?: string
}

interface CommandTemplate {
  name: string
  label: string
  description: string
  category: 'power' | 'battery' | 'grid' | 'system' | 'ota'
  params: CommandParam[]
  requiresConfirm: boolean
  confirmationMessage?: string
}

interface CommandHistoryRecord {
  id: number
  device_sn: string
  command_name: string
  command_label: string
  params: any
  req_id: string
  status: string
  result_message: string
  executed_by: number
  ip_address: string
  retry_count: number
  created_at: string
  completed_at: string
}

const COMMAND_STATUS_COLORS: Record<string, string> = {
  pending: 'default',
  queued: 'gold',
  sent: 'processing',
  ack_received: 'blue',
  success: 'green',
  failed: 'red',
  timeout: 'orange',
}

const LIFECYCLE_EVENT_COLORS: Record<string, string> = {
  registered: 'green',
  bound: 'blue',
  unbound: 'orange',
  activated: 'cyan',
  decommissioned: 'red',
  maintenance: 'purple',
  firmware_upgrade: 'geekblue',
  hardware_replace: 'volcano',
}

const DevicesPage: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { timezone } = useTimezoneStore()

  const COMMAND_CATEGORY_LABELS: Record<string, string> = {
    power: t('dev.powerControl'),
    battery: t('dev.batteryManage'),
    grid: t('dev.gridProtect'),
    system: t('dev.systemControl'),
    ota: t('dev.remoteUpgrade'),
  }

  const LIFECYCLE_EVENT_LABELS: Record<string, string> = {
    registered: t('dev.register'),
    bound: t('dev.bind'),
    unbound: t('dev.unbindAction'),
    activated: t('dev.activate'),
    decommissioned: t('dev.retire'),
    maintenance: t('dev.maintenance'),
    firmware_upgrade: t('dev.firmwareUpgrade'),
    hardware_replace: t('dev.hardwareReplace'),
  }

  const { user } = useAuthStore()
  const [messageApi, contextHolder] = message.useMessage()
  const screens = Grid.useBreakpoint()
  const isEndUser = user?.role === Role.END_USER
  const isInstaller = user?.role === Role.INSTALLER
  const isSuperAdmin = user?.role === Role.SUPER_ADMIN
  const isAgent = user?.role === Role.AGENT
  const canDirectUnbind = isSuperAdmin || isAgent

  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [filters, setFilters] = useState<DeviceFilters>({})
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([])

  const [addModalOpen, setAddModalOpen] = useState(false)
  const [editModalOpen, setEditModalOpen] = useState(false)
  const [editingDevice, setEditingDevice] = useState<DeviceRecord | null>(null)
  const [addForm] = Form.useForm()
  const [editForm] = Form.useForm()

  const [detailDrawerOpen, setDetailDrawerOpen] = useState(false)
  const [detailDevice, setDetailDevice] = useState<DeviceRecord | null>(null)
  const [detailSn, setDetailSn] = useState<string>('')
  const [telemetryRange, setTelemetryRange] = useState<[dayjs.Dayjs, dayjs.Dayjs]>([
    dayjs().subtract(1, 'day'),
    dayjs(),
  ])
  const [powerLimit, setPowerLimit] = useState<number>(0)
  const [drawerTab, setDrawerTab] = useState<string>('info')
  const [telemetryVersion, setTelemetryVersion] = useState(0)

  const [selectedCommand, setSelectedCommand] = useState<CommandTemplate | null>(null)
  const [commandParams, setCommandParams] = useState<Record<string, any>>({})
  const [executing, setExecuting] = useState(false)
  const [confirmModalOpen, setConfirmModalOpen] = useState(false)
  const [pendingExecution, setPendingExecution] = useState<{ commandName: string; params: Record<string, any> } | null>(null)
  const [commandResult, setCommandResult] = useState<{ success: boolean; message: string } | null>(null)

  const [importModalOpen, setImportModalOpen] = useState(false)
  const [importFile, setImportFile] = useState<File | null>(null)
  const [importPreview, setImportPreview] = useState<ExcelPreviewRow[]>([])
  const [importResult, setImportResult] = useState<{ success: number; failed: number; errors: { row: number; message: string }[] } | null>(null)
  const [importing, setImporting] = useState(false)

  const [unbindModalOpen, setUnbindModalOpen] = useState(false)
  const [unbindTargetSn, setUnbindTargetSn] = useState<string>('')
  const [unbindReason, setUnbindReason] = useState('')
  const [unbindApprovalTab, setUnbindApprovalTab] = useState<string>('devices')
  const [unbindReqPage, setUnbindReqPage] = useState(1)
  const [unbindReqPageSize, setUnbindReqPageSize] = useState(10)

  // 分配安装商相关状态
  const [assignModalOpen, setAssignModalOpen] = useState(false)
  const [assignTargetSn, setAssignTargetSn] = useState<string>('')
  const [selectedInstallerId, setSelectedInstallerId] = useState<number | null>(null)

  // 绑定电站相关状态
  const [bindStationModalOpen, setBindStationModalOpen] = useState(false)
  const [bindStationSn, setBindStationSn] = useState<string>('')
  const [selectedStationId, setSelectedStationId] = useState<number | null>(null)

  const [modelOptions, setModelOptions] = useState<{ label: string; value: string }[]>([])
  const modelFields = useModelFields(detailDevice?.model)

  const buildQueryParams = useCallback(() => {
    const params: any = {
      page,
      pageSize,
    }
    if (filters.keyword) params.keyword = filters.keyword
    if (filters.status) params.status = filters.status
    if (filters.model) params.model = filters.model
    if (filters.lastOnlineRange) {
      params.lastOnlineStart = filters.lastOnlineRange[0]
      params.lastOnlineEnd = filters.lastOnlineRange[1]
    }
    if (isInstaller) params.installerId = user?.id
    if (isEndUser) params.userId = user?.id
    return params
  }, [page, pageSize, filters, isInstaller, isEndUser, user?.id])

  const { data: devicesRes, isLoading: devicesLoading } = useQuery({
    queryKey: ['devices', buildQueryParams()],
    queryFn: () =>
      deviceApi.getDevices(buildQueryParams()).then((res) => {
        const d = res.data
        const inner = d?.data ?? d
        return {
          items: (inner?.items ?? []) as DeviceRecord[],
          total: (inner?.total ?? 0) as number,
        }
      }),
  })

  const { data: deviceDetailRaw } = useQuery({
    queryKey: ['deviceDetail', detailSn],
    queryFn: () =>
      deviceApi.getDeviceBySn(detailSn).then((res) => {
        const d = res.data
        const inner = d?.data ?? d ?? {}
        return inner as { device?: DeviceRecord; realtime_data?: any; online_status?: any }
      }),
    enabled: !!detailSn && detailDrawerOpen,
  })

  const { data: realtimeData, isLoading: realtimeLoading } = useQuery({
    queryKey: ['deviceRealtime', detailSn],
    queryFn: () =>
      deviceApi.getRealtime(detailSn).then((res) => {
        const d = res.data
        const inner = d?.data ?? d ?? {}
        const raw = inner?.realtime ?? inner

        const acObj = raw?.ac || (raw?.voltage != null ? raw : null)
        const pvObj = raw?.pv || (raw?.pv_voltage != null ? raw : null)
        const batObj = raw?.battery || raw?.batt || (raw?.soc != null ? raw : null)
        const sysObj = raw?.sys_status || raw?.sys || raw

        return {
          ac: acObj ? {
            voltage: acObj.voltage || 0,
            current: acObj.current || 0,
            power: acObj.power || 0,
            frequency: acObj.frequency || 0,
            powerFactor: acObj.powerFactor || acObj.pf || 0,
          } : undefined,
          pv: pvObj ? {
            voltage: pvObj.pv_voltage || pvObj.voltage || 0,
            current: pvObj.pv_current || pvObj.current || 0,
            power: pvObj.pv_power || pvObj.power || 0,
          } : undefined,
          battery: batObj ? {
            soc: batObj.soc || 0,
            voltage: batObj.voltage || 0,
            current: batObj.current || 0,
            temp: batObj.temp || batObj.temp_bat || 0,
          } : undefined,
          system: {
            state: sysObj.state || raw?.charge_state || '-',
            fault_code: sysObj.fault_code || 0,
            temp_inv: sysObj.temp_inv || 0,
            temp_ambient: sysObj.temp_mos || sysObj.temp_env || 0,
          },
          online: { online: raw?.online ?? false, rssi: raw?.rssi || 0, ip: raw?.ip || '' },
          _raw: raw,
        } as RealtimeData
      }),
    enabled: !!detailSn && detailDrawerOpen,
    refetchInterval: 5000,
  })

  const [telemetryData, setTelemetryData] = useState<any[]>([]);
  const [telemetryLoading, setTelemetryLoading] = useState(false);

  const fetchTelemetry = useCallback(async (sn: string, range: [dayjs.Dayjs, dayjs.Dayjs]) => {
    if (!sn) return;
    setTelemetryLoading(true);
    try {
      const s = range[0].toISOString();
      const e = range[1].toISOString();
      const res = await deviceApi.getTelemetry(sn, { startTime: s, endTime: e, pageSize: 500 });
      const payload = res.data;
      const inner = payload?.data ?? payload;
      const items = Array.isArray(inner?.items) ? inner.items : (Array.isArray(inner) ? inner : []);
      setTelemetryData(items);
    } catch (err: any) {
      setTelemetryData([]);
    } finally {
      setTelemetryLoading(false);
    }
  }, []);

  useEffect(() => {
    if (detailDrawerOpen && detailSn) {
      fetchTelemetry(detailSn, telemetryRange);
    }
  }, [detailDrawerOpen, detailSn, telemetryRange, telemetryVersion, fetchTelemetry]);

  useEffect(() => {
    modelApi.listModels().then((res) => {
      const models = res.data?.data ?? res.data ?? []
      setModelOptions(
        models.map((m: any) => ({
          label: `${m.model_name} (${m.model_code})`,
          value: m.model_code,
        })),
      )
    }).catch(() => {})
  }, [])

  const { data: lifecycleRes } = useQuery({
    queryKey: ['deviceLifecycle', detailSn],
    queryFn: () =>
      deviceApi.getLifecycleHistory(detailSn).then((res) => {
        const d = res.data
        const inner = d?.data ?? d
        return {
          items: (inner?.items ?? []) as LifecycleRecord[],
          total: (inner?.total ?? 0) as number,
        }
      }),
    enabled: !!detailSn && detailDrawerOpen,
  })

  const { data: unbindRequestsRes } = useQuery({
    queryKey: ['unbindRequests', unbindReqPage, unbindReqPageSize],
    queryFn: () =>
      deviceApi.getUnbindRequests({ page: unbindReqPage, pageSize: unbindReqPageSize }).then((res) => {
        const d = res.data
        const inner = d?.data ?? d
        return {
          items: (inner?.items ?? []) as UnbindRequestRecord[],
          total: (inner?.total ?? 0) as number,
        }
      }),
    enabled: canDirectUnbind && unbindApprovalTab === 'approvals',
  })

  const { data: commandTemplatesRes } = useQuery({
    queryKey: ['commandTemplates', detailSn],
    queryFn: () =>
      commandApi.getTemplates(detailSn).then((res) => {
        const d = res.data
        const inner = d?.data ?? d
        if (Array.isArray(inner)) return inner as CommandTemplate[]
        if (inner?.items && Array.isArray(inner.items)) return inner.items as CommandTemplate[]
        return [] as CommandTemplate[]
      }),
    enabled: !!detailSn && detailDrawerOpen,
  })

  const { data: commandHistoryRes } = useQuery({
    queryKey: ['commandHistory', detailSn],
    queryFn: () =>
      commandApi.getHistory(detailSn, { pageSize: 50 }).then((res) => {
        const d = res.data
        const inner = d?.data ?? d
        return {
          items: (inner?.items ?? []) as CommandHistoryRecord[],
          total: (inner?.total ?? 0) as number,
        }
      }),
    enabled: !!detailSn && detailDrawerOpen,
  })

  const commandTemplates = Array.isArray(commandTemplatesRes) ? commandTemplatesRes : []
  const commandHistory = commandHistoryRes?.items ?? []

  const createMutation = useMutation({
    mutationFn: (data: any) => deviceApi.createDevice(data).then((r) => r.data),
    onSuccess: () => {
      messageApi.success(t('dev.addSuccess'))
      setAddModalOpen(false)
      addForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => {
      messageApi.error(t('dev.addFailed'))
    },
  })

  const updateMutation = useMutation({
    mutationFn: (data: any) => deviceApi.updateDevice(data.sn, data).then((r) => r.data),
    onSuccess: () => {
      messageApi.success(t('dev.updateSuccess'))
      setEditModalOpen(false)
      editForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => {
      messageApi.error(t('dev.updateFailed'))
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (sn: string) => deviceApi.deleteDevice(sn),
    onSuccess: () => {
      messageApi.success(t('dev.deleteSuccess'))
      queryClient.invalidateQueries({ queryKey: ['devices'] })
      setSelectedRowKeys([])
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || err?.message || t('dev.deleteFailed')),
  })

  const unbindMutation = useMutation({
    mutationFn: (sn: string) => deviceApi.unbindDevice(sn),
    onSuccess: () => {
      messageApi.success(t('dev.unbindSuccess'))
      queryClient.invalidateQueries({ queryKey: ['devices'] })
      setSelectedRowKeys([])
    },
    onError: () => messageApi.error(t('dev.unbindFailed')),
  })

  const requestUnbindMutation = useMutation({
    mutationFn: ({ sn, reason }: { sn: string; reason: string }) =>
      deviceApi.requestUnbind(sn, reason),
    onSuccess: () => {
      messageApi.success(t('dev.unbindSubmitted'))
      setUnbindModalOpen(false)
      setUnbindReason('')
      setUnbindTargetSn('')
    },
    onError: () => messageApi.error(t('dev.submitFailed')),
  })

  const approveUnbindMutation = useMutation({
    mutationFn: ({ id, comment }: { id: number; comment?: string }) =>
      deviceApi.approveUnbind(id, comment),
    onSuccess: () => {
      messageApi.success(t('dev.unbindApproved'))
      queryClient.invalidateQueries({ queryKey: ['unbindRequests'] })
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => messageApi.error(t('dev.approveFailed')),
  })

  const rejectUnbindMutation = useMutation({
    mutationFn: ({ id, comment }: { id: number; comment?: string }) =>
      deviceApi.rejectUnbind(id, comment),
    onSuccess: () => {
      messageApi.success(t('dev.unbindRejected'))
      queryClient.invalidateQueries({ queryKey: ['unbindRequests'] })
    },
    onError: () => messageApi.error(t('dev.approveFailed')),
  })

  // 获取安装商列表
  const { data: installersRes } = useQuery({
    queryKey: ['users', 'installers'],
    queryFn: () =>
      userApi.list({ role: 2, pageSize: 100 }).then((res) => {
        const d = res.data?.data ?? res.data
        const items = Array.isArray(d) ? d : (d?.items ?? [])
        return items as Array<{ id: number; nickname: string; phone: string }>
      }),
    enabled: assignModalOpen,
  })

  const assignInstallerMutation = useMutation({
    mutationFn: ({ sn, installerId }: { sn: string; installerId: number }) =>
      deviceApi.assignInstaller(sn, installerId),
    onSuccess: () => {
      messageApi.success(t('dev.assignSuccess'))
      setAssignModalOpen(false)
      setAssignTargetSn('')
      setSelectedInstallerId(null)
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => messageApi.error(t('dev.assignFailed')),
  })

  // 获取电站列表（用于绑定电站下拉）
  const { data: stationsList = [] } = useQuery({
    queryKey: ['stations-for-bind'],
    queryFn: () => api.get('/stations', { params: { pageSize: 200 } }).then((res: any) => {
      const d = res.data
      return Array.isArray(d) ? d : d?.data?.list || d?.list || d?.data || []
    }),
    enabled: bindStationModalOpen,
  })

  const bindStationMutation = useMutation({
    mutationFn: ({ sn, stationId }: { sn: string; stationId: number }) =>
      deviceApi.addToStation(sn, stationId),
    onSuccess: () => {
      messageApi.success(t('dev.bindStationSuccess'))
      setBindStationModalOpen(false)
      setSelectedStationId(null)
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: (err: any) => {
      messageApi.error(err?.response?.data?.message || err?.message || t('common.error'))
    },
  })

  const removeFromStationMutation = useMutation({
    mutationFn: (sn: string) => deviceApi.removeFromStation(sn),
    onSuccess: () => {
      messageApi.success(t('dev.removeFromStationSuccess'))
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: (err: any) => {
      messageApi.error(err?.response?.data?.message || err?.message || t('common.error'))
    },
  })

  const handleAdd = () => {
    setAddModalOpen(true)
  }

  const handleAddSubmit = async () => {
    try {
      const values = await addForm.validateFields()
      createMutation.mutate(values)
    } catch {
      // validation failed
    }
  }

  const handleEdit = (record: any) => {
    setEditingDevice(record)
    editForm.setFieldsValue({
      sn: record.sn,
      model: record.model,
      ratedPower: record.rated_power,
      firmwareVersion: record.firmware_arm,
      hardwareVersion: record.firmware_esp,
    })
    setEditModalOpen(true)
  }

  const handleEditSubmit = async () => {
    try {
      const values = await editForm.validateFields()
      updateMutation.mutate(values)
    } catch {
      // validation failed
    }
  }

  const handleSearch = () => {
    setPage(1)
    queryClient.invalidateQueries({ queryKey: ['devices'] })
  }

  const handleReset = () => {
    setFilters({})
    setPage(1)
    queryClient.invalidateQueries({ queryKey: ['devices'] })
  }

  const handleTableChange = (pagination: TablePaginationConfig) => {
    setPage(pagination.current ?? 1)
    setPageSize(pagination.pageSize ?? 20)
  }

  const openDeviceDetail = (sn: string) => {
    setDetailSn(sn)
    setDrawerTab('info')
    setDetailDrawerOpen(true)
    setSelectedCommand(null)
    setCommandParams({})
    setCommandResult(null)
    setTelemetryVersion(v => v + 1)
  }

  const handleCommandSelect = (commandName: string) => {
    const template = commandTemplates.find((t) => t.name === commandName)
    setSelectedCommand(template || null)
    if (template && Array.isArray(template.params)) {
      const defaults: Record<string, any> = {}
      template.params.forEach((p) => {
        if (p.defaultValue !== undefined) {
          defaults[p.name] = p.defaultValue
        }
      })
      setCommandParams(defaults)
    } else {
      setCommandParams({})
    }
    setCommandResult(null)
  }

  const handleParamChange = (name: string, value: any) => {
    setCommandParams((prev) => ({ ...prev, [name]: value }))
  }

  const handleExecuteCommand = () => {
    if (!selectedCommand || !detailSn) return

    if (selectedCommand.requiresConfirm) {
      setPendingExecution({
        commandName: selectedCommand.name,
        params: commandParams,
      })
      setConfirmModalOpen(true)
      return
    }

    doExecuteCommand(selectedCommand.name, commandParams)
  }

  const doExecuteCommand = async (commandName: string, params: Record<string, any>) => {
    setExecuting(true)
    setCommandResult(null)
    try {
      const res = await commandApi.execute(detailSn, {
        command: commandName,
        params,
      })
      const result = res.data?.data ?? res.data
      setCommandResult({ success: result?.success ?? true, message: result?.message ?? t('dev.commandSent') })
      if (result?.success !== false) {
        messageApi.success(t('dev.commandSent'))
      } else {
        messageApi.warning(result?.message || t('dev.commandFailed'))
      }
      queryClient.invalidateQueries({ queryKey: ['commandHistory', detailSn] })
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || t('dev.commandFailed')
      setCommandResult({ success: false, message: msg })
      messageApi.error(msg)
    } finally {
      setExecuting(false)
    }
  }

  const handleConfirmExecute = () => {
    setConfirmModalOpen(false)
    if (pendingExecution) {
      doExecuteCommand(pendingExecution.commandName, pendingExecution.params)
      setPendingExecution(null)
    }
  }

  const handleExportTelemetry = async (format: 'csv' | 'excel') => {
    if (!detailSn) return
    try {
      const res = await deviceApi.exportTelemetry(detailSn, format, {
        startTime: telemetryRange[0].toISOString(),
        endTime: telemetryRange[1].toISOString(),
      })
      const blob = res.data as Blob
      const url = window.URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      const ext = format === 'excel' ? 'xlsx' : 'csv'
      link.download = `${detailSn}_telemetry_${Date.now()}.${ext}`
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      window.URL.revokeObjectURL(url)
      messageApi.success(t('dev.exportSuccess', { format: format === 'excel' ? 'Excel' : 'CSV' }))
    } catch (err: any) {
      messageApi.error(t('dev.exportFailed') + (err?.message || ''))
    }
  }

  const exportMenuItems: MenuProps['items'] = [
    {
      key: 'csv',
      label: t('common.exportCSV'),
      icon: <DownloadOutlined />,
      onClick: () => handleExportTelemetry('csv'),
    },
    {
      key: 'excel',
      label: t('common.exportExcel'),
      icon: <DownloadOutlined />,
      onClick: () => handleExportTelemetry('excel'),
    },
  ]

  const handleUnbind = (record: DeviceRecord) => {
    if (canDirectUnbind) {
      Modal.confirm({
        title: t('dev.unbindConfirm'),
        content: t('dev.unbindDevice') + ` ${record.sn}？`,
        okText: t('common.confirm'),
        cancelText: t('common.cancel'),
        onOk: () => unbindMutation.mutate(record.sn),
      })
    } else {
      setUnbindTargetSn(record.sn)
      setUnbindReason('')
      setUnbindModalOpen(true)
    }
  }

  const handleRequestUnbind = async () => {
    if (!unbindReason.trim()) {
      messageApi.warning(t('dev.pleaseEnterUnbindReason'))
      return
    }
    requestUnbindMutation.mutate({ sn: unbindTargetSn, reason: unbindReason })
  }

  const handleImportFile = (file: File) => {
    setImportFile(file)
    setImportResult(null)
    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        const XLSX = (window as any).XLSX
        if (!XLSX) {
          setImportPreview([])
          messageApi.warning(t('dev.excelNotLoaded'))
          return
        }
        const data = new Uint8Array(e.target?.result as ArrayBuffer)
        const workbook = XLSX.read(data, { type: 'array' })
        const sheetName = workbook.SheetNames[0]
        const worksheet = workbook.Sheets[sheetName]
        const rows: any[] = XLSX.utils.sheet_to_json(worksheet, { defval: '' })
        const previewRows: ExcelPreviewRow[] = rows.slice(0, 20).map((row: any) => ({
          SN: row['SN'] ?? row['sn'] ?? '',
          Model: row['Model'] ?? row['model'] ?? '',
          'RatedPower(kW)': row['RatedPower(kW)'] ?? row['RatedPower'] ?? row['ratedPower'] ?? '',
          FirmwareVersion: row['FirmwareVersion'] ?? row['firmwareVersion'] ?? '',
          HardwareVersion: row['HardwareVersion'] ?? row['hardwareVersion'] ?? '',
          StationName: row['StationName'] ?? row['stationName'] ?? '',
        }))
        setImportPreview(previewRows)
      } catch {
        messageApi.error(t('dev.excelParseFailed'))
        setImportPreview([])
      }
    }
    reader.readAsArrayBuffer(file)
    return false
  }

  const handleImportSubmit = async () => {
    if (!importFile) return
    setImporting(true)
    try {
      const res = await deviceApi.importExcel(importFile)
      const result = res.data?.data ?? res.data
      setImportResult(result)
      if (result?.success > 0) {
        messageApi.success(t('dev.importSuccess', { count: result.success }))
      }
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    } catch (err: any) {
      messageApi.error(err?.response?.data?.message || t('dev.importFailed'))
    } finally {
      setImporting(false)
    }
  }

  const importPreviewColumns: ColumnsType<ExcelPreviewRow> = [
    { title: 'SN', dataIndex: 'SN', key: 'SN', width: 150 },
    { title: t('common.model'), dataIndex: 'Model', key: 'Model', width: 120 },
    { title: t('dev.ratedPower_kW'), dataIndex: 'RatedPower(kW)', key: 'RatedPower(kW)', width: 120 },
    { title: t('dev.firmwareVersion'), dataIndex: 'FirmwareVersion', key: 'FirmwareVersion', width: 110 },
    { title: t('dev.hardwareVersion'), dataIndex: 'HardwareVersion', key: 'HardwareVersion', width: 110 },
    { title: t('dev.stationName'), dataIndex: 'StationName', key: 'StationName', width: 120 },
  ]

  const unbindRequestColumns: ColumnsType<UnbindRequestRecord> = [
    {
      title: t('dev.deviceSN'),
      dataIndex: 'device_sn',
      key: 'device_sn',
      width: 150,
    },
    {
      title: t('dev.applicantID'),
      dataIndex: 'requested_by',
      key: 'requested_by',
      width: 100,
    },
    {
      title: t('dev.unbindReason'),
      dataIndex: 'reason',
      key: 'reason',
      width: 200,
      render: (v: string) => v || '-',
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const colorMap: Record<string, string> = { pending: 'orange', approved: 'green', rejected: 'red' }
        const labelMap: Record<string, string> = { pending: t('dev.pending'), approved: t('dev.approved'), rejected: t('dev.rejected') }
        return <Tag color={colorMap[status] || 'default'}>{labelMap[status] || status}</Tag>
      },
    },
    {
      title: t('dev.applyTime'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('common.actions'),
      key: 'actions',
      width: 200,
      render: (_: any, record: UnbindRequestRecord) => {
        if (record.status !== 'pending') return null
        return (
          <Space size="small">
            <Popconfirm
              title={t('dev.unbindApprovalConfirm')}
              onConfirm={() => approveUnbindMutation.mutate({ id: record.id })}
              okText={t('common.confirm')}
              cancelText={t('common.cancel')}
            >
              <Button type="link" size="small" icon={<CheckOutlined />} style={{ color: '#52c41a' }}>
                {t('dev.approve')}
              </Button>
            </Popconfirm>
            <Popconfirm
              title={t('dev.confirmRejectUnbind')}
              onConfirm={() => rejectUnbindMutation.mutate({ id: record.id })}
              okText={t('common.confirm')}
              cancelText={t('common.cancel')}
            >
              <Button type="link" size="small" icon={<CloseOutlined />} danger>
                {t('dev.reject')}
              </Button>
            </Popconfirm>
          </Space>
        )
      },
    },
  ]

  const batchMenuItems: MenuProps['items'] = [
    {
      key: 'unbind',
      label: t('dev.batchUnbind'),
      icon: <LinkOutlined />,
      danger: true,
      onClick: () => {
        Modal.confirm({
          title: t('dev.batchUnbind'),
          content: t('dev.confirmBatchUnbind', { count: selectedRowKeys.length }),
          okText: t('common.confirm'),
          cancelText: t('common.cancel'),
          onOk: () => {
            Promise.all(selectedRowKeys.map((sn) => deviceApi.unbindDevice(String(sn))))
              .then(() => {
                messageApi.success(t('dev.batchUnbindComplete'))
                queryClient.invalidateQueries({ queryKey: ['devices'] })
                setSelectedRowKeys([])
              })
              .catch(() => messageApi.error(t('dev.partialUnbindFailed')))
          },
        })
      },
    },
    {
      key: 'delete',
      label: t('dev.batchDelete'),
      icon: <DeleteOutlined />,
      danger: true,
      onClick: () => {
        Modal.confirm({
          title: t('dev.batchDelete'),
          content: t('dev.confirmBatchDelete', { count: selectedRowKeys.length }),
          okText: t('dev.confirmBatchDeleteBtn'),
          cancelText: t('common.cancel'),
          okButtonProps: { danger: true },
          onOk: () => {
            Promise.all(selectedRowKeys.map((sn) => deviceApi.deleteDevice(String(sn))))
              .then(() => {
                messageApi.success(t('dev.batchDeleteComplete'))
                queryClient.invalidateQueries({ queryKey: ['devices'] })
                setSelectedRowKeys([])
              })
              .catch(() => messageApi.error(t('dev.partialDeleteFailed')))
          },
        })
      },
    },
    {
      key: 'ota',
      label: t('dev.createOTATask'),
      icon: <DownloadOutlined />,
      onClick: () => {
        messageApi.info(t('dev.otaTaskCreated') + ': ' + selectedRowKeys.join(', '))
      },
    },
    {
      key: 'batchControl',
      label: t('dev.batchControl'),
      icon: <ThunderboltOutlined />,
      onClick: () => {
        if (selectedRowKeys.length === 0) {
          messageApi.warning(t('dev.selectDevicesFirst'))
          return
        }
        Modal.confirm({
          title: t('dev.batchControlTitle'),
          content: (
            <div>
              <p>{t('dev.batchControlConfirm', { count: selectedRowKeys.length, cmd: 'restart' })}</p>
              <Select
                defaultValue="restart"
                style={{ width: '100%', marginTop: 8 }}
                options={[
                  { label: 'restart', value: 'restart' },
                  { label: 'query_status', value: 'query_status' },
                ]}
                id="batch-cmd-select"
              />
            </div>
          ),
          okText: t('common.confirm'),
          cancelText: t('common.cancel'),
          onOk: () => {
            const cmdSelect = document.getElementById('batch-cmd-select') as HTMLSelectElement
            const cmd = cmdSelect?.value || 'restart'
            return commandApi.batchControl({
              device_sns: selectedRowKeys.map(String),
              command: cmd,
              params: {},
            }).then(() => {
              messageApi.success(t('dev.batchControlSuccess'))
              setSelectedRowKeys([])
            }).catch(() => {
              messageApi.error(t('dev.batchControlFailed'))
            })
          },
        })
      },
    },
  ]

  const columns: ColumnsType<DeviceRecord> = [
    {
      title: t('dev.deviceSN'),
      dataIndex: 'sn',
      key: 'sn',
      width: 150,
      fixed: 'left',
      render: (sn: string) => (
        <a onClick={() => openDeviceDetail(sn)} style={{ fontWeight: 500 }}>
          {sn}
        </a>
      ),
    },
    {
      title: t('common.model'),
      dataIndex: 'model',
      key: 'model',
      width: 120,
      responsive: ['sm'],
    },
    {
      title: t('dev.ratedPower'),
      dataIndex: 'rated_power',
      key: 'rated_power',
      width: 100,
      responsive: ['md'],
      render: (val: number) => val != null ? `${val} W` : '-',
    },
    {
      title: t('dev.firmwareVersion'),
      dataIndex: 'firmware_arm',
      key: 'firmware_arm',
      width: 110,
      responsive: ['md'],
      render: (v: string) => v || '-',
    },
    {
      title: t('common.owner'),
      key: 'owner',
      width: 130,
      render: (_: any, record: any) => {
        if (!record.owner) return '-'
        return <Text>{record.owner.nickname || record.owner.phone || '-'}</Text>
      },
    },
    {
      title: t('common.installer'),
      key: 'installer',
      width: 120,
      render: (_: any, record: any) => {
        if (!record.installer) return '-'
        return <Text>{record.installer.nickname || record.installer.phone || '-'}</Text>
      },
    },
    {
      title: t('dev.stationName'),
      dataIndex: 'station_name',
      key: 'station_name',
      width: 140,
      responsive: ['sm'],
      render: (v: string) => v || '-',
    },
    {
      title: t('dev.onlineStatus'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: number) => <StatusBadge status={status} />,
    },
    {
      title: t('common.lastOnline'),
      dataIndex: 'last_online_at',
      key: 'last_online_at',
      width: 170,
      render: (v: string, record: DeviceRecord) => formatInTimezone(v, record.timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('common.actions'),
      key: 'actions',
      width: 220,
      fixed: 'right',
      render: (_: any, record: any) => (
        <Space size="small">
          <Button
            type="link"
            size="small"
            icon={<EyeOutlined />}
            onClick={() => openDeviceDetail(record.sn)}
          >
            {t('common.detail')}
          </Button>
          {!isEndUser && (
            <>
              <Button
                type="link"
                size="small"
                icon={<EditOutlined />}
                onClick={() => handleEdit(record)}
              >
                {t('common.edit')}
              </Button>
              {isSuperAdmin && (
                <Button
                  type="link"
                  size="small"
                  onClick={() => {
                    setAssignTargetSn(record.sn)
                    setSelectedInstallerId(null)
                    setAssignModalOpen(true)
                  }}
                >
                  {t('dev.assignInstaller')}
                </Button>
              )}
              {(isSuperAdmin || record.user_id === user?.id) && (
                <Button
                  type="link"
                  size="small"
                  icon={<LinkOutlined />}
                  onClick={() => {
                    setBindStationSn(record.sn)
                    setSelectedStationId(null)
                    setBindStationModalOpen(true)
                  }}
                >
                  {t('dev.bindStation')}
                </Button>
              )}
              {(isSuperAdmin || record.user_id === user?.id) && record.station_id && (
                <Popconfirm
                  title={t('dev.confirmRemoveFromStation')}
                  onConfirm={() => removeFromStationMutation.mutate(record.sn)}
                  okText={t('common.confirm')}
                  cancelText={t('common.cancel')}
                >
                  <Button
                    type="link"
                    size="small"
                    icon={<DisconnectOutlined />}
                  >
                    {t('dev.removeFromStation')}
                  </Button>
                </Popconfirm>
              )}
              <Button
                type="link"
                size="small"
                icon={<LinkOutlined />}
                danger
                onClick={() => handleUnbind(record)}
              >
                {t('dev.unbind')}
              </Button>
              {isSuperAdmin && (
                <Popconfirm
                  title={t('dev.confirmDelete')}
                  onConfirm={() => deleteMutation.mutate(record.sn)}
                  okText={t('common.confirm')}
                  cancelText={t('common.cancel')}
                >
                  <Button type="link" size="small" icon={<DeleteOutlined />} danger>
                    {t('common.delete')}
                  </Button>
                </Popconfirm>
              )}
            </>
          )}
        </Space>
      ),
    },
  ]

  const telemetryOption = useMemo(() => {
    if (!telemetryData || telemetryData.length === 0) return {}
    const times = telemetryData.map((item: any) =>
      formatInTimezone(item.timestamp ?? item.time, timezone, 'MM-DD HH:mm'),
    )
    const powers = telemetryData.map((item: any) => item.ac_power ?? item.power ?? item.acPower ?? 0)
    const voltages = telemetryData.map((item: any) => item.ac_voltage ?? item.voltage ?? item.acVoltage ?? 0)
    const currents = telemetryData.map((item: any) => item.ac_current ?? item.current ?? item.acCurrent ?? 0)

    return {
      tooltip: {
        trigger: 'axis' as const,
      },
      legend: {
        data: [t('dev.power') + '(W)', t('dev.voltage') + '(V)', t('dev.current') + '(A)'],
      },
      grid: {
        left: '3%',
        right: '4%',
        bottom: '3%',
        containLabel: true,
      },
      xAxis: {
        type: 'category' as const,
        data: times,
        boundaryGap: false,
      },
      yAxis: {
        type: 'value' as const,
      },
      series: [
        {
          name: t('dev.power') + '(W)',
          type: 'line',
          data: powers,
          smooth: true,
          lineStyle: { color: '#fa8c16' },
          symbol: 'none',
        },
        {
          name: t('dev.voltage') + '(V)',
          type: 'line',
          data: voltages,
          smooth: true,
          lineStyle: { color: '#1677ff' },
          symbol: 'none',
        },
        {
          name: t('dev.current') + '(A)',
          type: 'line',
          data: currents,
          smooth: true,
          lineStyle: { color: '#52c41a' },
          symbol: 'none',
        },
      ],
    }
  }, [telemetryData])

  const renderRealtimePanel = () => {
    if (realtimeLoading) return <Spin tip={t('common.loading')} />
    if (!realtimeData)
      return <Empty description={t('dev.noRealtimeData')} />

    const { ac, pv, battery, system, online } = realtimeData
    const isOnline = online?.online ?? false

    return (
      <Row gutter={[12, 12]}>
        {ac && (
          <Col span={24}>
            <Card size="small" title={t('dev.acSide')} style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={8}>
                  <Text type="secondary">{t('dev.voltage')}</Text>
                  <br />
                  <Text strong>{ac.voltage?.toFixed(1) ?? '-'} V</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('dev.current')}</Text>
                  <br />
                  <Text strong>{ac.current?.toFixed(2) ?? '-'} A</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('dev.power')}</Text>
                  <br />
                  <Text strong>{ac.power?.toFixed(1) ?? '-'} W</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('dev.frequency')}</Text>
                  <br />
                  <Text strong>{ac.frequency?.toFixed(1) ?? '-'} Hz</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('dev.powerFactor')}</Text>
                  <br />
                  <Text strong>{ac.powerFactor?.toFixed(2) ?? '-'}</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
        {pv && (
          <Col span={24}>
            <Card size="small" title={t('dev.pvSide')} style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={8}>
                  <Text type="secondary">{t('dev.voltage')}</Text>
                  <br />
                  <Text strong>{pv.voltage?.toFixed(1) ?? '-'} V</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('dev.current')}</Text>
                  <br />
                  <Text strong>{pv.current?.toFixed(2) ?? '-'} A</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">{t('dev.power')}</Text>
                  <br />
                  <Text strong>{pv.power?.toFixed(1) ?? '-'} W</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
        {battery && (
          <Col span={24}>
            <Card size="small" title={t('dev.battery')} style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={6}>
                  <Text type="secondary">SOC</Text>
                  <br />
                  <Text strong>{battery.soc?.toFixed(1) ?? '-'} %</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">{t('dev.voltage')}</Text>
                  <br />
                  <Text strong>{battery.voltage?.toFixed(1) ?? '-'} V</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">{t('dev.current')}</Text>
                  <br />
                  <Text strong>{battery.current?.toFixed(2) ?? '-'} A</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">{t('dev.temperature')}</Text>
                  <br />
                  <Text strong>{battery.temp?.toFixed(1) ?? '-'} °C</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
        {system && (
          <Col span={24}>
            <Card size="small" title={t('dev.systemInfo')} style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={6}>
                  <Text type="secondary">{t('dev.workStatus')}</Text>
                  <br />
                  <Text strong>{system.state ?? '-'}</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">{t('dev.faultCode')}</Text>
                  <br />
                  <Text strong style={{ color: system.fault_code ? '#ff4d4f' : undefined }}>
                    {system.fault_code || t('dev.none')}
                  </Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">{t('dev.inverterTemp')}</Text>
                  <br />
                  <Text strong>{system.temp_inv?.toFixed(1) ?? '-'} °C</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">{t('dev.ambientTemp')}</Text>
                  <br />
                  <Text strong>{system.temp_ambient?.toFixed(1) ?? '-'} °C</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
      </Row>
    )
  }

  const renderLifecyclePanel = () => {
    const lifecycles = lifecycleRes?.items ?? []
    if (lifecycles.length === 0) {
      return <Empty description={t('dev.noLifecycleRecords')} />
    }
    return (
      <Timeline
        items={lifecycles.map((event) => ({
          color: LIFECYCLE_EVENT_COLORS[event.event_type] || 'gray',
          children: (
            <div>
              <div style={{ marginBottom: 4 }}>
                <Tag color={LIFECYCLE_EVENT_COLORS[event.event_type] || 'default'}>
                  {LIFECYCLE_EVENT_LABELS[event.event_type] || event.event_type}
                </Tag>
                <Text style={{ fontSize: 12, color: '#999' }}>
                  {formatInTimezone(event.created_at, timezone, 'YYYY-MM-DD HH:mm:ss')}
                </Text>
              </div>
              <Text>{event.description}</Text>
              {event.triggered_by && (
                <div>
                  <Text type="secondary" style={{ fontSize: 12 }}>
                    {t('dev.operatorID')}: {event.triggered_by}
                  </Text>
                </div>
              )}
            </div>
          ),
        }))}
      />
    )
  }

  const deviceDetail = useMemo(() => {
    const base = deviceDetailRaw?.device ?? detailDevice
    if (!base) return undefined
    const rt = deviceDetailRaw?.realtime_data ?? realtimeData
    if (!rt) return base

    // 从嵌套的 info 对象中提取设备信息（支持 {info: {...}} 和 {info: {data: {...}}} 两种格式）
    let rtInfo: any = rt.info
    if (rtInfo && typeof rtInfo === 'object' && rtInfo.data && typeof rtInfo.data === 'object') {
      rtInfo = rtInfo.data
    }

    return {
      ...base,
      model: base.model || rtInfo?.model || rt.model || '',
      rated_power: (base as any).rated_power || rtInfo?.rated_power || rt.rated_power || 0,
      firmware_version: (base as any).firmware_arm || rtInfo?.firmware_arm || (base as any).firmware_version || '',
      hardware_version: (base as any).firmware_esp || rtInfo?.firmware_esp || (base as any).hardware_version || '',
      manufacturer: (base as any).manufacturer || rtInfo?.manufacturer || '',
    }
  }, [deviceDetailRaw, detailDevice, realtimeData])
  const currentStatus = deviceDetail?.status ?? 0

  const drawerTabItems = [
    {
      key: 'info',
      label: t('dev.deviceInfo'),
      children: deviceDetail && (
        <>
          <Card size="small" title={t('dev.deviceInfo')} style={{ marginBottom: 16 }}>
            <Descriptions column={2} size="small">
              <Descriptions.Item label={t('dev.serialNumber')}>{deviceDetail.sn}</Descriptions.Item>
              <Descriptions.Item label={t('common.model')}>{deviceDetail.model ?? '-'}</Descriptions.Item>
              <Descriptions.Item label={t('dev.ratedPower')}>
                {(deviceDetail as any).rated_power != null ? `${(deviceDetail as any).rated_power} W` : '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('dev.firmwareVersion')}>
                {(deviceDetail as any).firmware_arm || (deviceDetail as any).firmware_version || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('dev.hardwareVersion')}>
                {(deviceDetail as any).firmware_esp || (deviceDetail as any).hardware_version || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.status')}>
                <StatusBadge status={currentStatus} />
              </Descriptions.Item>
              <Descriptions.Item label={t('common.owner')}>
                {deviceDetail.owner?.nickname || deviceDetail.owner?.phone || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.installer')}>
                {deviceDetail.installer?.nickname || deviceDetail.installer?.phone || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.lastOnline')}>
                {formatInTimezone((deviceDetail as any).last_online_at, (deviceDetail as any).timezone, 'YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
            </Descriptions>
          </Card>

          {modelFields?.cache && modelFields.cache.showFields.length > 0 && (
            <Card size="small" title={`${detailDevice?.model ?? ''} ${t('dev.statusOverview')}`} style={{ marginBottom: 16 }}>
              <DynamicStatCards
                fields={modelFields.cache.showFields.slice(0, 6)}
                data={realtimeData ?? {}}
              />
            </Card>
          )}

          {modelFields?.cache && modelFields.cache.showFields.length > 0 ? (
            <Card size="small" title={`${detailDevice?.model ?? ''} ${t('dev.realtimeData')}`} style={{ marginBottom: 16 }}>
              <DynamicFieldRenderer
                fields={modelFields.cache.showFields}
                data={realtimeData ?? {}}
                column={2}
                size="small"
              />
            </Card>
          ) : (
            <Card size="small" title={t('dev.realtimeTelemetry')} style={{ marginBottom: 16 }}>
              {renderRealtimePanel()}
            </Card>
          )}

          <Card size="small" title={t('dev.historyTelemetry')} style={{ marginBottom: 16 }}>
            <Space style={{ marginBottom: 12 }}>
              <RangePicker
                value={telemetryRange}
                onChange={(dates) => {
                  if (dates && dates[0] && dates[1]) {
                    setTelemetryRange([dates[0], dates[1]])
                  }
                }}
                showTime
              />
              <Button
                onClick={() => {
                  setTelemetryVersion(v => v + 1)
                }}
              >
                {t('dev.query')}
              </Button>
              <Dropdown menu={{ items: exportMenuItems }}>
                <Button icon={<DownloadOutlined />}>{t('dev.export')}</Button>
              </Dropdown>
            </Space>
            {telemetryLoading ? (
              <Spin tip={t('dev.loadingHistory')} />
            ) : telemetryData && telemetryData.length > 0 ? (
              <ReactECharts key={telemetryVersion} option={telemetryOption} notMerge={true} style={{ height: 280 }} />
            ) : (
              <div style={{ textAlign: 'center', padding: 40 }}>
                <Empty description={`${t('dev.noRealtimeData')} (${detailSn}, ${telemetryRange[0].format('MM-DD HH:mm')} ~ ${telemetryRange[1].format('MM-DD HH:mm')})`} />
              </div>
            )}
          </Card>

          {modelFields?.cache && modelFields.cache.controlFields.length > 0 && (
            <Card size="small" title={t('dev.modelControl')} style={{ marginBottom: 16 }}>
              <List
                size="small"
                dataSource={modelFields.cache.controlFields}
                renderItem={(field) => {
                  const params = (field as any).control_params || {};
                  const label = params.label || field.field_name;
                  const needConfirm = params.confirm === true;
                  const confirmMsg = params.confirm_message || t('dev.confirmExecute', { label });
                  const inputType = params.input_type;

                  const executeCommand = (cmdParams: any = {}) => {
                    return commandApi.execute(detailSn!, { command: field.field_key, params: cmdParams })
                      .then(() => message.success(t('dev.commandSent')))
                      .catch((e: any) => message.error(t('dev.commandFailed') + `: ${e.message}`));
                  };

                  return (
                    <List.Item
                      actions={[
                        <Button
                          key="control"
                          type="primary"
                          size="small"
                          icon={<ThunderboltOutlined />}
                          onClick={() => {
                            if (inputType === 'number') {
                              // 数值输入弹窗
                              let numValue = params.min ?? 0;
                              Modal.confirm({
                                title: label,
                                width: 400,
                                content: (
                                  <div>
                                    <p>{t('dev.rangeHint', { min: params.min ?? 0, max: params.max ?? 10000, unit: params.unit || '' })}</p>
                                    <InputNumber
                                      min={params.min ?? 0}
                                      max={params.max ?? 10000}
                                      step={params.step ?? 1}
                                      defaultValue={params.min ?? 0}
                                      style={{ width: '100%' }}
                                      addonAfter={params.unit || ''}
                                      onChange={(v) => { numValue = v ?? 0; }}
                                    />
                                  </div>
                                ),
                                onOk: () => executeCommand({ value: numValue }),
                              });
                            } else if (needConfirm) {
                              Modal.confirm({
                                title: label,
                                content: confirmMsg,
                                onOk: () => executeCommand(),
                              });
                            } else {
                              executeCommand();
                            }
                          }}
                        >
                          {t('dev.send')}
                        </Button>,
                      ]}
                    >
                      <List.Item.Meta
                        title={label}
                        description={`${t('dev.param')}: ${field.field_key} | ${t('common.model')}: ${field.field_type}`}
                      />
                    </List.Item>
                  );
                }}
              />
            </Card>
          )}

          <Card size="small" title={t('dev.deviceControl')}>
            <div style={{ marginBottom: 12 }}>
              <Text strong>{t('dev.selectTemplate')}</Text>
              <Select
                placeholder={t('dev.selectTemplatePlaceholder')}
                style={{ width: '100%', marginTop: 6 }}
                value={selectedCommand?.name}
                onChange={handleCommandSelect}
                showSearch
                optionFilterProp="label"
                options={(() => {
                  const groups: Record<string, CommandTemplate[]> = {}
                  commandTemplates.forEach((t) => {
                    if (!groups[t.category]) groups[t.category] = []
                    groups[t.category].push(t)
                  })
                  return Object.entries(groups).flatMap(([category, templates]) => [
                    { label: COMMAND_CATEGORY_LABELS[category] || category, value: `group_${category}`, disabled: true },
                    ...templates.map((t) => ({
                      label: `${t.label} - ${t.description}`,
                      value: t.name,
                    })),
                  ])
                })()}
              />
            </div>

            {selectedCommand && selectedCommand.params.length > 0 && (
              <Card size="small" style={{ marginBottom: 12, background: '#fafafa' }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {selectedCommand.params.map((param) => (
                    <div key={param.name}>
                      <div style={{ marginBottom: 4 }}>
                        <Text>{param.label}</Text>
                        {param.required && <Text type="danger"> *</Text>}
                        {param.unit && <Text type="secondary" style={{ marginLeft: 4 }}>({param.unit})</Text>}
                      </div>
                      {param.type === 'number' && (
                        <InputNumber
                          style={{ width: '100%' }}
                          min={param.min}
                          max={param.max}
                          value={commandParams[param.name] as number}
                          onChange={(v) => handleParamChange(param.name, v)}
                          placeholder={`${param.min ?? 0} ~ ${param.max ?? 100}`}
                        />
                      )}
                      {param.type === 'string' && (
                        <Input
                          value={commandParams[param.name] as string}
                          onChange={(e) => handleParamChange(param.name, e.target.value)}
                          placeholder={`${t('common.pleaseInput')}${param.label}`}
                        />
                      )}
                      {param.type === 'boolean' && (
                        <Switch
                          checked={!!commandParams[param.name]}
                          onChange={(v) => handleParamChange(param.name, v)}
                        />
                      )}
                      {param.type === 'select' && param.options && (
                        <Select
                          style={{ width: '100%' }}
                          value={commandParams[param.name]}
                          onChange={(v) => handleParamChange(param.name, v)}
                          options={param.options.map((o) => ({
                            label: o.label,
                            value: o.value,
                          }))}
                        />
                      )}
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {selectedCommand && selectedCommand.requiresConfirm && (
              <Alert
                message={t('dev.note')}
                description={selectedCommand.confirmationMessage || t('dev.needConfirm')}
                type="warning"
                showIcon
                style={{ marginBottom: 12 }}
              />
            )}

            {commandResult && (
              <Alert
                message={commandResult.success ? t('dev.executeSuccess') : t('dev.executeFailed')}
                description={commandResult.message}
                type={commandResult.success ? 'success' : 'error'}
                showIcon
                closable
                style={{ marginBottom: 12 }}
                onClose={() => setCommandResult(null)}
              />
            )}

            <Space style={{ marginBottom: 12 }}>
              <Button
                type="primary"
                icon={<ThunderboltOutlined />}
                onClick={handleExecuteCommand}
                loading={executing}
                disabled={!selectedCommand || currentStatus === 0}
              >
                {selectedCommand
                  ? t('dev.executeCmd', { label: selectedCommand.label })
                  : t('dev.pleaseSelectTemplate')}
              </Button>
              {selectedCommand && (
                <Button onClick={() => { setSelectedCommand(null); setCommandParams({}); setCommandResult(null) }}>
                  {t('dev.resetSelection')}
                </Button>
              )}
              <Button
                icon={<ReloadOutlined />}
                onClick={() => queryClient.invalidateQueries({ queryKey: ['commandTemplates', detailSn] })}
              >
                {t('dev.refreshTemplate')}
              </Button>
            </Space>

            <Divider style={{ margin: '8px 0' }} />

            <div>
              <Text strong style={{ display: 'block', marginBottom: 8 }}>
                {t('dev.commandHistory')}
              </Text>
              {commandHistory.length === 0 ? (
                <Empty description={t('dev.noCommandRecords')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
              ) : (
                <List
                  size="small"
                  dataSource={commandHistory}
                  renderItem={(item: CommandHistoryRecord) => (
                    <List.Item style={{ display: 'block', padding: '8px 0' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <Space size={4}>
                          <Text strong>{item.command_label}</Text>
                          <Tag color={COMMAND_STATUS_COLORS[item.status] || 'default'}>
                            {item.status === 'pending' && t('dev.waiting')}
                            {item.status === 'queued' && (t('dev.queued') || '排队中')}
                            {item.status === 'sent' && t('dev.sent')}
                            {item.status === 'ack_received' && t('dev.deviceConfirmed')}
                            {item.status === 'success' && t('dev.success')}
                            {item.status === 'failed' && t('dev.failed')}
                            {item.status === 'timeout' && t('dev.timeout')}
                          </Tag>
                        </Space>
                        <Text type="secondary" style={{ fontSize: 12 }}>
                          {formatInTimezone(item.created_at, timezone, 'MM-DD HH:mm:ss')}
                        </Text>
                      </div>
                      {item.params && Object.keys(item.params).length > 0 && (
                        <div style={{ marginTop: 2 }}>
                          <Text type="secondary" style={{ fontSize: 12 }}>
                            {t('dev.param')}: {JSON.stringify(item.params)}
                          </Text>
                        </div>
                      )}
                      {item.result_message && (
                        <div style={{ marginTop: 2 }}>
                          <Text type="secondary" style={{ fontSize: 12 }}>
                            {item.result_message}
                          </Text>
                        </div>
                      )}
                    </List.Item>
                  )}
                />
              )}
            </div>
          </Card>
        </>
      ),
    },
    {
      key: 'lifecycle',
      label: t('dev.lifecycle'),
      children: (
        <Card size="small" title={t('dev.lifecycleRecords')}>
          {renderLifecyclePanel()}
        </Card>
      ),
    },
  ]

  return (
    <div>
      {contextHolder}

      <Title level={4} style={{ marginBottom: 24 }}>
        {t('dev.title')}
      </Title>

      {canDirectUnbind && (
        <Card style={{ marginBottom: 16 }}>
          <Tabs
            activeKey={unbindApprovalTab}
            onChange={setUnbindApprovalTab}
            items={[
              {
                key: 'devices',
                label: t('dev.deviceList'),
              },
              {
                key: 'approvals',
                label: (
                  <span>
                    {t('dev.unbindApproval')}
                    {unbindRequestsRes && unbindRequestsRes.total > 0 && (
                      <Tag color="orange" style={{ marginLeft: 8 }}>
                        {unbindRequestsRes.total}
                      </Tag>
                    )}
                  </span>
                ),
              },
            ]}
          />
        </Card>
      )}

      {(!canDirectUnbind || unbindApprovalTab === 'devices') && (
        <>
          <Card style={{ marginBottom: 16 }}>
            <Row gutter={[12, 12]} align="middle">
              <Col xs={24} sm={8} md={6}>
                <Input.Search
                  placeholder={t('dev.searchPlaceholder')}
                  allowClear
                  value={filters.keyword}
                  onChange={(e) => setFilters((f) => ({ ...f, keyword: e.target.value }))}
                  onSearch={() => {
                    setPage(1)
                    queryClient.invalidateQueries({ queryKey: ['devices'] })
                  }}
                  enterButton={<SearchOutlined />}
                />
              </Col>
              <Col xs={12} sm={8} md={4}>
                <Select
                  placeholder={t('dev.onlineStatus')}
                  allowClear
                  style={{ width: '100%' }}
                  value={filters.status}
                  onChange={(v) => setFilters((f) => ({ ...f, status: v }))}
                  options={[
                    { label: t('common.all'), value: '' },
                    { label: t('common.online'), value: '1' },
                    { label: t('common.offline'), value: '0' },
                    { label: t('common.fault'), value: '2' },
                  ]}
                />
              </Col>
              <Col xs={12} sm={8} md={4}>
                <Select
                  placeholder={t('common.model')}
                  allowClear
                  style={{ width: '100%' }}
                  value={filters.model}
                  onChange={(v) => setFilters((f) => ({ ...f, model: v }))}
                  options={modelOptions}
                  showSearch
                  optionFilterProp="label"
                />
              </Col>
              <Col xs={24} sm={12} md={6}>
                <RangePicker
                  style={{ width: '100%' }}
                  placeholder={[t('dev.lastOnlineStart'), t('dev.lastOnlineEnd')]}
                  value={
                    filters.lastOnlineRange
                      ? [dayjs(filters.lastOnlineRange[0]), dayjs(filters.lastOnlineRange[1])]
                      : undefined
                  }
                  onChange={(dates) => {
                    if (dates && dates[0] && dates[1]) {
                      setFilters((f) => ({
                        ...f,
                        lastOnlineRange: [dates[0]!.toISOString(), dates[1]!.toISOString()],
                      }))
                    } else {
                      setFilters((f) => ({ ...f, lastOnlineRange: undefined }))
                    }
                  }}
                />
              </Col>
              <Col xs={24} sm={12} md={4}>
                <Space>
                  <Button type="primary" icon={<SearchOutlined />} onClick={handleSearch}>
                    {t('common.search')}
                  </Button>
                  <Button icon={<ReloadOutlined />} onClick={handleReset}>
                    {t('common.reset')}
                  </Button>
                </Space>
              </Col>
            </Row>

            <Divider style={{ margin: '12px 0' }} />

            <Row justify="space-between" align="middle">
              <Col>
                <Space>
                  {!isEndUser && (
                    <Button type="primary" icon={<PlusOutlined />} onClick={handleAdd}>
                      {t('dev.addDevice')}
                    </Button>
                  )}
                  {(isSuperAdmin || isAgent) && (
                    <Button icon={<UploadOutlined />} onClick={() => {
                      setImportModalOpen(true)
                      setImportFile(null)
                      setImportPreview([])
                      setImportResult(null)
                    }}>
                      {t('dev.importExcel')}
                    </Button>
                  )}
                  {!isEndUser && selectedRowKeys.length > 0 && (
                    <Dropdown menu={{ items: batchMenuItems }} placement="bottomLeft">
                      <Button icon={<SettingOutlined />}>
                        {t('dev.batchOps')} ({selectedRowKeys.length})
                      </Button>
                    </Dropdown>
                  )}
                </Space>
              </Col>
              <Col>
                <Text type="secondary">
                  {isInstaller ? t('dev.onlyMyDevices') : ''}
                </Text>
              </Col>
            </Row>
          </Card>

          <Card>
            <Table
              rowKey="sn"
              columns={columns}
              dataSource={devicesRes?.items ?? []}
              loading={devicesLoading}
              rowSelection={
                !isEndUser
                  ? {
                      selectedRowKeys,
                      onChange: (keys) => setSelectedRowKeys(keys),
                    }
                  : undefined
              }
              pagination={{
                current: page,
                pageSize,
                total: devicesRes?.total ?? 0,
                showSizeChanger: true,
                pageSizeOptions: ['10', '20', '50'],
                showTotal: (total) => t('common.total', { total }),
                onChange: (p, ps) => {
                  setPage(p)
                  setPageSize(ps)
                },
              }}
              onChange={handleTableChange}
              scroll={{ x: 1300 }}
              size="small"
            />
          </Card>
        </>
      )}

      {canDirectUnbind && unbindApprovalTab === 'approvals' && (
        <Card>
          <Table
            rowKey="id"
            columns={unbindRequestColumns}
            dataSource={unbindRequestsRes?.items ?? []}
            loading={false}
            pagination={{
              current: unbindReqPage,
              pageSize: unbindReqPageSize,
              total: unbindRequestsRes?.total ?? 0,
              showSizeChanger: true,
              showTotal: (total) => t('common.total', { total }),
              onChange: (p, ps) => {
                setUnbindReqPage(p)
                setUnbindReqPageSize(ps)
              },
            }}
            scroll={{ x: 800 }}
            size="small"
          />
        </Card>
      )}

      <Modal
        title={t('dev.addDeviceTitle')}
        open={addModalOpen}
        onCancel={() => setAddModalOpen(false)}
        onOk={handleAddSubmit}
        confirmLoading={createMutation.isPending}
        okText={t('dev.addDevice')}
        cancelText={t('common.cancel')}
        destroyOnClose
      >
        <Form form={addForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item
            name="sn"
            label={t('dev.deviceSN')}
            rules={[{ required: true, message: t('dev.deviceSN') }]}
          >
            <Input placeholder={t('dev.deviceSN')} />
          </Form.Item>
          <Form.Item name="model" label={t('common.model')}>
            <Input placeholder={t('common.model')} />
          </Form.Item>
          <Form.Item name="ratedPower" label={t('dev.ratedPower_W')}>
            <InputNumber style={{ width: '100%' }} placeholder={t('dev.ratedPower_W')} />
          </Form.Item>
          <Form.Item name="firmwareVersion" label={t('dev.firmwareVersion')}>
            <Input placeholder={t('dev.firmwareVersion')} />
          </Form.Item>
          <Form.Item name="hardwareVersion" label={t('dev.hardwareVersion')}>
            <Input placeholder={t('dev.hardwareVersion')} />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title={t('dev.confirmExecute')}
        open={confirmModalOpen}
        onOk={handleConfirmExecute}
        onCancel={() => { setConfirmModalOpen(false); setPendingExecution(null) }}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
        okButtonProps={{ danger: true }}
      >
        <div style={{ marginBottom: 12 }}>
          <Alert
            message={selectedCommand?.label || pendingExecution?.commandName}
            description={
              selectedCommand?.confirmationMessage ||
              t('dev.needConfirm')
            }
            type="warning"
            showIcon
          />
        </div>
        {pendingExecution?.params && Object.keys(pendingExecution.params).length > 0 && (
          <Descriptions size="small" column={1} bordered>
            {Object.entries(pendingExecution.params).map(([key, value]) => (
              <Descriptions.Item key={key} label={key}>
                {String(value)}
              </Descriptions.Item>
            ))}
          </Descriptions>
        )}
      </Modal>

      <Modal
        title={t('dev.editDeviceTitle')}
        open={editModalOpen}
        onCancel={() => setEditModalOpen(false)}
        onOk={handleEditSubmit}
        confirmLoading={updateMutation.isPending}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
        destroyOnClose
      >
        <Form form={editForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item name="sn" label={t('dev.deviceSN')}>
            <Input disabled />
          </Form.Item>
          <Form.Item name="model" label={t('common.model')}>
            <Input placeholder={t('common.model')} />
          </Form.Item>
          <Form.Item name="ratedPower" label={t('dev.ratedPower_W')}>
            <InputNumber style={{ width: '100%' }} placeholder={t('dev.ratedPower_W')} />
          </Form.Item>
          <Form.Item name="firmwareVersion" label={t('dev.firmwareVersion')}>
            <Input placeholder={t('dev.firmwareVersion')} />
          </Form.Item>
          <Form.Item name="hardwareVersion" label={t('dev.hardwareVersion')}>
            <Input placeholder={t('dev.hardwareVersion')} />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title={t('dev.importDeviceTitle')}
        open={importModalOpen}
        onCancel={() => setImportModalOpen(false)}
        onOk={handleImportSubmit}
        confirmLoading={importing}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
        width={800}
        okButtonProps={{ disabled: !importFile }}
        destroyOnClose
      >
        <div style={{ marginBottom: 16 }}>
          <Text type="secondary">
            {t('dev.importHintFull')}
          </Text>
          <br />
          <a
            onClick={() => {
              const XLSX = (window as any).XLSX
              if (!XLSX) {
                messageApi.warning(t('dev.excelNotLoaded2'))
                return
              }
              const wb = XLSX.utils.book_new()
              const ws = XLSX.utils.json_to_sheet([
                {
                  SN: 'INV-20240001',
                  Model: 'INV-5000',
                  'RatedPower(kW)': 5,
                  FirmwareVersion: 'v1.0.0',
                  HardwareVersion: 'H1.0',
                  StationName: '',
                },
              ])
              XLSX.utils.book_append_sheet(wb, ws, 'Sheet1')
              XLSX.writeFile(wb, 'device_import_template.xlsx')
            }}
          >
            {t('common.downloadTemplate')}
          </a>
        </div>

        <Dragger
          accept=".xlsx,.xls"
          maxCount={1}
          beforeUpload={handleImportFile}
          onRemove={() => {
            setImportFile(null)
            setImportPreview([])
            setImportResult(null)
          }}
          fileList={importFile ? [{ uid: '-1', name: importFile.name, status: 'done' } as any] : []}
        >
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">{t('dev.uploadExcelHere')}</p>
          <p className="ant-upload-hint">{t('dev.excelOnly')}</p>
        </Dragger>

        {importPreview.length > 0 && (
          <div style={{ marginTop: 16 }}>
            <Text strong>{t('dev.dataPreview')}</Text>
            <Table
              columns={importPreviewColumns}
              dataSource={importPreview.map((row, idx) => ({ ...row, key: idx }))}
              size="small"
              scroll={{ x: 700 }}
              pagination={false}
              style={{ marginTop: 8 }}
            />
          </div>
        )}

        {importResult && (
          <div style={{ marginTop: 16 }}>
            <Divider />
            <Row gutter={16}>
              <Col span={12}>
                <Card size="small">
                  <Text strong style={{ color: '#52c41a', fontSize: 18 }}>
                    {t('dev.importSuccessCount')}: {importResult.success}
                  </Text>
                </Card>
              </Col>
              <Col span={12}>
                <Card size="small">
                  <Text strong style={{ color: '#ff4d4f', fontSize: 18 }}>
                    {t('dev.importFailedCount')}: {importResult.failed}
                  </Text>
                </Card>
              </Col>
            </Row>
            {importResult.errors.length > 0 && (
              <div style={{ marginTop: 8, maxHeight: 200, overflow: 'auto' }}>
                <Table
                  columns={[
                    { title: t('dev.rowNum'), dataIndex: 'row', key: 'row', width: 80 },
                    { title: t('dev.errorInfo'), dataIndex: 'message', key: 'message' },
                  ]}
                  dataSource={importResult.errors.map((e, idx) => ({ ...e, key: idx }))}
                  size="small"
                  pagination={false}
                />
              </div>
            )}
          </div>
        )}
      </Modal>

      <Modal
        title={t('dev.unbindDeviceTitle')}
        open={unbindModalOpen}
        onCancel={() => {
          setUnbindModalOpen(false)
          setUnbindReason('')
          setUnbindTargetSn('')
        }}
        onOk={handleRequestUnbind}
        confirmLoading={requestUnbindMutation.isPending}
        okText={t('common.submit')}
        cancelText={t('common.cancel')}
        destroyOnClose
      >
        <div style={{ marginBottom: 12 }}>
          <Text>{t('dev.deviceSN')}: <Text strong>{unbindTargetSn}</Text></Text>
        </div>
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary">{t('dev.unbindHint')}</Text>
        </div>
        <Form layout="vertical">
          <Form.Item label={t('dev.unbindReasonLabel')} required>
            <AntInput.TextArea
              rows={4}
              placeholder={t('dev.unbindReasonPlaceholder')}
              value={unbindReason}
              onChange={(e) => setUnbindReason(e.target.value)}
            />
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title={
          <Space>
            <span>{t('dev.deviceDetail')}</span>
            {deviceDetail && <StatusBadge status={deviceDetail.status} />}
          </Space>
        }
        width={screens.md ? 720 : '100%'}
        open={detailDrawerOpen}
        onClose={() => {
          setDetailDrawerOpen(false)
          setDetailSn('')
          setDetailDevice(null)
          setDrawerTab('info')
        }}
        extra={
          <Space>
            {currentStatus !== 0 && (
              <>
                <Popconfirm
                  title={t('dev.confirmRestart')}
                  onConfirm={() => {
                    commandApi.execute(detailSn, { command: 'restart', params: {} })
                      .then(() => {
                        messageApi.success(t('dev.restartSuccess'))
                        queryClient.invalidateQueries({ queryKey: ['commandHistory', detailSn] })
                      })
                      .catch(() => messageApi.error(t('dev.restartFailed')))
                  }}
                  okText={t('dev.confirmRestartBtn')}
                  cancelText={t('common.cancel')}
                >
                  <Button icon={<ReloadOutlined />}>{t('dev.restartDevice')}</Button>
                </Popconfirm>
                <Button
                  icon={<ThunderboltOutlined />}
                  onClick={() => {
                    commandApi.execute(detailSn, { command: 'query_status', params: {} })
                      .then(() => {
                        messageApi.success(t('dev.querySuccess'))
                        queryClient.invalidateQueries({ queryKey: ['commandHistory', detailSn] })
                      })
                      .catch(() => messageApi.error(t('dev.queryFailed')))
                  }}
                >
                  {t('dev.queryStatus')}
                </Button>
              </>
            )}
            {currentStatus === 0 && (
              <Tag color="red">{t('dev.deviceOffline')}</Tag>
            )}
          </Space>
        }
      >
        {deviceDetail ? (
          <Tabs
            activeKey={drawerTab}
            onChange={setDrawerTab}
            items={drawerTabItems}
          />
        ) : (
          <Spin tip={t('common.loading')} />
        )}
      </Drawer>

      {/* 绑定电站Modal */}
      <Modal
        title={t('dev.bindStation')}
        open={bindStationModalOpen}
        onCancel={() => { setBindStationModalOpen(false); setSelectedStationId(null) }}
        onOk={() => {
          if (selectedStationId && bindStationSn) {
            bindStationMutation.mutate({ sn: bindStationSn, stationId: selectedStationId })
          }
        }}
        confirmLoading={bindStationMutation.isPending}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
      >
        <div style={{ padding: '16px 0' }}>
          <div style={{ marginBottom: 8 }}>{t('dev.selectStation')}</div>
          <Select
            style={{ width: '100%' }}
            placeholder={t('dev.selectStation')}
            value={selectedStationId}
            onChange={(v) => setSelectedStationId(v)}
            showSearch
            filterOption={(input, option) =>
              (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
            }
            options={stationsList.map((s: any) => ({ value: s.id, label: s.name }))}
          />
        </div>
      </Modal>

      {/* 分配安装商Modal */}
      <Modal
        title={t('dev.assignInstallerTitle')}
        open={assignModalOpen}
        onCancel={() => {
          setAssignModalOpen(false)
          setAssignTargetSn('')
          setSelectedInstallerId(null)
        }}
        onOk={() => {
          if (selectedInstallerId && assignTargetSn) {
            assignInstallerMutation.mutate({ sn: assignTargetSn, installerId: selectedInstallerId })
          } else {
            messageApi.warning(t('dev.pleaseSelectInstaller'))
          }
        }}
        confirmLoading={assignInstallerMutation.isPending}
        destroyOnClose
      >
        <div style={{ marginBottom: 16 }}>
          <Text>{t('dev.deviceSN')}：</Text>
          <Text strong>{assignTargetSn}</Text>
        </div>
        <div>
          <Text>{t('dev.selectInstaller')}：</Text>
          <Select
            style={{ width: '100%', marginTop: 8 }}
            placeholder={t('dev.selectInstallerPlaceholder')}
            value={selectedInstallerId}
            onChange={(value) => setSelectedInstallerId(value)}
            options={
              (installersRes || []).map((installer) => ({
                label: `${installer.nickname || installer.phone} (ID: ${installer.id})`,
                value: installer.id,
              }))
            }
            showSearch
            filterOption={(input, option) =>
              (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
            }
          />
        </div>
      </Modal>
    </div>
  )
}

export default DevicesPage
