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
} from '@ant-design/icons'
import dayjs from 'dayjs'
import ReactECharts from 'echarts-for-react'
import { deviceApi } from '@/services/deviceApi'
import { commandApi } from '@/services/commandApi'
import { modelApi } from '@/services/modelApi'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import StatusBadge from '@/components/StatusBadge'
import { useModelFields, DynamicFieldRenderer, DynamicStatCards } from '@/components/dyna'

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
  owner?: { phone: string; nickname: string }
  installer?: { nickname: string; phone: string }
}

interface RealtimeData {
  ac?: { voltage: number; current: number; power: number; frequency: number; powerFactor: number }
  pv?: { voltage: number; current: number; power: number }
  battery?: { soc: number; voltage: number; current: number; temp: number }
  system?: { state: string; fault_code: number; temp_inv: number; temp_ambient: number }
  online?: { online: boolean; rssi: number; ip: string }
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

const COMMAND_CATEGORY_LABELS: Record<string, string> = {
  power: '功率控制',
  battery: '电池管理',
  grid: '电网保护',
  system: '系统控制',
  ota: '远程升级',
}

const COMMAND_STATUS_COLORS: Record<string, string> = {
  pending: 'default',
  sent: 'processing',
  ack_received: 'blue',
  success: 'green',
  failed: 'red',
  timeout: 'orange',
}

const LIFECYCLE_EVENT_LABELS: Record<string, string> = {
  registered: '注册',
  bound: '绑定',
  unbound: '解绑',
  activated: '激活',
  decommissioned: '退役',
  maintenance: '维护',
  firmware_upgrade: '固件升级',
  hardware_replace: '硬件更换',
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
  const queryClient = useQueryClient()
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

  const { data: deviceDetailRes } = useQuery({
    queryKey: ['deviceDetail', detailSn],
    queryFn: () =>
      deviceApi.getDeviceBySn(detailSn).then((res) => {
        const d = res.data
        return (d?.data ?? d ?? {}) as DeviceRecord
      }),
    enabled: !!detailSn && detailDrawerOpen,
  })

  const { data: realtimeData, isLoading: realtimeLoading } = useQuery({
    queryKey: ['deviceRealtime', detailSn],
    queryFn: () =>
      deviceApi.getRealtime(detailSn).then((res) => {
        const d = res.data
        return (d?.data ?? d ?? {}) as RealtimeData
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
      console.log('[Telemetry] Fetching:', sn, s, e);
      const res = await deviceApi.getTelemetry(sn, { startTime: s, endTime: e });
      console.log('[Telemetry] Raw:', res.status, res.data);
      const payload = res.data;
      const items = Array.isArray(payload?.data) ? payload.data : (Array.isArray(payload) ? payload : []);
      console.log('[Telemetry] Items:', items.length, items);
      setTelemetryData(items);
    } catch (err: any) {
      console.error('[Telemetry] Error:', err?.response?.status, err?.response?.data || err?.message);
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
        return (res.data?.data ?? res.data ?? []) as CommandTemplate[]
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

  const commandTemplates = commandTemplatesRes ?? []
  const commandHistory = commandHistoryRes?.items ?? []

  const createMutation = useMutation({
    mutationFn: (data: any) => deviceApi.createDevice(data).then((r) => r.data),
    onSuccess: () => {
      messageApi.success('设备添加成功')
      setAddModalOpen(false)
      addForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => {
      messageApi.error('添加失败，请重试')
    },
  })

  const updateMutation = useMutation({
    mutationFn: (data: any) => deviceApi.updateDevice(data.sn, data).then((r) => r.data),
    onSuccess: () => {
      messageApi.success('设备更新成功')
      setEditModalOpen(false)
      editForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => {
      messageApi.error('更新失败，请重试')
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (sn: string) => deviceApi.deleteDevice(sn),
    onSuccess: () => {
      messageApi.success('设备已删除')
      queryClient.invalidateQueries({ queryKey: ['devices'] })
      setSelectedRowKeys([])
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || err?.message || '删除失败'),
  })

  const unbindMutation = useMutation({
    mutationFn: (sn: string) => deviceApi.unbindDevice(sn),
    onSuccess: () => {
      messageApi.success('设备已解绑')
      queryClient.invalidateQueries({ queryKey: ['devices'] })
      setSelectedRowKeys([])
    },
    onError: () => messageApi.error('解绑失败'),
  })

  const requestUnbindMutation = useMutation({
    mutationFn: ({ sn, reason }: { sn: string; reason: string }) =>
      deviceApi.requestUnbind(sn, reason),
    onSuccess: () => {
      messageApi.success('解绑申请已提交，等待审批')
      setUnbindModalOpen(false)
      setUnbindReason('')
      setUnbindTargetSn('')
    },
    onError: () => messageApi.error('提交失败'),
  })

  const approveUnbindMutation = useMutation({
    mutationFn: ({ id, comment }: { id: number; comment?: string }) =>
      deviceApi.approveUnbind(id, comment),
    onSuccess: () => {
      messageApi.success('已批准解绑')
      queryClient.invalidateQueries({ queryKey: ['unbindRequests'] })
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: () => messageApi.error('操作失败'),
  })

  const rejectUnbindMutation = useMutation({
    mutationFn: ({ id, comment }: { id: number; comment?: string }) =>
      deviceApi.rejectUnbind(id, comment),
    onSuccess: () => {
      messageApi.success('已拒绝解绑申请')
      queryClient.invalidateQueries({ queryKey: ['unbindRequests'] })
    },
    onError: () => messageApi.error('操作失败'),
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
      firmwareVersion: record.firmware_version,
      hardwareVersion: record.hardware_version,
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
    if (template) {
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
      setCommandResult({ success: result?.success ?? true, message: result?.message ?? '指令执行成功' })
      if (result?.success !== false) {
        messageApi.success('指令执行成功')
      } else {
        messageApi.warning(result?.message || '指令执行失败')
      }
      queryClient.invalidateQueries({ queryKey: ['commandHistory', detailSn] })
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || '指令执行失败'
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
      messageApi.success(`${format === 'excel' ? 'Excel' : 'CSV'} 导出成功`)
    } catch (err: any) {
      messageApi.error('导出失败: ' + (err?.message || '未知错误'))
    }
  }

  const exportMenuItems: MenuProps['items'] = [
    {
      key: 'csv',
      label: '导出 CSV',
      icon: <DownloadOutlined />,
      onClick: () => handleExportTelemetry('csv'),
    },
    {
      key: 'excel',
      label: '导出 Excel',
      icon: <DownloadOutlined />,
      onClick: () => handleExportTelemetry('excel'),
    },
  ]

  const handleUnbind = (record: DeviceRecord) => {
    if (canDirectUnbind) {
      Modal.confirm({
        title: '确认解绑',
        content: `确认解绑设备 ${record.sn}？`,
        okText: '确认',
        cancelText: '取消',
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
      messageApi.warning('请输入解绑原因')
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
          messageApi.warning('Excel解析库未加载，请刷新重试')
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
        messageApi.error('Excel文件解析失败')
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
        messageApi.success(`成功导入 ${result.success} 台设备`)
      }
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    } catch (err: any) {
      messageApi.error(err?.response?.data?.message || '导入失败')
    } finally {
      setImporting(false)
    }
  }

  const importPreviewColumns: ColumnsType<ExcelPreviewRow> = [
    { title: 'SN', dataIndex: 'SN', key: 'SN', width: 150 },
    { title: '型号', dataIndex: 'Model', key: 'Model', width: 120 },
    { title: '额定功率(kW)', dataIndex: 'RatedPower(kW)', key: 'RatedPower(kW)', width: 120 },
    { title: '固件版本', dataIndex: 'FirmwareVersion', key: 'FirmwareVersion', width: 110 },
    { title: '硬件版本', dataIndex: 'HardwareVersion', key: 'HardwareVersion', width: 110 },
    { title: '电站名称', dataIndex: 'StationName', key: 'StationName', width: 120 },
  ]

  const unbindRequestColumns: ColumnsType<UnbindRequestRecord> = [
    {
      title: '设备SN',
      dataIndex: 'device_sn',
      key: 'device_sn',
      width: 150,
    },
    {
      title: '申请人ID',
      dataIndex: 'requested_by',
      key: 'requested_by',
      width: 100,
    },
    {
      title: '解绑原因',
      dataIndex: 'reason',
      key: 'reason',
      width: 200,
      render: (v: string) => v || '-',
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const colorMap: Record<string, string> = { pending: 'orange', approved: 'green', rejected: 'red' }
        const labelMap: Record<string, string> = { pending: '待审批', approved: '已批准', rejected: '已拒绝' }
        return <Tag color={colorMap[status] || 'default'}>{labelMap[status] || status}</Tag>
      },
    },
    {
      title: '申请时间',
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (v: string) => v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: '操作',
      key: 'actions',
      width: 200,
      render: (_: any, record: UnbindRequestRecord) => {
        if (record.status !== 'pending') return null
        return (
          <Space size="small">
            <Popconfirm
              title="确认批准此解绑申请？"
              onConfirm={() => approveUnbindMutation.mutate({ id: record.id })}
              okText="确认"
              cancelText="取消"
            >
              <Button type="link" size="small" icon={<CheckOutlined />} style={{ color: '#52c41a' }}>
                批准
              </Button>
            </Popconfirm>
            <Popconfirm
              title="确认拒绝此解绑申请？"
              onConfirm={() => rejectUnbindMutation.mutate({ id: record.id })}
              okText="确认"
              cancelText="取消"
            >
              <Button type="link" size="small" icon={<CloseOutlined />} danger>
                拒绝
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
      label: '批量解绑',
      icon: <LinkOutlined />,
      danger: true,
      onClick: () => {
        Modal.confirm({
          title: '批量解绑',
          content: `确认解绑选中的 ${selectedRowKeys.length} 台设备？`,
          okText: '确认',
          cancelText: '取消',
          onOk: () => {
            Promise.all(selectedRowKeys.map((sn) => deviceApi.unbindDevice(String(sn))))
              .then(() => {
                messageApi.success('批量解绑完成')
                queryClient.invalidateQueries({ queryKey: ['devices'] })
                setSelectedRowKeys([])
              })
              .catch(() => messageApi.error('部分解绑失败'))
          },
        })
      },
    },
    {
      key: 'delete',
      label: '批量删除',
      icon: <DeleteOutlined />,
      danger: true,
      onClick: () => {
        Modal.confirm({
          title: '批量删除',
          content: `确认删除选中的 ${selectedRowKeys.length} 台设备？此操作不可逆！`,
          okText: '确认删除',
          cancelText: '取消',
          okButtonProps: { danger: true },
          onOk: () => {
            Promise.all(selectedRowKeys.map((sn) => deviceApi.deleteDevice(String(sn))))
              .then(() => {
                messageApi.success('批量删除完成')
                queryClient.invalidateQueries({ queryKey: ['devices'] })
                setSelectedRowKeys([])
              })
              .catch(() => messageApi.error('部分删除失败'))
          },
        })
      },
    },
    {
      key: 'ota',
      label: '创建OTA任务',
      icon: <DownloadOutlined />,
      onClick: () => {
        messageApi.info('OTA任务创建功能 - 选中设备: ' + selectedRowKeys.join(', '))
      },
    },
  ]

  const columns: ColumnsType<DeviceRecord> = [
    {
      title: '设备序列号',
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
      title: '型号',
      dataIndex: 'model',
      key: 'model',
      width: 120,
      responsive: ['sm'],
    },
    {
      title: '额定功率',
      dataIndex: 'rated_power',
      key: 'rated_power',
      width: 100,
      responsive: ['md'],
      render: (val: number) => val != null ? `${val} W` : '-',
    },
    {
      title: '固件版本',
      dataIndex: 'firmware_version',
      key: 'firmware_version',
      width: 110,
      responsive: ['md'],
      render: (v: string) => v || '-',
    },
    {
      title: '所有者',
      key: 'owner',
      width: 130,
      render: (_: any, record: any) => {
        if (!record.owner) return '-'
        return <Text>{record.owner.nickname || record.owner.phone || '-'}</Text>
      },
    },
    {
      title: '安装商',
      key: 'installer',
      width: 120,
      render: (_: any, record: any) => {
        if (!record.installer) return '-'
        return <Text>{record.installer.nickname || record.installer.phone || '-'}</Text>
      },
    },
    {
      title: '在线状态',
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: number) => <StatusBadge status={status} />,
    },
    {
      title: '最后通信时间',
      dataIndex: 'last_online_at',
      key: 'last_online_at',
      width: 170,
      render: (v: string) => (v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-'),
    },
    {
      title: '操作',
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
            详情
          </Button>
          {!isEndUser && (
            <>
              <Button
                type="link"
                size="small"
                icon={<EditOutlined />}
                onClick={() => handleEdit(record)}
              >
                编辑
              </Button>
              <Button
                type="link"
                size="small"
                icon={<LinkOutlined />}
                danger
                onClick={() => handleUnbind(record)}
              >
                解绑
              </Button>
              {isSuperAdmin && (
                <Popconfirm
                  title="确认删除？"
                  onConfirm={() => deleteMutation.mutate(record.sn)}
                  okText="确认"
                  cancelText="取消"
                >
                  <Button type="link" size="small" icon={<DeleteOutlined />} danger>
                    删除
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
      dayjs(item.timestamp ?? item.time).format('MM-DD HH:mm'),
    )
    const powers = telemetryData.map((item: any) => item.power ?? item.acPower ?? 0)
    const voltages = telemetryData.map((item: any) => item.voltage ?? item.acVoltage ?? 0)
    const currents = telemetryData.map((item: any) => item.current ?? item.acCurrent ?? 0)

    return {
      tooltip: {
        trigger: 'axis' as const,
      },
      legend: {
        data: ['功率(W)', '电压(V)', '电流(A)'],
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
          name: '功率(W)',
          type: 'line',
          data: powers,
          smooth: true,
          lineStyle: { color: '#fa8c16' },
          symbol: 'none',
        },
        {
          name: '电压(V)',
          type: 'line',
          data: voltages,
          smooth: true,
          lineStyle: { color: '#1677ff' },
          symbol: 'none',
        },
        {
          name: '电流(A)',
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
    if (realtimeLoading) return <Spin tip="加载中..." />
    if (!realtimeData)
      return <Empty description="暂无实时数据" />

    const { ac, pv, battery, system, online } = realtimeData
    const isOnline = online?.online ?? false

    return (
      <Row gutter={[12, 12]}>
        {ac && (
          <Col span={24}>
            <Card size="small" title="交流侧 (AC)" style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={8}>
                  <Text type="secondary">电压</Text>
                  <br />
                  <Text strong>{ac.voltage?.toFixed(1) ?? '-'} V</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">电流</Text>
                  <br />
                  <Text strong>{ac.current?.toFixed(2) ?? '-'} A</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">功率</Text>
                  <br />
                  <Text strong>{ac.power?.toFixed(1) ?? '-'} W</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">频率</Text>
                  <br />
                  <Text strong>{ac.frequency?.toFixed(1) ?? '-'} Hz</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">功率因数</Text>
                  <br />
                  <Text strong>{ac.powerFactor?.toFixed(2) ?? '-'}</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
        {pv && (
          <Col span={24}>
            <Card size="small" title="光伏 (PV)" style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={8}>
                  <Text type="secondary">电压</Text>
                  <br />
                  <Text strong>{pv.voltage?.toFixed(1) ?? '-'} V</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">电流</Text>
                  <br />
                  <Text strong>{pv.current?.toFixed(2) ?? '-'} A</Text>
                </Col>
                <Col span={8}>
                  <Text type="secondary">功率</Text>
                  <br />
                  <Text strong>{pv.power?.toFixed(1) ?? '-'} W</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
        {battery && (
          <Col span={24}>
            <Card size="small" title="电池" style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={6}>
                  <Text type="secondary">SOC</Text>
                  <br />
                  <Text strong>{battery.soc?.toFixed(1) ?? '-'} %</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">电压</Text>
                  <br />
                  <Text strong>{battery.voltage?.toFixed(1) ?? '-'} V</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">电流</Text>
                  <br />
                  <Text strong>{battery.current?.toFixed(2) ?? '-'} A</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">温度</Text>
                  <br />
                  <Text strong>{battery.temp?.toFixed(1) ?? '-'} °C</Text>
                </Col>
              </Row>
            </Card>
          </Col>
        )}
        {system && (
          <Col span={24}>
            <Card size="small" title="系统信息" style={{ background: '#fafafa' }}>
              <Row gutter={[12, 8]}>
                <Col span={6}>
                  <Text type="secondary">工作状态</Text>
                  <br />
                  <Text strong>{system.state ?? '-'}</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">故障码</Text>
                  <br />
                  <Text strong style={{ color: system.fault_code ? '#ff4d4f' : undefined }}>
                    {system.fault_code || '无'}
                  </Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">逆变温度</Text>
                  <br />
                  <Text strong>{system.temp_inv?.toFixed(1) ?? '-'} °C</Text>
                </Col>
                <Col span={6}>
                  <Text type="secondary">环境温度</Text>
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
      return <Empty description="暂无生命周期记录" />
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
                  {dayjs(event.created_at).format('YYYY-MM-DD HH:mm:ss')}
                </Text>
              </div>
              <Text>{event.description}</Text>
              {event.triggered_by && (
                <div>
                  <Text type="secondary" style={{ fontSize: 12 }}>
                    操作人ID: {event.triggered_by}
                  </Text>
                </div>
              )}
            </div>
          ),
        }))}
      />
    )
  }

  const deviceDetail = deviceDetailRes ?? detailDevice
  const currentStatus = deviceDetail?.status ?? 0

  const drawerTabItems = [
    {
      key: 'info',
      label: '基本信息',
      children: deviceDetail && (
        <>
          <Card size="small" title="设备信息" style={{ marginBottom: 16 }}>
            <Descriptions column={2} size="small">
              <Descriptions.Item label="序列号">{deviceDetail.sn}</Descriptions.Item>
              <Descriptions.Item label="型号">{deviceDetail.model ?? '-'}</Descriptions.Item>
              <Descriptions.Item label="额定功率">
                {(deviceDetail as any).rated_power != null ? `${(deviceDetail as any).rated_power} W` : '-'}
              </Descriptions.Item>
              <Descriptions.Item label="固件版本">
                {(deviceDetail as any).firmware_version || '-'}
              </Descriptions.Item>
              <Descriptions.Item label="硬件版本">
                {(deviceDetail as any).hardware_version || '-'}
              </Descriptions.Item>
              <Descriptions.Item label="状态">
                <StatusBadge status={currentStatus} />
              </Descriptions.Item>
              <Descriptions.Item label="所有者">
                {deviceDetail.owner?.nickname || deviceDetail.owner?.phone || '-'}
              </Descriptions.Item>
              <Descriptions.Item label="安装商">
                {deviceDetail.installer?.nickname || deviceDetail.installer?.phone || '-'}
              </Descriptions.Item>
              <Descriptions.Item label="最后通信">
                {(deviceDetail as any).last_online_at
                  ? dayjs((deviceDetail as any).last_online_at).format('YYYY-MM-DD HH:mm:ss')
                  : '-'}
              </Descriptions.Item>
            </Descriptions>
          </Card>

          {modelFields?.cache && modelFields.cache.showFields.length > 0 && (
            <Card size="small" title={`${detailDevice?.model ?? ''} 状态概览`} style={{ marginBottom: 16 }}>
              <DynamicStatCards
                fields={modelFields.cache.showFields.slice(0, 6)}
                data={realtimeData ?? {}}
              />
            </Card>
          )}

          <Card size="small" title="实时遥测数据" style={{ marginBottom: 16 }}>
            {renderRealtimePanel()}
          </Card>

          {modelFields?.cache && modelFields.cache.showFields.length > 0 && (
            <Card size="small" title={`${detailDevice?.model ?? ''} 动态字段`} style={{ marginBottom: 16 }}>
              <DynamicFieldRenderer
                fields={modelFields.cache.showFields}
                data={realtimeData ?? {}}
                column={2}
                size="small"
              />
            </Card>
          )}

          <Card size="small" title="历史遥测数据" style={{ marginBottom: 16 }}>
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
                查询
              </Button>
              <Dropdown menu={{ items: exportMenuItems }}>
                <Button icon={<DownloadOutlined />}>导出</Button>
              </Dropdown>
            </Space>
            {telemetryLoading ? (
              <Spin tip="加载历史数据中..." />
            ) : telemetryData && telemetryData.length > 0 ? (
              <ReactECharts key={telemetryVersion} option={telemetryOption} notMerge={true} style={{ height: 280 }} />
            ) : (
              <div style={{ textAlign: 'center', padding: 40 }}>
                <Empty description={`暂无遥测数据 (${detailSn}, ${telemetryRange[0].format('MM-DD HH:mm')} ~ ${telemetryRange[1].format('MM-DD HH:mm')})`} />
              </div>
            )}
          </Card>

          {modelFields?.cache && modelFields.cache.controlFields.length > 0 && (
            <Card size="small" title="型号控制指令" style={{ marginBottom: 16 }}>
              <Alert
                type="info"
                message="以下为当前型号支持的控制字段，由型号配置自动生成"
                style={{ marginBottom: 12 }}
                showIcon
              />
              <List
                size="small"
                dataSource={modelFields.cache.controlFields}
                renderItem={(field) => (
                  <List.Item
                    actions={[
                      <Button
                        key="control"
                        type="primary"
                        size="small"
                        icon={<ThunderboltOutlined />}
                        onClick={() => {
                          message.info(`下发控制指令: ${field.field_name}`)
                        }}
                      >
                        下发
                      </Button>,
                    ]}
                  >
                    <List.Item.Meta
                      title={`${field.field_name} (${field.field_key})`}
                      description={`类型: ${field.field_type} | 单位: ${field.unit || '无'}`}
                    />
                    <InputNumber
                      style={{ width: 180 }}
                      placeholder={`输入${field.field_name}`}
                      size="small"
                    />
                  </List.Item>
                )}
              />
            </Card>
          )}

          <Card size="small" title="设备控制">
            <div style={{ marginBottom: 12 }}>
              <Text strong>选择指令模板</Text>
              <Select
                placeholder="请选择需下发的控制指令..."
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
                          placeholder={`请输入${param.label}`}
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
                message="注意事项"
                description={selectedCommand.confirmationMessage || '此操作需要二次确认'}
                type="warning"
                showIcon
                style={{ marginBottom: 12 }}
              />
            )}

            {commandResult && (
              <Alert
                message={commandResult.success ? '执行成功' : '执行失败'}
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
                  ? `执行: ${selectedCommand.label}`
                  : '请先选择指令模板'}
              </Button>
              {selectedCommand && (
                <Button onClick={() => { setSelectedCommand(null); setCommandParams({}); setCommandResult(null) }}>
                  重置选择
                </Button>
              )}
              <Button
                icon={<ReloadOutlined />}
                onClick={() => queryClient.invalidateQueries({ queryKey: ['commandTemplates', detailSn] })}
              >
                刷新模板
              </Button>
            </Space>

            <Divider style={{ margin: '8px 0' }} />

            <div>
              <Text strong style={{ display: 'block', marginBottom: 8 }}>
                指令历史
              </Text>
              {commandHistory.length === 0 ? (
                <Empty description="暂无指令记录" image={Empty.PRESENTED_IMAGE_SIMPLE} />
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
                            {item.status === 'pending' && '等待中'}
                            {item.status === 'sent' && '已发送'}
                            {item.status === 'ack_received' && '设备已确认'}
                            {item.status === 'success' && '成功'}
                            {item.status === 'failed' && '失败'}
                            {item.status === 'timeout' && '超时'}
                          </Tag>
                        </Space>
                        <Text type="secondary" style={{ fontSize: 12 }}>
                          {dayjs(item.created_at).format('MM-DD HH:mm:ss')}
                        </Text>
                      </div>
                      {item.params && Object.keys(item.params).length > 0 && (
                        <div style={{ marginTop: 2 }}>
                          <Text type="secondary" style={{ fontSize: 12 }}>
                            参数: {JSON.stringify(item.params)}
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
      label: '生命周期',
      children: (
        <Card size="small" title="生命周期记录">
          {renderLifecyclePanel()}
        </Card>
      ),
    },
  ]

  return (
    <div>
      {contextHolder}

      <Title level={4} style={{ marginBottom: 24 }}>
        设备管理
      </Title>

      {canDirectUnbind && (
        <Card style={{ marginBottom: 16 }}>
          <Tabs
            activeKey={unbindApprovalTab}
            onChange={setUnbindApprovalTab}
            items={[
              {
                key: 'devices',
                label: '设备列表',
              },
              {
                key: 'approvals',
                label: (
                  <span>
                    解绑审批
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
                  placeholder="搜索序列号、型号..."
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
                  placeholder="在线状态"
                  allowClear
                  style={{ width: '100%' }}
                  value={filters.status}
                  onChange={(v) => setFilters((f) => ({ ...f, status: v }))}
                  options={[
                    { label: '全部', value: '' },
                    { label: '在线', value: '1' },
                    { label: '离线', value: '0' },
                    { label: '故障', value: '2' },
                  ]}
                />
              </Col>
              <Col xs={12} sm={8} md={4}>
                <Select
                  placeholder="设备型号"
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
                  placeholder={['最近上线开始', '最近上线结束']}
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
                    搜索
                  </Button>
                  <Button icon={<ReloadOutlined />} onClick={handleReset}>
                    重置
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
                      添加设备
                    </Button>
                  )}
                  {(isSuperAdmin || isAgent) && (
                    <Button icon={<UploadOutlined />} onClick={() => {
                      setImportModalOpen(true)
                      setImportFile(null)
                      setImportPreview([])
                      setImportResult(null)
                    }}>
                      导入Excel
                    </Button>
                  )}
                  {!isEndUser && selectedRowKeys.length > 0 && (
                    <Dropdown menu={{ items: batchMenuItems }} placement="bottomLeft">
                      <Button icon={<SettingOutlined />}>
                        批量操作 ({selectedRowKeys.length})
                      </Button>
                    </Dropdown>
                  )}
                </Space>
              </Col>
              <Col>
                <Text type="secondary">
                  {isInstaller ? '仅展示您安装的设备' : ''}
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
                showTotal: (total) => `共 ${total} 条`,
                onChange: (p, ps) => {
                  setPage(p)
                  setPageSize(ps)
                },
              }}
              onChange={handleTableChange}
              scroll={{ x: 1300 }}
              size="middle"
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
              showTotal: (total) => `共 ${total} 条`,
              onChange: (p, ps) => {
                setUnbindReqPage(p)
                setUnbindReqPageSize(ps)
              },
            }}
            scroll={{ x: 800 }}
            size="middle"
          />
        </Card>
      )}

      <Modal
        title="添加设备"
        open={addModalOpen}
        onCancel={() => setAddModalOpen(false)}
        onOk={handleAddSubmit}
        confirmLoading={createMutation.isPending}
        okText="确认添加"
        cancelText="取消"
        destroyOnClose
      >
        <Form form={addForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item
            name="sn"
            label="设备序列号"
            rules={[{ required: true, message: '请输入设备序列号' }]}
          >
            <Input placeholder="请输入SN" />
          </Form.Item>
          <Form.Item name="model" label="型号">
            <Input placeholder="请输入型号" />
          </Form.Item>
          <Form.Item name="ratedPower" label="额定功率(W)">
            <Input type="number" placeholder="请输入额定功率" />
          </Form.Item>
          <Form.Item name="firmwareVersion" label="固件版本">
            <Input placeholder="请输入固件版本" />
          </Form.Item>
          <Form.Item name="hardwareVersion" label="硬件版本">
            <Input placeholder="请输入硬件版本" />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title="确认执行指令"
        open={confirmModalOpen}
        onOk={handleConfirmExecute}
        onCancel={() => { setConfirmModalOpen(false); setPendingExecution(null) }}
        okText="确认执行"
        cancelText="取消"
        okButtonProps={{ danger: true }}
      >
        <div style={{ marginBottom: 12 }}>
          <Alert
            message={selectedCommand?.label || pendingExecution?.commandName}
            description={
              selectedCommand?.confirmationMessage ||
              '请确认是否执行此操作，部分操作可能影响设备正常运行'
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
        title="编辑设备"
        open={editModalOpen}
        onCancel={() => setEditModalOpen(false)}
        onOk={handleEditSubmit}
        confirmLoading={updateMutation.isPending}
        okText="确认修改"
        cancelText="取消"
        destroyOnClose
      >
        <Form form={editForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item name="sn" label="设备序列号">
            <Input disabled />
          </Form.Item>
          <Form.Item name="model" label="型号">
            <Input placeholder="请输入型号" />
          </Form.Item>
          <Form.Item name="ratedPower" label="额定功率(W)">
            <Input type="number" placeholder="请输入额定功率" />
          </Form.Item>
          <Form.Item name="firmwareVersion" label="固件版本">
            <Input placeholder="请输入固件版本" />
          </Form.Item>
          <Form.Item name="hardwareVersion" label="硬件版本">
            <Input placeholder="请输入硬件版本" />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title="导入设备 (Excel)"
        open={importModalOpen}
        onCancel={() => setImportModalOpen(false)}
        onOk={handleImportSubmit}
        confirmLoading={importing}
        okText="确认导入"
        cancelText="取消"
        width={800}
        okButtonProps={{ disabled: !importFile }}
        destroyOnClose
      >
        <div style={{ marginBottom: 16 }}>
          <Text type="secondary">
            支持 .xlsx / .xls 格式，表头需包含: SN, Model, RatedPower(kW), FirmwareVersion, HardwareVersion, StationName(可选)
          </Text>
          <br />
          <a
            onClick={() => {
              const XLSX = (window as any).XLSX
              if (!XLSX) {
                messageApi.warning('Excel库未加载，请刷新页面')
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
            下载导入模板
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
          <p className="ant-upload-text">点击或拖拽Excel文件到此处</p>
          <p className="ant-upload-hint">仅支持 .xlsx / .xls 格式文件</p>
        </Dragger>

        {importPreview.length > 0 && (
          <div style={{ marginTop: 16 }}>
            <Text strong>数据预览 (前20条):</Text>
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
                    成功: {importResult.success}
                  </Text>
                </Card>
              </Col>
              <Col span={12}>
                <Card size="small">
                  <Text strong style={{ color: '#ff4d4f', fontSize: 18 }}>
                    失败: {importResult.failed}
                  </Text>
                </Card>
              </Col>
            </Row>
            {importResult.errors.length > 0 && (
              <div style={{ marginTop: 8, maxHeight: 200, overflow: 'auto' }}>
                <Table
                  columns={[
                    { title: '行号', dataIndex: 'row', key: 'row', width: 80 },
                    { title: '错误信息', dataIndex: 'message', key: 'message' },
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
        title="申请解绑设备"
        open={unbindModalOpen}
        onCancel={() => {
          setUnbindModalOpen(false)
          setUnbindReason('')
          setUnbindTargetSn('')
        }}
        onOk={handleRequestUnbind}
        confirmLoading={requestUnbindMutation.isPending}
        okText="提交申请"
        cancelText="取消"
        destroyOnClose
      >
        <div style={{ marginBottom: 12 }}>
          <Text>设备序列号: <Text strong>{unbindTargetSn}</Text></Text>
        </div>
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary">解绑需要经过代理商或超级管理员审批</Text>
        </div>
        <Form layout="vertical">
          <Form.Item label="解绑原因" required>
            <AntInput.TextArea
              rows={4}
              placeholder="请输入解绑原因..."
              value={unbindReason}
              onChange={(e) => setUnbindReason(e.target.value)}
            />
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title={
          <Space>
            <span>设备详情</span>
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
                  title="确认重启设备？设备将短暂离线。"
                  onConfirm={() => {
                    commandApi.execute(detailSn, { command: 'restart', params: {} })
                      .then(() => {
                        messageApi.success('重启指令已下发')
                        queryClient.invalidateQueries({ queryKey: ['commandHistory', detailSn] })
                      })
                      .catch(() => messageApi.error('下发失败'))
                  }}
                  okText="确认重启"
                  cancelText="取消"
                >
                  <Button icon={<ReloadOutlined />}>重启设备</Button>
                </Popconfirm>
                <Button
                  icon={<ThunderboltOutlined />}
                  onClick={() => {
                    commandApi.execute(detailSn, { command: 'query_status', params: {} })
                      .then(() => {
                        messageApi.success('状态查询指令已下发')
                        queryClient.invalidateQueries({ queryKey: ['commandHistory', detailSn] })
                      })
                      .catch(() => messageApi.error('下发失败'))
                  }}
                >
                  查询状态
                </Button>
              </>
            )}
            {currentStatus === 0 && (
              <Tag color="red">设备离线，无法执行指令</Tag>
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
          <Spin tip="加载中..." />
        )}
      </Drawer>
    </div>
  )
}

export default DevicesPage
