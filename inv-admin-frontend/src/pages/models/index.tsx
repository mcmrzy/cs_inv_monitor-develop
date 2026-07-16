import { useState, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Input, Space, Modal, Form, Select, Switch,
  Tag, Popconfirm, message, Typography, InputNumber, Drawer,
  Empty, Collapse, Tabs, Tooltip, Badge, Descriptions, Divider,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SettingOutlined, DeleteOutlined, EditOutlined,
  ThunderboltOutlined, ApiOutlined, EyeOutlined, EyeInvisibleOutlined,
  ControlOutlined, InfoCircleOutlined,
} from '@ant-design/icons'
import { modelApi, DeviceModelItem, DeviceModelFieldItem, DeviceModelProtocolItem, ModelFieldCapability, ModelCommandCapability } from '@/services/modelApi'
import useTranslation from '@/hooks/useTranslation'
import ModelRegistryWorkspace from './model_registry_workspace'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text, Title } = Typography

const GROUP_CONFIG_KEYS = [
  'models.acParams', 'models.batteryParams', 'models.pvParams',
  'models.systemStatus', 'models.energyStats', 'models.deviceInfo',
  'models.controlStatus', 'models.inverterControl', 'models.bmsControl',
  'models.mpptControl', 'models.epsControl', 'models.parallelControl',
]

const GROUP_COLOR_MAP: Record<string, string> = {
  'models.acParams': '#7c3aed',
  'models.batteryParams': '#10b981',
  'models.pvParams': '#f59e0b',
  'models.systemStatus': '#06b6d4',
  'models.energyStats': '#3b82f6',
  'models.deviceInfo': '#6b7280',
  'models.controlStatus': '#8b5cf6',
  'models.inverterControl': '#ef4444',
  'models.bmsControl': '#ef4444',
  'models.mpptControl': '#ef4444',
  'models.epsControl': '#ef4444',
  'models.parallelControl': '#ef4444',
}

const GROUP_ICON_MAP: Record<string, string> = {
  'models.acParams': '\u26a1',
  'models.batteryParams': '\ud83d\udd0b',
  'models.pvParams': '\u2600\ufe0f',
  'models.systemStatus': '\ud83d\udcca',
  'models.energyStats': '\ud83d\udcc8',
  'models.deviceInfo': '\ud83d\udccb',
  'models.controlStatus': '\ud83c\udf9b\ufe0f',
  'models.inverterControl': '\ud83c\udfae',
  'models.bmsControl': '\ud83c\udfae',
  'models.mpptControl': '\ud83c\udfae',
  'models.epsControl': '\ud83c\udfae',
  'models.parallelControl': '\ud83c\udfae',
}

