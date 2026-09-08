import { useState, useCallback, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Button, Input, Select, Space, Modal, Form,
  Descriptions, message, Typography,
  Dropdown, Tag, DatePicker, Divider, Upload, Tabs,
  Input as AntInput, Alert,
} from 'antd'
import Popconfirm from '@/components/LocalizedPopconfirm'
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table'
import type { MenuProps } from 'antd'
import {
  PlusOutlined, SearchOutlined, ReloadOutlined, SettingOutlined,
  DownloadOutlined, DeleteOutlined, LinkOutlined, EditOutlined,
  EyeOutlined, ThunderboltOutlined, MoreOutlined,
  UploadOutlined, InboxOutlined, CheckOutlined, CloseOutlined,
  DisconnectOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import { deviceApi } from '@/services/deviceApi'
import api from '@/services/api'
import { commandApi } from '@/services/commandApi'
import { modelApi } from '@/services/modelApi'
import { userApi } from '@/services/userApi'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import StatusBadge from '@/components/StatusBadge'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import BulkDeviceOperationModal, { type BulkFailure } from './components/BulkDeviceOperationModal'

const { Text, Title } = Typography
const { RangePicker } = DatePicker
const { Dragger } = Upload

interface DeviceRecord {
  id: string
  sn: string
  model: string
  model_id?: number
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

const DevicesPage: React.FC = () => {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { timezone } = useTimezoneStore()

  const { user, hasPermission } = useAuthStore()
  const [messageApi, contextHolder] = message.useMessage()
  const [modal, modalContextHolder] = Modal.useModal()
  const isSuperAdmin = user?.isSystemAdmin
  const isAdmin = isSuperAdmin || hasPermission('devices:manage')
  const isEndUser = !isAdmin
  const isInstaller = !isAdmin
  const canDirectUnbind = isAdmin

  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [filters, setFilters] = useState<DeviceFilters>({})
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([])
  // 批量控制命令（受控状态，避免从 DOM 取 antd Select 值失败的假动作）
  const [batchControlOpen, setBatchControlOpen] = useState(false)
  const [batchCmd, setBatchCmd] = useState<'restart' | 'query_status'>('restart')
  const [batchControlExecuting, setBatchControlExecuting] = useState(false)

  const [addModalOpen, setAddModalOpen] = useState(false)
  const [editModalOpen, setEditModalOpen] = useState(false)
  const [addForm] = Form.useForm()
  const [editForm] = Form.useForm()

  // 批量解绑/删除进度弹窗（串行逐台执行，逐条上报进度）
  const [bulkOpen, setBulkOpen] = useState(false)
  const [bulkAction, setBulkAction] = useState<'unbind' | 'delete'>('unbind')
  const [bulkSns, setBulkSns] = useState<string[]>([])

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

  // 绑定设备（所有权绑定，SN + 铭牌 PIN）相关状态
  const [deviceBindModalOpen, setDeviceBindModalOpen] = useState(false)
  const [bindDeviceForm] = Form.useForm()

  const [modelOptions, setModelOptions] = useState<{ label: string; value: string; model: any }[]>([])

  // 新增/编辑弹窗中当前选中的型号（用于联动预览该型号的额定参数）
  const watchedAddModel = Form.useWatch('model', addForm)
  const selectedAddModel = useMemo(
    () => modelOptions.find((o) => o.value === watchedAddModel)?.model ?? null,
    [modelOptions, watchedAddModel],
  )
  const watchedEditModel = Form.useWatch('model', editForm)
  const selectedEditModel = useMemo(
    () => modelOptions.find((o) => o.value === watchedEditModel)?.model ?? null,
    [modelOptions, watchedEditModel],
  )

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

  const { data: devicesRes, isLoading: devicesLoading, isError: devicesError, refetch: refetchDevices } = useQuery({
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

  useEffect(() => {
    modelApi.listModels().then((res) => {
      const models = res.data?.data ?? res.data ?? []
      setModelOptions(
        models.map((m: any) => ({
          label: `${m.model_name} (${m.model_code})`,
          value: m.model_code,
          model: m,
        })),
      )
    }).catch(() => {})
  }, [])

  const { data: unbindRequestsRes, error: unbindRequestsError, refetch: refetchUnbindRequests } = useQuery({
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
  const { data: installersRes, error: installersError, refetch: refetchInstallers } = useQuery({
    queryKey: ['users', 'installers'],
    queryFn: () =>
      userApi.list({ org_role: 'installer', pageSize: 100 }).then((res) => {
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
  const { data: stationsList = [], error: stationsListError, refetch: refetchStationsList } = useQuery({
    queryKey: ['stations-for-bind'],
    queryFn: () => api.get('/stations', { params: { page_size: 200 }, expectedDataShape: 'page' }).then((res: any) => {
      const d = res.data
      const list = Array.isArray(d) ? d : d?.data?.items || d?.data?.list || d?.list || (Array.isArray(d?.data) ? d?.data : [])
      return Array.isArray(list) ? list : []
    }),
    enabled: bindStationModalOpen || deviceBindModalOpen,
  })

  // 终端用户/渠道角色绑定设备到自己的账户（与管理员建台账的 createDevice 互补，
  // 后端 DeviceHandler.Create 仅限系统管理员，Bind 归属当前用户且凭 PIN 防抢绑）
  const bindDeviceMutation = useMutation({
    mutationFn: ({ sn, pin, stationId }: { sn: string; pin: string; stationId?: number }) =>
      deviceApi.bindDevice(sn, pin, stationId),
    onSuccess: () => {
      messageApi.success(t('dev.bindDeviceSuccess'))
      setDeviceBindModalOpen(false)
      bindDeviceForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['devices'] })
    },
    onError: (err: any) => {
      messageApi.error(err?.response?.data?.message || err?.message || t('common.error'))
    },
  })

  const handleBindDeviceSubmit = async () => {
    try {
      const values = await bindDeviceForm.validateFields()
      bindDeviceMutation.mutate({ sn: values.sn, pin: values.pin, stationId: values.stationId || undefined })
    } catch {
      // validation failed
    }
  }

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

  // modelOptions 里必须存在该型号（防止绕过 Select 校验提交脏数据）
  const isKnownModel = (model: string) => !!model && modelOptions.some((o) => o.value === model)

  const handleAddSubmit = async () => {
    try {
      const values = await addForm.validateFields()
      if (!isKnownModel(values.model)) {
        messageApi.error(t('dev.modelInvalid'))
        return
      }
      // 携带 model_id：与编辑弹窗一致，后端按所选型号同步全部型号关联参数
      const selected = modelOptions.find((o) => o.value === values.model)
      createMutation.mutate({ ...values, model_id: selected?.model?.id })
    } catch {
      // validation failed
    }
  }

  const handleEdit = (record: any) => {
    editForm.setFieldsValue({
      sn: record.sn,
      model: record.model,
    })
    setEditModalOpen(true)
  }

  const handleEditSubmit = async () => {
    try {
      const values = await editForm.validateFields()
      if (!isKnownModel(values.model)) {
        messageApi.error(t('dev.modelInvalid'))
        return
      }
      const selected = modelOptions.find((o) => o.value === values.model)
      // 携带 model_id：后端按所选型号同步更新设备的全部型号关联参数
      updateMutation.mutate({ ...values, model_id: selected?.model?.id ?? undefined })
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
    // 直接跳转完整详情页（全屏），不再经过抽屉
    navigate(`/devices/${sn}/detail`)
  }

  const handleUnbind = (record: DeviceRecord) => {
    if (canDirectUnbind) {
      modal.confirm({
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

  const handleBatchControlSubmit = async () => {
    setBatchControlExecuting(true)
    try {
      await commandApi.batchControl({
        device_sns: selectedRowKeys.map(String),
        command: batchCmd,
        params: {},
      })
      messageApi.success(t('dev.batchControlSuccess'))
      setSelectedRowKeys([])
      setBatchControlOpen(false)
    } catch {
      messageApi.error(t('dev.batchControlFailed'))
    } finally {
      setBatchControlExecuting(false)
    }
  }

  // 批量解绑/删除：确认后打开进度弹窗，串行逐台执行并逐条上报进度
  const startBatchOperation = (action: 'unbind' | 'delete') => {
    const sns = selectedRowKeys.map(String)
    if (sns.length === 0) {
      messageApi.warning(t('dev.selectDevicesFirst'))
      return
    }
    modal.confirm({
      title: action === 'unbind' ? t('dev.batchUnbind') : t('dev.batchDelete'),
      content: action === 'unbind'
        ? t('dev.confirmBatchUnbind', { count: sns.length })
        : t('dev.confirmBatchDelete', { count: sns.length }),
      okText: action === 'unbind' ? t('common.confirm') : t('dev.confirmBatchDeleteBtn'),
      cancelText: t('common.cancel'),
      okButtonProps: action === 'delete' ? { danger: true } : undefined,
      onOk: () => {
        setBulkAction(action)
        setBulkSns(sns)
        setBulkOpen(true)
      },
    })
  }

  const handleBulkExecute = useCallback(async (sn: string) => {
    if (bulkAction === 'unbind') {
      await deviceApi.unbindDevice(sn)
    } else {
      await deviceApi.deleteDevice(sn)
    }
  }, [bulkAction])

  const handleBulkSettled = useCallback((result: { success: string[]; failures: BulkFailure[] }) => {
    queryClient.invalidateQueries({ queryKey: ['devices'] })
    if (result.failures.length === 0) {
      messageApi.success(bulkAction === 'unbind' ? t('dev.batchUnbindComplete') : t('dev.batchDeleteComplete'))
      setSelectedRowKeys([])
      setBulkOpen(false)
    } else {
      messageApi.warning(t('dev.bulkPartialFailed', { success: result.success.length, failed: result.failures.length }))
    }
  }, [bulkAction, messageApi, queryClient, t])

  // 行内快捷指令（自原详情抽屉迁移）：重启需二次确认，查询状态直接下发；离线设备禁用
  const handleQuickCommand = (sn: string, command: 'restart' | 'query_status') => {
    if (command === 'restart') {
      // Dropdown 菜单项无法内嵌 Popconfirm，使用等效的 modal.confirm 二次确认
      modal.confirm({
        title: t('dev.confirmRestart'),
        okText: t('dev.confirmRestartBtn'),
        cancelText: t('common.cancel'),
        onOk: () =>
          commandApi.execute(sn, { command: 'restart', params: {} })
            .then(() => messageApi.success(t('dev.restartSuccess')))
            .catch(() => messageApi.error(t('dev.restartFailed'))),
      })
      return
    }
    commandApi.execute(sn, { command: 'query_status', params: {} })
      .then(() => messageApi.success(t('dev.querySuccess')))
      .catch(() => messageApi.error(t('dev.queryFailed')))
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
      onClick: () => startBatchOperation('unbind'),
    },
    {
      key: 'delete',
      label: t('dev.batchDelete'),
      icon: <DeleteOutlined />,
      danger: true,
      onClick: () => startBatchOperation('delete'),
    },
    {
      key: 'ota',
      label: t('dev.createOTATask'),
      icon: <DownloadOutlined />,
      onClick: () => {
        // 跳转 OTA 页并预填所选设备（ota 页读取 create/sns 参数自动打开创建向导）
        navigate('/ota?create=1&sns=' + selectedRowKeys.map(String).join(','))
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
        setBatchCmd('restart')
        setBatchControlOpen(true)
      },
    },
  ]

  const getCategoryType = (category: string): 'inv' | 'collector' | 'battery' => {
    if (category === 'battery') return 'battery'
    if (category === 'meter') return 'collector'
    return 'inv'
  }

  const deviceTypeConfig = {
    inv: { label: t('station.deviceTypeInverter'), color: 'purple' },
    collector: { label: t('station.deviceTypeCollector'), color: 'cyan' },
    battery: { label: t('station.deviceTypeStorage'), color: 'green' },
  }

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
      title: t('station.deviceType'),
      key: 'device_type',
      width: 90,
      responsive: ['sm'],
      render: (_: any, record: any) => {
        if (!record.model_id || record.model_id === 0) {
          return <Tag color="orange">{t('dev.modelUnbound')}</Tag>
        }
        const devType = getCategoryType(record.model_category ?? '')
        const cfg = deviceTypeConfig[devType]
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
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
              <Dropdown
                menu={{
                  items: [
                    {
                      key: 'restart',
                      icon: <ReloadOutlined />,
                      label: t('dev.restartDevice'),
                      disabled: record.status === 0,
                      onClick: () => handleQuickCommand(record.sn, 'restart'),
                    },
                    {
                      key: 'query_status',
                      icon: <ThunderboltOutlined />,
                      label: t('dev.queryStatus'),
                      disabled: record.status === 0,
                      onClick: () => handleQuickCommand(record.sn, 'query_status'),
                    },
                  ],
                }}
              >
                <Button type="link" size="small" icon={<MoreOutlined />}>
                  {t('dev.moreActions')}
                </Button>
              </Dropdown>
            </>
          )}
        </Space>
      ),
    },
  ]

  const secondaryQueryFailure = [
    { error: unbindRequestsError, retry: refetchUnbindRequests },
    { error: installersError, retry: refetchInstallers },
    { error: stationsListError, retry: refetchStationsList },
  ].find((item) => item.error)

  // 新增/编辑弹窗共用的型号字段：showSearch Select + 必填 + 选中型号联动预览额定参数
  const renderModelFormItem = (selectedModel: any) => (
    <>
      <Form.Item
        name="model"
        label={t('common.model')}
        rules={[{ required: true, message: t('common.required') }]}
      >
        <Select
          showSearch
          placeholder={t('common.select')}
          optionFilterProp="label"
          options={modelOptions}
        />
      </Form.Item>
      {selectedModel && (
        <Alert
          type="info"
          showIcon
          style={{ marginBottom: 16 }}
          message={t('dev.modelLinkedPreview')}
          description={
            <Descriptions size="small" column={2} bordered style={{ marginTop: 8 }}>
              <Descriptions.Item label={t('common.modelName')}>
                {selectedModel.model_name || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.manufacturer')}>
                {selectedModel.manufacturer || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.ratedPower')}>
                {selectedModel.rated_power_w
                  ? `${selectedModel.rated_power_w} W`
                  : selectedModel.rated_power_kw
                    ? `${selectedModel.rated_power_kw} kW`
                    : '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.ratedVoltage')}>
                {selectedModel.rated_voltage_v ? `${selectedModel.rated_voltage_v} V` : '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.ratedFreq')}>
                {selectedModel.rated_frequency_hz ? `${selectedModel.rated_frequency_hz} Hz` : '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.deviceType')}>
                {selectedModel.category || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.batteryVoltage')}>
                {selectedModel.battery_voltage_v ? `${selectedModel.battery_voltage_v} V` : '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.batteryType')}>
                {selectedModel.battery_type || '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.cellCount')}>
                {selectedModel.cell_count ?? '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.mpptCount')}>
                {selectedModel.mppt_count ?? '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.tempSensorCount')}>
                {selectedModel.temp_sensor_count ?? '-'}
              </Descriptions.Item>
              <Descriptions.Item label={t('common.parallelSupport')}>
                {selectedModel.supports_parallel ? t('common.yes') : t('common.no')}
              </Descriptions.Item>
            </Descriptions>
          }
        />
      )}
    </>
  )

  return (
    <div>
      {contextHolder}
      {modalContextHolder}

      {devicesError && (
        <Alert
          type="error"
          showIcon
          message={t('dev.listLoadFailed')}
          action={<Button size="small" danger onClick={() => refetchDevices()}>{t('dev.retryLoad')}</Button>}
          style={{ marginBottom: 16 }}
        />
      )}
      {secondaryQueryFailure && (
        <QueryErrorAlert
          error={secondaryQueryFailure.error}
          onRetry={() => { void secondaryQueryFailure.retry() }}
          style={{ marginBottom: 16 }}
        />
      )}

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
                  {/* 添加设备=建台账（后端仅限系统管理员）；渠道角色/终端用户通过绑定接入外来设备 */}
                  {isSuperAdmin && (
                    <Button type="primary" icon={<PlusOutlined />} onClick={handleAdd}>
                      {t('dev.addDevice')}
                    </Button>
                  )}
                  {hasPermission('devices:create') && (
                    <Button type="primary" icon={<LinkOutlined />} onClick={() => setDeviceBindModalOpen(true)}>
                      {t('dev.bindDevice')}
                    </Button>
                  )}
                  {(isSuperAdmin || isAdmin) && (
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
        destroyOnHidden
      >
        <Form form={addForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item
            name="sn"
            label={t('dev.deviceSN')}
            rules={[{ required: true, message: t('dev.deviceSN') }]}
          >
            <Input placeholder={t('dev.deviceSN')} />
          </Form.Item>
          {renderModelFormItem(selectedAddModel)}
        </Form>
      </Modal>

      <Modal
        title={t('dev.bindDeviceTitle')}
        open={deviceBindModalOpen}
        onCancel={() => setDeviceBindModalOpen(false)}
        onOk={handleBindDeviceSubmit}
        confirmLoading={bindDeviceMutation.isPending}
        okText={t('dev.bindDevice')}
        cancelText={t('common.cancel')}
        destroyOnHidden
      >
        <Alert
          message={t('dev.bindDeviceTip')}
          type="info"
          showIcon
          style={{ marginTop: 16 }}
        />
        <Form form={bindDeviceForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item
            name="sn"
            label={t('dev.deviceSN')}
            rules={[{ required: true, message: t('dev.deviceSN') }]}
          >
            <Input placeholder={t('dev.deviceSN')} />
          </Form.Item>
          <Form.Item
            name="pin"
            label={t('dev.pin')}
            rules={[{ required: true, message: t('dev.pin') }]}
          >
            <Input.Password placeholder={t('dev.pin')} />
          </Form.Item>
          <Form.Item name="stationId" label={t('dev.selectStationOptional')}>
            <Select
              allowClear
              showSearch
              filterOption={(input, option) =>
                (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
              }
              options={(Array.isArray(stationsList) ? stationsList : []).map((s: any) => ({ value: s.id, label: s.name }))}
            />
          </Form.Item>
        </Form>
      </Modal>

      <Modal
        title={t('dev.editDeviceTitle')}
        open={editModalOpen}
        onCancel={() => setEditModalOpen(false)}
        onOk={handleEditSubmit}
        confirmLoading={updateMutation.isPending}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
        destroyOnHidden
      >
        <Form form={editForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item name="sn" label={t('dev.deviceSN')}>
            <Input disabled />
          </Form.Item>
          {renderModelFormItem(selectedEditModel)}
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
        destroyOnHidden
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
        destroyOnHidden
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

      {/* 批量解绑/删除进度弹窗 */}
      <BulkDeviceOperationModal
        open={bulkOpen}
        title={bulkAction === 'unbind' ? t('dev.batchUnbind') : t('dev.batchDelete')}
        sns={bulkSns}
        execute={handleBulkExecute}
        onCancel={() => {
          setBulkOpen(false)
          // 中途取消也可能已有部分成功，仍需刷新列表
          queryClient.invalidateQueries({ queryKey: ['devices'] })
        }}
        onSettled={handleBulkSettled}
      />

      {/* 批量控制命令Modal */}
      <Modal
        title={t('dev.batchControlTitle')}
        open={batchControlOpen}
        onCancel={() => setBatchControlOpen(false)}
        onOk={handleBatchControlSubmit}
        confirmLoading={batchControlExecuting}
        okText={t('common.confirm')}
        cancelText={t('common.cancel')}
      >
        <p>{t('dev.batchControlConfirm', { count: selectedRowKeys.length, cmd: batchCmd })}</p>
        <Select
          value={batchCmd}
          style={{ width: '100%', marginTop: 8 }}
          onChange={(v) => setBatchCmd(v)}
          options={[
            { label: 'restart', value: 'restart' },
            { label: 'query_status', value: 'query_status' },
          ]}
        />
      </Modal>

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
            options={(Array.isArray(stationsList) ? stationsList : []).map((s: any) => ({ value: s.id, label: s.name }))}
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
        destroyOnHidden
      >
        <div style={{ marginBottom: 16 }}>
          <Text>{t('dev.deviceSN')}: </Text>
          <Text strong>{assignTargetSn}</Text>
        </div>
        <div>
          <Text>{t('dev.selectInstaller')}: </Text>
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