const ModelsPage: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [messageApi, contextHolder] = message.useMessage()

  const GROUP_NAME_MAP: Record<string, string> = {
    [t('models.acParams')]: 'models.acParams',
    [t('models.batteryParams')]: 'models.batteryParams',
    [t('models.pvParams')]: 'models.pvParams',
    [t('models.systemStatus')]: 'models.systemStatus',
    [t('models.energyStats')]: 'models.energyStats',
    [t('models.deviceInfo')]: 'models.deviceInfo',
    [t('models.controlStatus')]: 'models.controlStatus',
    [t('models.inverterControl')]: 'models.inverterControl',
    [t('models.bmsControl')]: 'models.bmsControl',
    [t('models.mpptControl')]: 'models.mpptControl',
    [t('models.epsControl')]: 'models.epsControl',
    [t('models.parallelControl')]: 'models.parallelControl',
  }

  const getGroupConfig = (groupName: string) => {
    const key = GROUP_CONFIG_KEYS.includes(groupName) ? groupName : GROUP_NAME_MAP[groupName]
    return {
      color: (key ? GROUP_COLOR_MAP[key] : null) || '#999',
      icon: (key ? GROUP_ICON_MAP[key] : null) || '\ud83d\udcc1',
    }
  }

  // 将 group_name 转为显示文本（英文key翻译，中文文本原样显示）
  const getGroupDisplayName = (groupName: string) => {
    if (GROUP_CONFIG_KEYS.includes(groupName)) return t(groupName)
    return groupName
  }

  const FIELD_TYPE_OPTIONS = [
    { label: t('models.floatType'), value: 'float' },
    { label: t('models.intType'), value: 'int' },
    { label: t('models.stringType'), value: 'string' },
    { label: t('models.boolType'), value: 'bool' },
  ]

  const PARSE_TYPE_OPTIONS = [
    { label: 'JSON', value: 'json' },
    { label: 'Modbus', value: 'modbus' },
    { label: t('models.custom'), value: 'custom' },
  ]

  const CATEGORY_OPTIONS = [
    { label: t('models.inverter'), value: 'inverter' },
    { label: t('models.energyStorage'), value: 'storage' },
    { label: t('models.chargingPile'), value: 'charger' },
    { label: t('models.meter'), value: 'meter' },
    { label: t('models.hybrid'), value: 'hybrid' },
  ]

  const INPUT_TYPE_OPTIONS = [
    { label: t('models.sliderInput'), value: 'number' },
    { label: t('models.dropdownSelect'), value: 'select' },
    { label: t('models.switchToggle'), value: 'switch' },
  ]

  const [keyword, setKeyword] = useState('')
  const [modelModalOpen, setModelModalOpen] = useState(false)
  const [editingModel, setEditingModel] = useState<DeviceModelItem | null>(null)
  const [modelForm] = Form.useForm()

  const [fieldsDrawerOpen, setFieldsDrawerOpen] = useState(false)
  const [currentModelId, setCurrentModelId] = useState<number | null>(null)
  const [currentModelName, setCurrentModelName] = useState('')
  const [fieldModalOpen, setFieldModalOpen] = useState(false)
  const [editingField, setEditingField] = useState<DeviceModelFieldItem | null>(null)
  const [fieldForm] = Form.useForm()
  const [isControl, setIsControl] = useState(false)

  const [protocolModalOpen, setProtocolModalOpen] = useState(false)
  const [editingProtocol, setEditingProtocol] = useState<DeviceModelProtocolItem | null>(null)
  const [protocolForm] = Form.useForm()

  const { data: modelList = [], isLoading, error: modelsError, refetch: refetchModels } = useQuery({
    queryKey: ['models'],
    queryFn: () => modelApi.listModels().then((res) => {
      const d = res.data
      return (Array.isArray(d?.data) ? d.data : Array.isArray(d) ? d : []) as DeviceModelItem[]
    }),
  })

  const { data: fieldList = [], error: fieldsError, refetch: refetchFields } = useQuery({
    queryKey: ['modelFields', currentModelId],
    queryFn: () => modelApi.getFields(currentModelId!).then((res) => {
      const d = res.data
      return (Array.isArray(d?.data) ? d.data : Array.isArray(d) ? d : []) as DeviceModelFieldItem[]
    }),
    enabled: currentModelId != null,
  })

  const { data: protocolList = [], error: protocolsError, refetch: refetchProtocols } = useQuery({
    queryKey: ['modelProtocols', currentModelId],
    queryFn: () => modelApi.getProtocols(currentModelId!).then((res) => {
      const d = res.data
      return (Array.isArray(d?.data) ? d.data : Array.isArray(d) ? d : []) as DeviceModelProtocolItem[]
    }),
    enabled: currentModelId != null,
  })

  const { data: fieldCapabilities = [], error: fieldCapabilitiesError, refetch: refetchFieldCapabilities } = useQuery<ModelFieldCapability[]>({
    queryKey: ['modelFieldCapabilities', currentModelId],
    queryFn: () => modelApi.getFieldCapabilities(currentModelId!).then((res) => res.data?.data ?? res.data ?? []),
    enabled: currentModelId != null && fieldsDrawerOpen,
  })

  const { data: commandCapabilities = [], error: commandCapabilitiesError, refetch: refetchCommandCapabilities } = useQuery<ModelCommandCapability[]>({
    queryKey: ['modelCommandCapabilities', currentModelId],
    queryFn: () => modelApi.getCommandCapabilities(currentModelId!).then((res) => res.data?.data ?? res.data ?? []),
    enabled: currentModelId != null && fieldsDrawerOpen,
  })

  const { data: protocolSchema, error: protocolSchemaError, refetch: refetchProtocolSchema } = useQuery<any>({
    queryKey: ['modelProtocolSchema', currentModelId],
    queryFn: () => modelApi.getProtocolSchema(currentModelId!).then((res) => res.data?.data ?? res.data),
    enabled: currentModelId != null && fieldsDrawerOpen,
  })

  const updateFieldCapabilityMut = useMutation({
    mutationFn: ({ fieldKey, data }: { fieldKey: string; data: Partial<ModelFieldCapability> }) =>
      modelApi.updateFieldCapability(currentModelId!, fieldKey, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['modelFieldCapabilities', currentModelId] }),
    onError: () => messageApi.error(t('models.fieldCapabilityUpdateFailed')),
  })

  const updateCommandCapabilityMut = useMutation({
    mutationFn: ({ commandCode, data }: { commandCode: string; data: Partial<ModelCommandCapability> }) =>
      modelApi.updateCommandCapability(currentModelId!, commandCode, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['modelCommandCapabilities', currentModelId] }),
    onError: () => messageApi.error(t('models.commandCapabilityUpdateFailed')),
  })

  const groupedFields = useMemo(() => {
    const groups: Record<string, DeviceModelFieldItem[]> = {}
    for (const f of fieldList) {
      const g = f.group_name || t('models.noGroup')
      if (!groups[g]) groups[g] = []
      groups[g].push(f)
    }
    for (const list of Object.values(groups)) {
      list.sort((a, b) => a.sort - b.sort)
    }
    return groups
  }, [fieldList, t])

  const filteredModels = modelList.filter(
    (m) => !keyword || m.model_code.toLowerCase().includes(keyword.toLowerCase()) || m.model_name.toLowerCase().includes(keyword.toLowerCase())
  )

  const createModelMut = useMutation({
    mutationFn: (data: any) => modelApi.createModel(data),
    onSuccess: () => { messageApi.success(t('models.modelCreateSuccess')); setModelModalOpen(false); modelForm.resetFields(); queryClient.invalidateQueries({ queryKey: ['models'] }) },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.modelCreateFailed')),
  })

  const updateModelMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => modelApi.updateModel(id, data),
    onSuccess: () => { messageApi.success(t('models.modelUpdateSuccess')); setModelModalOpen(false); modelForm.resetFields(); queryClient.invalidateQueries({ queryKey: ['models'] }) },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.modelUpdateFailed')),
  })

  const deleteModelMut = useMutation({
    mutationFn: (id: number) => modelApi.deleteModel(id),
    onSuccess: () => { messageApi.success(t('models.modelDeleteSuccess')); queryClient.invalidateQueries({ queryKey: ['models'] }) },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.modelDeleteFailed')),
  })

  const createFieldMut = useMutation({
    mutationFn: ({ modelId, data }: { modelId: number; data: any }) => modelApi.createField(modelId, data),
    onSuccess: () => { messageApi.success(t('models.fieldAddSuccess')); setFieldModalOpen(false); fieldForm.resetFields(); queryClient.invalidateQueries({ queryKey: ['modelFields', currentModelId] }) },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.fieldAddFailed')),
  })

  const updateFieldMut = useMutation({
    mutationFn: ({ modelId, fieldId, data }: { modelId: number; fieldId: number; data: any }) => modelApi.updateField(modelId, fieldId, data),
    onSuccess: () => { messageApi.success(t('models.fieldUpdateSuccess')); setFieldModalOpen(false); fieldForm.resetFields(); queryClient.invalidateQueries({ queryKey: ['modelFields', currentModelId] }) },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.fieldUpdateFailed')),
  })

  const deleteFieldMut = useMutation({
    mutationFn: ({ modelId, fieldId }: { modelId: number; fieldId: number }) => modelApi.deleteField(modelId, fieldId),
    onSuccess: () => { messageApi.success(t('models.fieldDeleteSuccess')); queryClient.invalidateQueries({ queryKey: ['modelFields', currentModelId] }) },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.fieldDeleteFailed')),
  })

  const createProtocolMut = useMutation({
    mutationFn: ({ modelId, data }: { modelId: number; data: any }) => modelApi.createProtocol(modelId, data),
    onSuccess: () => { messageApi.success(t('models.protocolAddSuccess')); setProtocolModalOpen(false); protocolForm.resetFields(); refetchProtocols() },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.protocolAddFailed')),
  })

  const updateProtocolMut = useMutation({
    mutationFn: ({ modelId, protocolId, data }: { modelId: number; protocolId: number; data: any }) => modelApi.updateProtocol(modelId, protocolId, data),
    onSuccess: () => { messageApi.success(t('models.protocolUpdateSuccess')); setProtocolModalOpen(false); protocolForm.resetFields(); refetchProtocols() },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.protocolUpdateFailed')),
  })

  const deleteProtocolMut = useMutation({
    mutationFn: ({ modelId, protocolId }: { modelId: number; protocolId: number }) => modelApi.deleteProtocol(modelId, protocolId),
    onSuccess: () => { messageApi.success(t('models.protocolDeleteSuccess')); refetchProtocols() },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || t('models.protocolDeleteFailed')),
  })

  const handleManageFields = (record: DeviceModelItem) => {
    setCurrentModelId(record.id)
    setCurrentModelName(record.model_name)
    setFieldsDrawerOpen(true)
  }

  const handleCreateField = (groupName?: string) => {
    setEditingField(null)
    fieldForm.resetFields()
    // 兼容旧数据：将中文 group_name 转换为英文 key
    let resolvedGroup = groupName || ''
    if (resolvedGroup && !GROUP_CONFIG_KEYS.includes(resolvedGroup) && GROUP_NAME_MAP[resolvedGroup]) {
      resolvedGroup = GROUP_NAME_MAP[resolvedGroup]
    }
    fieldForm.setFieldsValue({ field_type: 'float', sort: 0, is_show: true, is_control: false, group_name: resolvedGroup })
    setIsControl(false)
    setFieldModalOpen(true)
  }

  const handleEditField = (record: DeviceModelFieldItem) => {
    setEditingField(record)
    const values = { ...record }
    // 兼容旧数据：将中文 group_name 转换为英文 key
    if (values.group_name && !GROUP_CONFIG_KEYS.includes(values.group_name) && GROUP_NAME_MAP[values.group_name]) {
      values.group_name = GROUP_NAME_MAP[values.group_name]
    }
    // 确保 is_show / is_control 为严格布尔值，避免 Switch 组件因类型不匹配而显示异常
    values.is_show = Boolean(values.is_show)
    values.is_control = Boolean(values.is_control)
    fieldForm.setFieldsValue(values)
    setIsControl(Boolean(record.is_control))
    setFieldModalOpen(true)
  }

  const handleFieldSubmit = () => {
    fieldForm.validateFields().then((values) => {
      if (!values.is_control) {
        values.control_params = {}
      }
      if (editingField) {
        updateFieldMut.mutate({ modelId: currentModelId!, fieldId: editingField.id, data: values })
      } else {
        createFieldMut.mutate({ modelId: currentModelId!, data: values })
      }
    })
  }

  const handleCreateProtocol = () => {
    setEditingProtocol(null)
    protocolForm.resetFields()
    protocolForm.setFieldsValue({ parse_type: 'json', is_active: true })
    setProtocolModalOpen(true)
  }

  const handleEditProtocol = (record: DeviceModelProtocolItem) => {
    setEditingProtocol(record)
    protocolForm.setFieldsValue(record)
    setProtocolModalOpen(true)
  }

  const handleProtocolSubmit = () => {
    protocolForm.validateFields().then((values) => {
      if (typeof values.parse_config === 'string') {
        try { values.parse_config = JSON.parse(values.parse_config) } catch { values.parse_config = {} }
      }
      if (editingProtocol) {
        updateProtocolMut.mutate({ modelId: currentModelId!, protocolId: editingProtocol.id, data: values })
      } else {
        createProtocolMut.mutate({ modelId: currentModelId!, data: values })
      }
    })
  }

  const modelColumns: ColumnsType<DeviceModelItem> = [
    { title: 'ID', dataIndex: 'id', key: 'id', width: 60 },
    { title: t('models.modelCode'), dataIndex: 'model_code', key: 'model_code', width: 140 },
    { title: t('models.modelName'), dataIndex: 'model_name', key: 'model_name', width: 160 },
    { title: t('models.manufacturer'), dataIndex: 'manufacturer', key: 'manufacturer', width: 120, render: (v: string) => v || '-' },
    { title: t('models.category'), dataIndex: 'category', key: 'category', width: 100, render: (v: string) => <Tag>{v}</Tag> },
    { title: t('models.ratedPower'), dataIndex: 'rated_power_kw', key: 'rated_power_kw', width: 100, render: (v: number) => v != null ? `${v} kW` : '-' },
    { title: t('models.deviceCount'), dataIndex: 'device_count', key: 'device_count', width: 80, render: (v: number) => v ?? 0 },
    { title: t('models.status'), dataIndex: 'is_active', key: 'is_active', width: 80, render: (v: boolean) => <Tag color={v ? 'green' : 'red'}>{v ? t('common.enabled') : t('common.disabled')}</Tag> },
    {
      title: t('common.operation'), key: 'actions', width: 200, fixed: 'right',
      render: (_, record) => (
        <Space size="small">
          <Button size="small" icon={<SettingOutlined />} onClick={() => handleManageFields(record)}>{t('models.config')}</Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => { setEditingModel(record); modelForm.setFieldsValue(record); setModelModalOpen(true) }} />
          <Popconfirm title={t('models.confirmDeleteModel')} onConfirm={() => deleteModelMut.mutate(record.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  const protocolColumns: ColumnsType<DeviceModelProtocolItem> = [
    { title: t('models.topicPattern'), dataIndex: 'topic_pattern', key: 'topic_pattern', width: 200, render: (v: string) => <Text code>{v}</Text> },
    { title: t('models.parseType'), dataIndex: 'parse_type', key: 'parse_type', width: 100, render: (v: string) => <Tag color="blue">{v}</Tag> },
    { title: t('models.parseConfig'), dataIndex: 'parse_config', key: 'parse_config', width: 200, ellipsis: true, render: (v: any) => v && Object.keys(v).length > 0 ? <Text code style={{ fontSize: 11 }}>{JSON.stringify(v)}</Text> : '-' },
    { title: t('models.status'), dataIndex: 'is_active', key: 'is_active', width: 80, render: (v: boolean) => <Tag color={v ? 'green' : 'default'}>{v ? t('common.enabled') : t('common.disabled')}</Tag> },
    {
      title: t('common.operation'), key: 'actions', width: 120,
      render: (_, record) => (
        <Space size="small">
          <Button size="small" icon={<EditOutlined />} onClick={() => handleEditProtocol(record)} />
          <Popconfirm title={t('models.confirmDeleteProtocol')} onConfirm={() => deleteProtocolMut.mutate({ modelId: currentModelId!, protocolId: record.id })}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  const renderFieldGroups = () => {
    const groupNames = Object.keys(groupedFields)
    if (groupNames.length === 0) {
      return <Empty description={t('models.noFields')} />
    }

    const displayGroups = groupNames.filter(g => !groupedFields[g].some(f => f.is_control))
    const controlGroups = groupNames.filter(g => groupedFields[g].some(f => f.is_control))

    return (
      <>
        {displayGroups.length > 0 && (
          <>
            <Text strong style={{ fontSize: 13, color: '#666', marginBottom: 8, display: 'block' }}>
              <EyeOutlined /> {t('models.displayFields')} ({displayGroups.reduce((s, g) => s + groupedFields[g].filter(f => f.is_show).length, 0)})
            </Text>
            <Collapse
              size="small"
              defaultActiveKey={displayGroups}
              items={displayGroups.map(groupName => ({
                key: groupName,
                label: (
                  <Space>
                    <span>{getGroupConfig(groupName).icon}</span>
                    <Text strong>{getGroupDisplayName(groupName)}</Text>
                    <Badge count={groupedFields[groupName].length} style={{ backgroundColor: getGroupConfig(groupName).color }} />
                  </Space>
                ),
                extra: (
                  <Button size="small" type="link" icon={<PlusOutlined />}
                    onClick={(e) => { e.stopPropagation(); handleCreateField(groupName) }}>
                    {t('models.add')}
                  </Button>
                ),
                children: (
                  <Table
                    size="small"
                    rowKey="id"
                    dataSource={groupedFields[groupName]}
                    pagination={false}
                    columns={[
                      { title: t('models.fieldId'), dataIndex: 'field_key', key: 'field_key', width: 180, render: (v: string) => <Text code style={{ fontSize: 12 }}>{v}</Text> },
                      { title: t('models.displayName'), dataIndex: 'field_name', key: 'field_name', width: 120 },
                      { title: t('models.type'), dataIndex: 'field_type', key: 'field_type', width: 80, render: (v: string) => <Tag>{v}</Tag> },
                      { title: t('models.unit'), dataIndex: 'unit', key: 'unit', width: 60, render: (v: string) => v || '-' },
                      { title: t('models.display'), dataIndex: 'is_show', key: 'is_show', width: 60, render: (v: boolean) => v ? <EyeOutlined style={{ color: '#52c41a' }} /> : <EyeInvisibleOutlined style={{ color: '#ccc' }} /> },
                      { title: t('models.parseRule'), dataIndex: 'parse_rule', key: 'parse_rule', width: 120, ellipsis: true, render: (v: string) => v ? <Text code style={{ fontSize: 11 }}>{v}</Text> : '-' },
                      {
                        title: t('common.operation'), key: 'actions', width: 80,
                        render: (_, record) => (
                          <Space size="small">
                            <Button size="small" type="link" icon={<EditOutlined />} onClick={() => handleEditField(record)} />
                            <Popconfirm title={t('models.confirmDelete')} onConfirm={() => deleteFieldMut.mutate({ modelId: currentModelId!, fieldId: record.id })}>
                              <Button size="small" type="link" danger icon={<DeleteOutlined />} />
                            </Popconfirm>
                          </Space>
                        ),
                      },
                    ]}
                  />
                ),
              }))}
            />
            <Divider />
          </>
        )}

        {controlGroups.length > 0 && (
          <>
            <Text strong style={{ fontSize: 13, color: '#666', marginBottom: 8, display: 'block' }}>
              <ControlOutlined /> {t('models.controlCommands')} ({controlGroups.reduce((s, g) => s + groupedFields[g].length, 0)})
            </Text>
            <Collapse
              size="small"
              defaultActiveKey={controlGroups}
              items={controlGroups.map(groupName => ({
                key: groupName,
                label: (
                  <Space>
                    <span>{getGroupConfig(groupName).icon}</span>
                    <Text strong>{getGroupDisplayName(groupName)}</Text>
                    <Badge count={groupedFields[groupName].length} style={{ backgroundColor: '#ef4444' }} />
                  </Space>
                ),
                extra: (
                  <Button size="small" type="link" icon={<PlusOutlined />}
                    onClick={(e) => { e.stopPropagation(); handleCreateField(groupName) }}>
                    {t('models.add')}
                  </Button>
                ),
                children: (
                  <Table
                    size="small"
                    rowKey="id"
                    dataSource={groupedFields[groupName]}
                    pagination={false}
                    columns={[
                      { title: t('models.commandId'), dataIndex: 'field_key', key: 'field_key', width: 180, render: (v: string) => <Text code style={{ fontSize: 12 }}>{v}</Text> },
                      { title: t('models.displayName'), dataIndex: 'field_name', key: 'field_name', width: 120 },
                      { title: t('models.paramType'), dataIndex: 'field_type', key: 'field_type', width: 80, render: (v: string) => <Tag>{v}</Tag> },
                      {
                        title: t('models.controlParam'), dataIndex: 'control_params', key: 'control_params', width: 250,
                        render: (v: any) => {
                          if (!v || Object.keys(v).length === 0) return '-'
                          const parts = []
                          if (v.confirm) parts.push(t('models.needConfirmShort'))
                          if (v.input_type === 'number') parts.push(`${t('models.numericInput')}: ${v.min ?? 0}~${v.max ?? '?'}`)
                          if (v.input_type === 'select') parts.push(`${t('models.dropdownSelect')}: ${v.options?.length ?? 0}${t('models.items')}`)
                          return <Text type="secondary" style={{ fontSize: 12 }}>{parts.join(' | ')}</Text>
                        },
                      },
                      {
                        title: t('common.operation'), key: 'actions', width: 80,
                        render: (_, record) => (
                          <Space size="small">
                            <Button size="small" type="link" icon={<EditOutlined />} onClick={() => handleEditField(record)} />
                            <Popconfirm title={t('models.confirmDelete')} onConfirm={() => deleteFieldMut.mutate({ modelId: currentModelId!, fieldId: record.id })}>
                              <Button size="small" type="link" danger icon={<DeleteOutlined />} />
                            </Popconfirm>
                          </Space>
                        ),
                      },
                    ]}
                  />
                ),
              }))}
            />
          </>
        )}
      </>
    )
  }

  const queryFailure = [
    { error: modelsError, retry: refetchModels },
    { error: fieldsError, retry: refetchFields },
    { error: protocolsError, retry: refetchProtocols },
    { error: fieldCapabilitiesError, retry: refetchFieldCapabilities },
    { error: commandCapabilitiesError, retry: refetchCommandCapabilities },
    { error: protocolSchemaError, retry: refetchProtocolSchema },
  ].find((item) => item.error)

  return (
    <>
      {contextHolder}
      {queryFailure && (
        <QueryErrorAlert
          error={queryFailure.error}
          onRetry={() => { void queryFailure.retry() }}
          style={{ marginBottom: 16 }}
        />
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16, flexWrap: 'wrap', gap: 8 }}>
        <Title level={4} style={{ margin: 0 }}>{t('models.title')}</Title>
        <Space>
          <Input.Search placeholder={t('models.searchModel')} allowClear style={{ width: 220 }}
            onSearch={setKeyword} onChange={(e) => !e.target.value && setKeyword('')} />
          <Button type="primary" icon={<PlusOutlined />} onClick={() => { setEditingModel(null); modelForm.resetFields(); modelForm.setFieldsValue({ category: 'inverter', rated_power_kw: 0 }); setModelModalOpen(true) }}>
            {t('models.addModel')}
          </Button>
        </Space>
      </div>

      <Card
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        <Table rowKey="id" columns={modelColumns} dataSource={filteredModels} loading={isLoading} size="middle"
          pagination={{ pageSize: 20, showSizeChanger: true, showTotal: (total) => t('common.total', { total }) }}
          scroll={{ x: 1000 }}
          locale={{ emptyText: <Empty description={t('common.noData')} /> }} />
      </Card>

      <Drawer
        title={
          <Space>
            <SettingOutlined />
            <span>{t('models.fieldConfig')} - {currentModelName}</span>
            <Tag>{t('models.fieldCount', { count: fieldList.length })}</Tag>
          </Space>
        }
        open={fieldsDrawerOpen}
        onClose={() => setFieldsDrawerOpen(false)}
        width={1000}
      >
        <Tabs
          items={[
            {
              key: 'fields',
              label: <span><EyeOutlined /> {t('models.monitoringFields')}</span>,
              children: <Table<ModelFieldCapability>
                rowKey="id"
                size="small"
                pagination={false}
                dataSource={fieldCapabilities}
                columns={[
                  { title: t('models.registry.standardField'), dataIndex: 'field_key', width: 190 },
                  { title: t('models.group'), dataIndex: 'group_code', width: 100 },
                  { title: t('models.type'), dataIndex: 'field_type', width: 90 },
                  { title: t('models.unit'), dataIndex: 'display_unit', width: 80, render: (v, r) => v || r.base_unit || '-' },
                  { title: t('models.realtime'), dataIndex: 'show_realtime', width: 70, render: (v, r) => <Switch size="small" checked={v} onChange={checked => updateFieldCapabilityMut.mutate({ fieldKey: r.field_key, data: { show_realtime: checked } })} /> },
                  { title: t('models.history'), dataIndex: 'show_history', width: 70, render: (v, r) => <Switch size="small" checked={v} onChange={checked => updateFieldCapabilityMut.mutate({ fieldKey: r.field_key, data: { show_history: checked } })} /> },
                  { title: t('models.compare'), dataIndex: 'allow_compare', width: 70, render: (v, r) => <Switch size="small" checked={v} onChange={checked => updateFieldCapabilityMut.mutate({ fieldKey: r.field_key, data: { allow_compare: checked } })} /> },
                  { title: t('models.allowAlarm'), dataIndex: 'allow_alarm_rule', width: 70, render: (v, r) => <Switch size="small" checked={v} onChange={checked => updateFieldCapabilityMut.mutate({ fieldKey: r.field_key, data: { allow_alarm_rule: checked } })} /> },
                ]}
                locale={{ emptyText: <Empty description={t('models.emptyFieldCapability')} /> }}
              />,
            },
            {
              key: 'commands',
              label: <span><ControlOutlined /> {t('models.controlCapability')}</span>,
              children: <Table<ModelCommandCapability>
                rowKey="id" size="small" pagination={false} dataSource={commandCapabilities}
                columns={[
                  { title: t('models.commandCode'), dataIndex: 'command_code', width: 220 },
                  { title: t('models.risk'), dataIndex: 'risk_level', width: 80, render: v => <Tag color={v === 3 ? 'red' : v === 2 ? 'orange' : 'blue'}>L{v}</Tag> },
                  { title: t('models.timeout'), dataIndex: 'timeout_seconds', width: 90, render: v => `${v}s` },
                  { title: t('models.requiresOnline'), dataIndex: 'requires_online', width: 90, render: (v, r) => <Switch size="small" checked={v} onChange={checked => updateCommandCapabilityMut.mutate({ commandCode: r.command_code, data: { requires_online: checked } })} /> },
                  { title: t('models.enabled'), dataIndex: 'is_enabled', width: 70, render: (v, r) => <Switch size="small" checked={v} onChange={checked => updateCommandCapabilityMut.mutate({ commandCode: r.command_code, data: { is_enabled: checked } })} /> },
                  { title: t('models.parameterSchema'), dataIndex: 'parameter_schema', render: v => <Text code>{JSON.stringify(v)}</Text> },
                ]}
              />,
            },
            {
              key: 'protocol',
              label: <span><ApiOutlined /> {t('models.protocolVersionTab')}</span>,
              children: <>
                <Descriptions size="small" bordered column={2} style={{ marginBottom: 12 }}>
                  <Descriptions.Item label={t('models.protocolLabel')}>{protocolSchema?.protocol_code ?? '-'}</Descriptions.Item>
                  <Descriptions.Item label={t('models.versionLabel')}>{protocolSchema?.version ?? '-'}</Descriptions.Item>
                  <Descriptions.Item label={t('models.statusLabel')}><Tag color="green">{protocolSchema?.status ?? '-'}</Tag></Descriptions.Item>
                  <Descriptions.Item label={t('models.schemaHash')}>{protocolSchema?.schema_hash ?? '-'}</Descriptions.Item>
                </Descriptions>
                <Table rowKey={(r: any) => `${r.group_code}-${r.field_index}`} size="small" pagination={false}
                  dataSource={protocolSchema?.fields ?? []}
                  columns={[
                    { title: t('models.arrayGroup'), dataIndex: 'group_code', width: 90 },
                    { title: t('models.subscript'), dataIndex: 'field_index', width: 70 },
                    { title: t('models.registry.standardField'), dataIndex: 'field_key', width: 220 },
                    { title: t('models.wireType'), dataIndex: 'wire_type', width: 100 },
                    { title: t('models.range'), render: (_: any, r: any) => `${r.minimum ?? '-'} ~ ${r.maximum ?? '-'}` },
                  ]}
                />
              </>,
            },
          ]}
        />
      </Drawer>

      <Modal title={editingModel ? t('models.editModel') : t('models.addModel')} open={modelModalOpen}
        onOk={() => modelForm.validateFields().then((values) => editingModel ? updateModelMut.mutate({ id: editingModel.id, data: values }) : createModelMut.mutate(values))}
        onCancel={() => setModelModalOpen(false)} confirmLoading={createModelMut.isPending || updateModelMut.isPending} width={560}>
        <Form form={modelForm} layout="vertical">
          <Form.Item name="model_code" label={t('models.modelCode')} rules={[{ required: true, message: t('models.pleaseInputModelCode') }]}><Input placeholder={t('models.mCodePlaceholder')} disabled={!!editingModel} /></Form.Item>
          <Form.Item name="model_name" label={t('models.modelName')} rules={[{ required: true, message: t('models.pleaseInputModelName') }]}><Input placeholder={t('models.mNamePlaceholder')} /></Form.Item>
          <Form.Item name="manufacturer" label={t('models.manufacturer')}><Input placeholder={t('models.manufacturerPlaceholder')} /></Form.Item>
          <Form.Item name="category" label={t('models.category')}>
            <Select options={CATEGORY_OPTIONS} />
          </Form.Item>
          <Form.Item name="rated_power_kw" label={t('models.ratedPower_kW')}><InputNumber min={0} step={0.1} style={{ width: '100%' }} /></Form.Item>
          <Form.Item name="description" label={t('models.description')}><Input.TextArea rows={2} /></Form.Item>
        </Form>
      </Modal>

      <Modal title={editingField ? t('models.editField') : t('models.addFieldTitle')} open={fieldModalOpen}
        onOk={handleFieldSubmit}
        onCancel={() => setFieldModalOpen(false)} confirmLoading={createFieldMut.isPending || updateFieldMut.isPending} width={640}>
        <Form form={fieldForm} layout="vertical">
          <Form.Item name="field_key" label={t('models.fieldId')} rules={[{ required: true, message: t('models.pleaseInputFieldKey') }]}
            help={t('models.fieldKeyHelp')}>
            <Input placeholder={t('models.fieldKeyPlaceholder')} disabled={!!editingField} />
          </Form.Item>
          <Form.Item name="field_name" label={t('models.displayName')} rules={[{ required: true, message: t('models.pleaseInputFieldName') }]}>
            <Input placeholder={t('models.fieldNamePlaceholder')} />
          </Form.Item>
          <Space size="large" style={{ display: 'flex' }}>
            <Form.Item name="field_type" label={t('models.dataType')} rules={[{ required: true }]} style={{ flex: 1 }}>
              <Select options={FIELD_TYPE_OPTIONS} />
            </Form.Item>
            <Form.Item name="unit" label={t('models.unit')} style={{ flex: 1 }}>
              <Input placeholder={t('models.unitPlaceholder')} />
            </Form.Item>
            <Form.Item name="sort" label={t('models.sort')} style={{ flex: 1 }}>
              <InputNumber min={0} style={{ width: '100%' }} />
            </Form.Item>
          </Space>
          <Form.Item name="group_name" label={t('models.group')}
            help={t('models.groupHelp')}>
            <Select
              showSearch
              allowClear
              placeholder={t('models.selectOrInputGroup')}
              options={GROUP_CONFIG_KEYS.map(key => ({ label: `${GROUP_ICON_MAP[key] || ''} ${t(key)}`, value: key }))}
              dropdownRender={(menu) => menu}
            />
          </Form.Item>
          <Space size="large" style={{ display: 'flex' }}>
            <Form.Item name="is_show" label={t('models.frontendDisplay')} valuePropName="checked">
              <Switch checkedChildren={t('common.show')} unCheckedChildren={t('common.hide')} />
            </Form.Item>
            <Form.Item name="is_control" label={t('models.controlCommand')} valuePropName="checked"
              help={t('models.controlHelp')}>
              <Switch checkedChildren={t('common.yes')} unCheckedChildren={t('common.no')} onChange={(v) => setIsControl(v)} />
            </Form.Item>
          </Space>
          <Form.Item name="parse_rule" label={t('models.parseRule')} help={t('models.parseRuleHelp')}>
            <Input placeholder={t('models.parseRulePlaceholder')} />
          </Form.Item>

          {isControl && (
            <>
              <Divider orientation="left" plain>{t('models.controlParams')}</Divider>
              <Form.Item name={['control_params', 'label']} label={t('models.buttonLabel')}>
                <Input placeholder={t('models.buttonLabelPlaceholder')} />
              </Form.Item>
              <Form.Item name={['control_params', 'confirm']} label={t('models.needConfirm')} valuePropName="checked">
                <Switch checkedChildren={t('common.yes')} unCheckedChildren={t('common.no')} />
              </Form.Item>
              <Form.Item name={['control_params', 'confirm_message']} label={t('models.confirmPrompt')}>
                <Input placeholder={t('models.confirmPromptPlaceholder')} />
              </Form.Item>
              <Form.Item name={['control_params', 'input_type']} label={t('models.inputMethod')}>
                <Select allowClear placeholder={t('models.noExtraInput')}
                  options={INPUT_TYPE_OPTIONS} />
              </Form.Item>
              <Form.Item noStyle shouldUpdate={(prev, cur) => prev.control_params?.input_type !== cur.control_params?.input_type}>
                {({ getFieldValue }) => {
                  const inputType = getFieldValue(['control_params', 'input_type'])
                  if (inputType === 'number') {
                    return (
                      <Space size="large" style={{ display: 'flex' }}>
                        <Form.Item name={['control_params', 'min']} label={t('models.minValue')} style={{ flex: 1 }}><InputNumber style={{ width: '100%' }} /></Form.Item>
                        <Form.Item name={['control_params', 'max']} label={t('models.maxValue')} style={{ flex: 1 }}><InputNumber style={{ width: '100%' }} /></Form.Item>
                        <Form.Item name={['control_params', 'step']} label={t('models.step')} style={{ flex: 1 }}><InputNumber min={1} style={{ width: '100%' }} /></Form.Item>
                        <Form.Item name={['control_params', 'unit']} label={t('models.unit')} style={{ flex: 1 }}><Input placeholder="W" /></Form.Item>
                      </Space>
                    )
                  }
                  return null
                }}
              </Form.Item>
            </>
          )}
        </Form>
      </Modal>

      <Modal title={editingProtocol ? t('models.editProtocol') : t('models.addProtocolTitle')} open={protocolModalOpen}
        onOk={handleProtocolSubmit}
        onCancel={() => setProtocolModalOpen(false)} confirmLoading={createProtocolMut.isPending || updateProtocolMut.isPending} width={560}>
        <Form form={protocolForm} layout="vertical">
          <Form.Item name="topic_pattern" label={t('models.topicPattern')} rules={[{ required: true, message: t('models.pleaseInputTopicPattern') }]}
            help={t('models.topicPatternHelp')}>
            <Input placeholder={t('models.topicPatternPlaceholder')} />
          </Form.Item>
          <Form.Item name="parse_type" label={t('models.parseType')} rules={[{ required: true }]}>
            <Select options={PARSE_TYPE_OPTIONS} />
          </Form.Item>
          <Form.Item name="parse_config" label={t('models.parseConfig')}
            help={t('models.parseConfigHelp')}>
            <Input.TextArea rows={4} placeholder='{"field_mapping": {"raw_key": "standard_key"}}' />
          </Form.Item>
          <Form.Item name="is_active" label={t('common.enabled')} valuePropName="checked">
            <Switch checkedChildren={t('common.enabled')} unCheckedChildren={t('common.disabled')} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  )
}

export default ModelRegistryWorkspace
