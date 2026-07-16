import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Alert, Button, Descriptions, Drawer, Form, Input, InputNumber, message, Modal,
  Popconfirm, Select, Space, Switch, Table, Tabs, Tag, Typography,
} from 'antd'
import {
  ApiOutlined, CheckCircleOutlined, EditOutlined, EyeOutlined, PlusOutlined,
  SafetyCertificateOutlined, SettingOutlined,
} from '@ant-design/icons'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import {
  DeviceModelItem, FieldCatalogItem, ModelCommandCapability, ModelFieldCapability,
  modelApi, ProtocolFieldInput, ProtocolVersionItem,
} from '@/services/modelApi'

const { Text, Title } = Typography

const unwrap = <T,>(response: { data: { data?: T } | T }): T => {
  const body = response.data as { data?: T }
  return body.data === undefined ? response.data as T : body.data
}

const statusColor: Record<string, string> = {
  active: 'green', released: 'green', draft: 'blue', pending: 'default',
  needs_review: 'orange', retired: 'default', deprecated: 'orange', migrated: 'green',
}

const ModelRegistryWorkspace: React.FC = () => {
  const { t, lang } = useTranslation()
  const statusLabel = (value: string) => {
    const key = `models.registry.status.${value}`
    const translated = t(key)
    return translated === key ? value : translated
  }
  const queryClient = useQueryClient()
  const [messageApi, contextHolder] = message.useMessage()
  const hasPermission = useAuthStore((state) => state.hasPermission)
  const canEdit = hasPermission('models:edit')
  const canEditDictionary = hasPermission('models:dictionary')
  const canPublishProtocol = hasPermission('models:protocol_publish')
  const [selectedModel, setSelectedModel] = useState<DeviceModelItem | null>(null)
  const [modelModalOpen, setModelModalOpen] = useState(false)
  const [fieldModalOpen, setFieldModalOpen] = useState(false)
  const [commandModalOpen, setCommandModalOpen] = useState(false)
  const [protocolModalOpen, setProtocolModalOpen] = useState(false)
  const [editingField, setEditingField] = useState<FieldCatalogItem | null>(null)
  const [editingCommand, setEditingCommand] = useState<ModelCommandCapability | null>(null)
  const [modelForm] = Form.useForm()
  const [fieldForm] = Form.useForm()
  const [commandForm] = Form.useForm()
  const [protocolForm] = Form.useForm()

  const modelsQuery = useQuery({
    queryKey: ['model-registry'],
    queryFn: async () => unwrap<DeviceModelItem[]>(await modelApi.listModels()),
  })
  const catalogQuery = useQuery({
    queryKey: ['field-catalog'],
    queryFn: async () => unwrap<FieldCatalogItem[]>(await modelApi.getFieldCatalog()),
  })
  const versionsQuery = useQuery({
    queryKey: ['protocol-versions'],
    queryFn: async () => unwrap<ProtocolVersionItem[]>(await modelApi.listProtocolVersions()),
  })
  const capabilitiesQuery = useQuery({
    queryKey: ['model-field-capabilities', selectedModel?.id],
    enabled: !!selectedModel,
    queryFn: async () => unwrap<ModelFieldCapability[]>(await modelApi.getFieldCapabilities(selectedModel!.id)),
  })
  const commandsQuery = useQuery({
    queryKey: ['model-command-capabilities', selectedModel?.id],
    enabled: !!selectedModel,
    queryFn: async () => unwrap<ModelCommandCapability[]>(await modelApi.getCommandCapabilities(selectedModel!.id)),
  })
  const schemaQuery = useQuery<Record<string, unknown> | null>({
    queryKey: ['model-protocol-schema', selectedModel?.id],
    enabled: !!selectedModel,
    retry: false,
    queryFn: async () => unwrap<Record<string, unknown> | null>(await modelApi.getProtocolSchema(selectedModel!.id)),
  })
  const migrationQuery = useQuery<Record<string, unknown>>({
    queryKey: ['model-migration-report', selectedModel?.id],
    enabled: !!selectedModel,
    queryFn: async () => unwrap<Record<string, unknown>>(await modelApi.getMigrationReport(selectedModel!.id)),
  })
  const previewQuery = useQuery<Record<string, unknown>>({
    queryKey: ['model-data-preview', selectedModel?.id],
    enabled: !!selectedModel,
    retry: false,
    queryFn: async () => unwrap<Record<string, unknown>>(await modelApi.getDataPreview(selectedModel!.id)),
  })

  const refreshModel = () => {
    queryClient.invalidateQueries({ queryKey: ['model-registry'] })
    if (selectedModel) {
      queryClient.invalidateQueries({ queryKey: ['model-field-capabilities', selectedModel.id] })
      queryClient.invalidateQueries({ queryKey: ['model-command-capabilities', selectedModel.id] })
      queryClient.invalidateQueries({ queryKey: ['model-protocol-schema', selectedModel.id] })
    }
  }

  const saveModel = useMutation({
    mutationFn: async (values: Partial<DeviceModelItem>) => selectedModel
      ? modelApi.updateModel(selectedModel.id, values)
      : modelApi.createModel(values),
    onSuccess: () => { messageApi.success(t('models.registry.modelSaved')); setModelModalOpen(false); refreshModel() },
    onError: () => messageApi.error(t('models.registry.modelSaveFailed')),
  })
  const retireModel = useMutation({
    mutationFn: (id: number) => modelApi.deleteModel(id),
    onSuccess: () => { messageApi.success(t('models.registry.modelRetired')); refreshModel() },
    onError: () => messageApi.error(t('models.registry.modelRetireFailed')),
  })
  const saveCatalog = useMutation({
    mutationFn: (values: Partial<FieldCatalogItem>) => modelApi.saveFieldCatalog(values),
    onSuccess: () => {
      messageApi.success(t('models.registry.fieldSaved')); setFieldModalOpen(false)
      queryClient.invalidateQueries({ queryKey: ['field-catalog'] }); refreshModel()
    },
    onError: () => messageApi.error(t('models.registry.fieldSaveFailed')),
  })
  const patchCapability = useMutation({
    mutationFn: (field: Partial<ModelFieldCapability>) =>
      modelApi.batchUpdateFieldCapabilities(selectedModel!.id, [field]),
    onSuccess: refreshModel,
    onError: () => messageApi.error(t('models.registry.capabilityUpdateFailed')),
  })
  const saveCommand = useMutation({
    mutationFn: (values: Record<string, unknown>) => modelApi.saveCommandCapability(selectedModel!.id, {
      ...values,
      parameter_schema: JSON.parse(String(values.parameter_schema || '{"args":[]}')),
    }),
    onSuccess: () => { messageApi.success(t('models.registry.commandSaved')); setCommandModalOpen(false); refreshModel() },
    onError: () => messageApi.error(t('models.registry.commandSaveFailed')),
  })
  const bindProtocol = useMutation({
    mutationFn: (protocolId: number) => modelApi.bindProtocolVersion(selectedModel!.id, protocolId),
    onSuccess: () => { messageApi.success(t('models.registry.protocolBound')); refreshModel() },
    onError: () => messageApi.error(t('models.registry.protocolBindFailed')),
  })
  const saveProtocol = useMutation({
    mutationFn: (values: Record<string, unknown>) => modelApi.createProtocolVersion({
      protocol_code: String(values.protocol_code), version: Number(values.version),
      schema_hash: String(values.schema_hash),
      fields: JSON.parse(String(values.fields)) as ProtocolFieldInput[],
    }),
    onSuccess: () => {
      messageApi.success(t('models.registry.protocolDraftCreated')); setProtocolModalOpen(false)
      queryClient.invalidateQueries({ queryKey: ['protocol-versions'] })
    },
    onError: () => messageApi.error(t('models.registry.protocolDraftFailed')),
  })
  const releaseProtocol = useMutation({
    mutationFn: (id: number) => modelApi.releaseProtocolVersion(id),
    onSuccess: () => { messageApi.success(t('models.registry.protocolReleased')); queryClient.invalidateQueries({ queryKey: ['protocol-versions'] }) },
    onError: () => messageApi.error(t('models.registry.protocolReleaseFailed')),
  })
  const validateModel = useMutation({
    mutationFn: () => modelApi.validateRegistry(selectedModel!.id),
    onSuccess: (response) => {
      const result = unwrap<{ valid: boolean; issues: string[] }>(response)
      result.valid ? messageApi.success(t('models.registry.validationPassed')) : Modal.warning({ title: t('models.registry.validationFailed'), content: result.issues.join(lang === 'zh' ? '；' : '; ') })
    },
  })
  const activateModel = useMutation({
    mutationFn: () => modelApi.activateRegistry(selectedModel!.id),
    onSuccess: () => { messageApi.success(t('models.registry.modelActivated')); refreshModel() },
    onError: () => messageApi.error(t('models.registry.modelActivateFailed')),
  })

  const releasedVersions = useMemo(
    () => (versionsQuery.data || []).filter((item) => item.status === 'released'),
    [versionsQuery.data],
  )

  const failedQuery = [
    modelsQuery, catalogQuery, versionsQuery, capabilitiesQuery,
    commandsQuery, schemaQuery, migrationQuery, previewQuery,
  ].find((query) => query.isError)
  const queryErrorMessage = (() => {
    if (!failedQuery?.error) return ''
    const error = failedQuery.error as {
      message?: string
      response?: { status?: number; data?: { message?: string } }
    }
    const detail = error.response?.data?.message || error.message || t('error.unknown')
    const status = error.response?.status ? `HTTP ${error.response.status}: ` : ''
    return `${status}${detail}`
  })()

  const openModelModal = (model?: DeviceModelItem) => {
    setSelectedModel(model || null)
    modelForm.setFieldsValue(model || { category: 'inverter', is_active: false })
    setModelModalOpen(true)
  }
  const openFieldModal = (field?: FieldCatalogItem) => {
    setEditingField(field || null)
    fieldForm.setFieldsValue(field || {
      field_type: 'float', category: 'system', status: 'active',
      is_timeseries: true, is_aggregatable: true, allowed_aggregates: ['avg', 'min', 'max', 'last'],
    })
    setFieldModalOpen(true)
  }
  const openCommandModal = (command?: ModelCommandCapability) => {
    setEditingCommand(command || null)
    commandForm.setFieldsValue({
      ...command, command_code: command?.command_code, display_name_key: command?.display_name_key,
      parameter_schema: JSON.stringify(command?.parameter_schema || { args: [] }, null, 2),
      timeout_seconds: command?.timeout_seconds || 30, risk_level: command?.risk_level || 1,
      requires_online: command?.requires_online ?? true, is_enabled: command?.is_enabled ?? true,
    })
    setCommandModalOpen(true)
  }

  const modelColumns = [
    { title: t('models.modelCode'), dataIndex: 'model_code', width: 170 },
    { title: t('models.modelName'), dataIndex: 'model_name' },
    { title: t('models.manufacturer'), dataIndex: 'manufacturer' },
    { title: t('models.category'), dataIndex: 'category', width: 110 },
    { title: t('models.ratedPower'), dataIndex: 'rated_power_kw', width: 110, render: (value: number) => `${value || 0} kW` },
    { title: t('common.status'), width: 90, render: (_: unknown, row: DeviceModelItem) => <Tag color={row.is_active ? 'green' : 'default'}>{row.is_active ? t('common.enabled') : t('common.disabled')}</Tag> },
    { title: t('models.deviceCount'), dataIndex: 'device_count', width: 80 },
    { title: t('common.actions'), width: 210, render: (_: unknown, row: DeviceModelItem) => <Space>
      <Button type="link" icon={<SettingOutlined />} onClick={() => setSelectedModel(row)}>{t('models.registry.manage')}</Button>
      {canEdit && <Button type="link" icon={<EditOutlined />} onClick={() => openModelModal(row)}>{t('common.edit')}</Button>}
      {canEdit && row.is_active && <Popconfirm title={t('models.registry.confirmRetire')} onConfirm={() => retireModel.mutate(row.id)}><Button type="link" danger>{t('models.registry.retire')}</Button></Popconfirm>}
    </Space> },
  ]

  const catalogColumns = [
    { title: t('models.registry.fieldKey'), dataIndex: 'field_key', width: 210 },
    { title: t('models.dataType'), dataIndex: 'field_type', width: 110 },
    { title: t('models.registry.classification'), dataIndex: 'category', width: 130 },
    { title: t('models.registry.baseUnit'), dataIndex: 'base_unit', width: 100, render: (value?: string) => value || '-' },
    { title: t('models.registry.timeseries'), dataIndex: 'is_timeseries', width: 80, render: (value: boolean) => value ? t('common.yes') : t('common.no') },
    { title: t('models.registry.aggregates'), dataIndex: 'allowed_aggregates', render: (values: string[]) => (values || []).map((v) => <Tag key={v}>{v}</Tag>) },
    { title: t('common.status'), dataIndex: 'status', width: 90, render: (value: string) => <Tag color={statusColor[value]}>{statusLabel(value)}</Tag> },
    { title: t('common.actions'), width: 90, render: (_: unknown, row: FieldCatalogItem) => canEditDictionary && <Button type="link" icon={<EditOutlined />} onClick={() => openFieldModal(row)}>{t('common.edit')}</Button> },
  ]

  const protocolColumns = [
    { title: t('models.registry.protocolCode'), dataIndex: 'protocol_code' },
    { title: t('models.registry.version'), dataIndex: 'version', width: 90, render: (value: number) => `v${value}` },
    { title: 'Schema Hash', dataIndex: 'schema_hash' },
    { title: t('models.registry.fieldCount'), dataIndex: 'field_count', width: 90 },
    { title: t('common.status'), dataIndex: 'status', width: 100, render: (value: string) => <Tag color={statusColor[value]}>{statusLabel(value)}</Tag> },
    { title: t('models.registry.releasedAt'), dataIndex: 'released_at', width: 190, render: (value?: string) => value ? new Date(value).toLocaleString(lang === 'zh' ? 'zh-CN' : 'en-US') : '-' },
    { title: t('common.actions'), width: 100, render: (_: unknown, row: ProtocolVersionItem) => canPublishProtocol && row.status === 'draft'
      ? <Popconfirm title={t('models.registry.confirmRelease')} onConfirm={() => releaseProtocol.mutate(row.id)}><Button type="link">{t('models.registry.release')}</Button></Popconfirm> : null },
  ]

  const capabilityColumns = [
    { title: t('models.registry.field'), dataIndex: 'field_key', width: 210 },
    { title: t('models.registry.classification'), dataIndex: 'category', width: 120 },
    { title: t('models.registry.typeUnit'), width: 130, render: (_: unknown, row: ModelFieldCapability) => `${row.field_type}${row.base_unit ? ` / ${row.base_unit}` : ''}` },
    ...([
      ['is_supported', t('models.registry.supported')], ['is_visible', t('models.registry.visible')], ['show_realtime', t('models.registry.realtime')],
      ['show_history', t('models.registry.history')], ['allow_compare', t('models.registry.compare')], ['allow_alarm_rule', t('models.registry.alarm')], ['default_chart', t('models.registry.defaultChart')],
    ] as const).map(([key, title]) => ({
      title, width: 78, align: 'center' as const,
      render: (_: unknown, row: ModelFieldCapability) => <Switch size="small" checked={row[key] as boolean}
        disabled={!canEdit || (key !== 'is_supported' && !row.is_supported)}
        onChange={(checked) => patchCapability.mutate({
          field_key: row.field_key, [key]: checked,
          ...(key === 'is_supported' && !checked ? {
            is_visible: false, show_realtime: false, show_history: false,
            allow_compare: false, allow_alarm_rule: false, default_chart: false,
          } : {}),
        })} />,
    })),
  ]

  const commandColumns = [
    { title: t('models.registry.commandCode'), dataIndex: 'command_code', width: 190 },
    { title: t('models.registry.nameKey'), dataIndex: 'display_name_key' },
    { title: t('models.registry.timeout'), dataIndex: 'timeout_seconds', width: 90, render: (value: number) => `${value}s` },
    { title: t('models.registry.risk'), dataIndex: 'risk_level', width: 80, render: (value: number) => <Tag color={value >= 3 ? 'red' : value === 2 ? 'orange' : 'blue'}>L{value}</Tag> },
    { title: t('models.registry.requiresOnline'), dataIndex: 'requires_online', width: 90, render: (value: boolean) => value ? t('common.yes') : t('common.no') },
    { title: t('common.enabled'), dataIndex: 'is_enabled', width: 80, render: (value: boolean) => value ? t('common.yes') : t('common.no') },
    { title: t('common.actions'), width: 90, render: (_: unknown, row: ModelCommandCapability) => canEdit && <Button type="link" icon={<EditOutlined />} onClick={() => openCommandModal(row)}>{t('common.edit')}</Button> },
  ]

  const migration = migrationQuery.data || {}
  const drawerTabs = [
    { key: 'basic', label: t('models.registry.basicInfo'), children: <>
      <Descriptions bordered size="small" column={2}>
        <Descriptions.Item label={t('models.modelCode')}>{selectedModel?.model_code}</Descriptions.Item>
        <Descriptions.Item label={t('models.modelName')}>{selectedModel?.model_name}</Descriptions.Item>
        <Descriptions.Item label={t('models.manufacturer')}>{selectedModel?.manufacturer || '-'}</Descriptions.Item>
        <Descriptions.Item label={t('models.ratedPower')}>{selectedModel?.rated_power_kw || 0} kW</Descriptions.Item>
        <Descriptions.Item label={t('common.status')}><Tag color={selectedModel?.is_active ? 'green' : 'default'}>{selectedModel?.is_active ? t('common.enabled') : t('common.disabled')}</Tag></Descriptions.Item>
        <Descriptions.Item label={t('models.deviceCount')}>{selectedModel?.device_count || 0}</Descriptions.Item>
      </Descriptions>
      {canEdit && <Space style={{ marginTop: 16 }}>
        <Button icon={<SafetyCertificateOutlined />} onClick={() => validateModel.mutate()}>{t('models.registry.validateConfig')}</Button>
        <Button type="primary" icon={<CheckCircleOutlined />} onClick={() => activateModel.mutate()}>{t('models.registry.activateModel')}</Button>
      </Space>}
    </> },
    { key: 'fields', label: t('models.registry.supportedFieldsCount', { count: capabilitiesQuery.data?.filter((f) => f.is_supported).length || 0 }), children:
      <Table rowKey="field_key" size="small" pagination={{ pageSize: 20 }} loading={capabilitiesQuery.isLoading} dataSource={capabilitiesQuery.data || []} columns={capabilityColumns} scroll={{ x: 1150 }} /> },
    { key: 'commands', label: t('models.registry.commandsCount', { count: commandsQuery.data?.length || 0 }), children: <>
      {canEdit && <Button icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => openCommandModal()}>{t('models.registry.addCommand')}</Button>}
      <Table rowKey="command_code" size="small" pagination={false} dataSource={commandsQuery.data || []} columns={commandColumns} />
    </> },
    { key: 'protocol', label: t('models.registry.protocolMapping'), children: <>
      <Space style={{ marginBottom: 16 }}>
        <Select style={{ width: 330 }} placeholder={t('models.registry.selectReleasedProtocol')} value={selectedModel?.heartbeat_protocol_id}
          disabled={!canEdit} options={releasedVersions.map((v) => ({ value: v.id, label: `${v.protocol_code} v${v.version} (${v.field_count} fields)` }))}
          onChange={(value) => bindProtocol.mutate(value)} />
      </Space>
      {schemaQuery.data ? <>
        <Descriptions bordered size="small" column={3}>
          <Descriptions.Item label={t('models.registry.protocol')}>{String(schemaQuery.data.protocol_code)}</Descriptions.Item>
          <Descriptions.Item label={t('models.registry.version')}>v{String(schemaQuery.data.version)}</Descriptions.Item>
          <Descriptions.Item label={t('common.status')}><Tag color="green">{statusLabel(String(schemaQuery.data.status))}</Tag></Descriptions.Item>
        </Descriptions>
        <Table rowKey={(row) => `${row.group_code}-${row.field_index}`} size="small" pagination={false}
          dataSource={(schemaQuery.data.fields as Record<string, unknown>[]) || []}
          columns={[
            { title: t('models.registry.arrayGroup'), dataIndex: 'group_code' }, { title: t('models.registry.index'), dataIndex: 'field_index', width: 80 },
            { title: t('models.registry.standardField'), dataIndex: 'field_key' }, { title: t('models.registry.wireType'), dataIndex: 'wire_type' },
            { title: t('models.registry.scale'), dataIndex: 'scale', width: 90 },
          ]} style={{ marginTop: 16 }} />
      </> : <Alert type="warning" showIcon message={t('models.registry.noReleasedProtocol')} />}
    </> },
    { key: 'migration', label: t('models.registry.migrationPreview'), children: <>
      <Alert type={migration.migration_status === 'needs_review' ? 'warning' : 'info'} showIcon
        message={t('models.registry.migrationStatus', { status: statusLabel(String(migration.migration_status || 'pending')) })}
        description={migration.migration_status === 'needs_review' ? t('models.registry.migrationReviewHint') : undefined} />
      <Descriptions bordered size="small" column={4} style={{ marginTop: 16 }}>
        <Descriptions.Item label={t('models.registry.legacyFields')}>{String(migration.legacy_field_count ?? 0)}</Descriptions.Item>
        <Descriptions.Item label={t('models.registry.legacyJsonFields')}>{String(migration.legacy_json_field_count ?? 0)}</Descriptions.Item>
        <Descriptions.Item label={t('models.registry.migratedFields')}>{String(migration.migrated_field_count ?? 0)}</Descriptions.Item>
        <Descriptions.Item label={t('models.registry.pendingMappings')}>{String(migration.legacy_mapping_count ?? 0)}</Descriptions.Item>
      </Descriptions>
      <Title level={5} style={{ marginTop: 20 }}>{t('models.registry.latestNormalizedData')}</Title>
      <pre style={{ maxHeight: 360, overflow: 'auto', padding: 12, background: '#f5f5f5', borderRadius: 4 }}>
        {previewQuery.isError ? t('models.registry.noTelemetry') : JSON.stringify(previewQuery.data || {}, null, 2)}
      </pre>
    </> },
  ]

  return <div>
    {contextHolder}
    {failedQuery && <Alert
      type="error"
      showIcon
      closable
      style={{ marginBottom: 16 }}
      message={t('models.registry.loadFailed')}
      description={queryErrorMessage}
      action={<Button size="small" onClick={() => queryClient.refetchQueries({ type: 'active' })}>{t('models.registry.reload')}</Button>}
    />}
    <Space align="center" style={{ width: '100%', justifyContent: 'space-between', marginBottom: 16 }}>
      <div><Title level={3} style={{ margin: 0, letterSpacing: 0 }}>{t('models.registry.title')}</Title><Text type="secondary">{t('models.registry.subtitle')}</Text></div>
    </Space>
    <Tabs items={[
      { key: 'models', label: <span><SettingOutlined /> {t('models.registry.modelRegistration')}</span>, children: <>
        {hasPermission('models:create') && <Button type="primary" icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => openModelModal()}>{t('models.addModel')}</Button>}
        <Table rowKey="id" loading={modelsQuery.isLoading} dataSource={modelsQuery.data || []} columns={modelColumns} pagination={{ pageSize: 15 }} />
      </> },
      { key: 'catalog', label: <span><EyeOutlined /> {t('models.registry.fieldDictionary')}</span>, children: <>
        {canEditDictionary && <Button type="primary" icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => openFieldModal()}>{t('models.registry.addStandardField')}</Button>}
        <Table rowKey="field_key" loading={catalogQuery.isLoading} dataSource={catalogQuery.data || []} columns={catalogColumns} pagination={{ pageSize: 20 }} />
      </> },
      { key: 'protocols', label: <span><ApiOutlined /> {t('models.registry.protocolVersions')}</span>, children: <>
        {canPublishProtocol && <Button type="primary" icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => {
          protocolForm.setFieldsValue({ protocol_code: 'heartbeat', version: 1, fields: '[\n  {"group_code":"ac","field_index":0,"field_key":"ac_voltage","wire_type":"number","scale":1}\n]' })
          setProtocolModalOpen(true)
        }}>{t('models.registry.newProtocolDraft')}</Button>}
        <Table rowKey="id" loading={versionsQuery.isLoading} dataSource={versionsQuery.data || []} columns={protocolColumns} pagination={false} />
      </> },
    ]} />

    <Drawer width={1040} open={!!selectedModel && !modelModalOpen} onClose={() => setSelectedModel(null)}
      title={selectedModel ? `${selectedModel.model_code} · ${selectedModel.model_name}` : ''} destroyOnClose>
      <Tabs items={drawerTabs} />
    </Drawer>

    <Modal title={selectedModel ? t('models.editModel') : t('models.addModel')} open={modelModalOpen} onCancel={() => { setModelModalOpen(false); setSelectedModel(null) }}
      onOk={() => modelForm.submit()} confirmLoading={saveModel.isPending} destroyOnClose>
      <Form form={modelForm} layout="vertical" onFinish={(values) => saveModel.mutate(values)}>
        <Form.Item name="model_code" label={t('models.modelCode')} rules={[{ required: true }]}><Input disabled={!!selectedModel} /></Form.Item>
        <Form.Item name="model_name" label={t('models.modelName')} rules={[{ required: true }]}><Input /></Form.Item>
        <Form.Item name="manufacturer" label={t('models.manufacturer')}><Input /></Form.Item>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="category" label={t('models.category')} rules={[{ required: true }]}><Select style={{ width: 180 }} options={[{ value: 'inverter', label: t('models.registry.offGridInverter') }]} /></Form.Item>
          <Form.Item name="rated_power_kw" label={t('models.ratedPower_kW')}><InputNumber min={0} precision={2} /></Form.Item>
        </Space>
        <Form.Item name="description" label={t('models.registry.notes')}><Input.TextArea rows={3} /></Form.Item>
      </Form>
    </Modal>

    <Modal title={editingField ? t('models.registry.editStandardField') : t('models.registry.addStandardField')} open={fieldModalOpen} onCancel={() => setFieldModalOpen(false)}
      onOk={() => fieldForm.submit()} confirmLoading={saveCatalog.isPending} destroyOnClose>
      <Form form={fieldForm} layout="vertical" onFinish={(values) => saveCatalog.mutate(values)}>
        <Form.Item name="field_key" label={t('models.registry.fieldKey')} rules={[{ required: true, pattern: /^[a-z][a-z0-9_]*$/ }]}><Input disabled={!!editingField} /></Form.Item>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="field_type" label={t('models.dataType')} rules={[{ required: true }]}><Select style={{ width: 150 }} options={['float', 'integer', 'boolean', 'string', 'bitmask'].map((value) => ({ value }))} /></Form.Item>
          <Form.Item name="category" label={t('models.registry.classification')} rules={[{ required: true }]}><Input /></Form.Item>
          <Form.Item name="base_unit" label={t('models.registry.baseUnit')}><Input style={{ width: 110 }} /></Form.Item>
        </Space>
        <Form.Item name="description" label={t('models.registry.fieldDescription')}><Input /></Form.Item>
        <Form.Item name="allowed_aggregates" label={t('models.registry.allowedAggregates')}><Select mode="multiple" options={['avg', 'min', 'max', 'sum', 'last'].map((value) => ({ value }))} /></Form.Item>
        <Space size="large">
          <Form.Item name="is_timeseries" label={t('models.registry.timeseriesField')} valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="is_aggregatable" label={t('models.registry.aggregatable')} valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="status" label={t('common.status')}><Select style={{ width: 120 }} options={['active', 'deprecated'].map((value) => ({ value, label: statusLabel(value) }))} /></Form.Item>
        </Space>
      </Form>
    </Modal>

    <Modal title={editingCommand ? t('models.registry.editCommand') : t('models.registry.addCommandCapability')} open={commandModalOpen} onCancel={() => setCommandModalOpen(false)}
      onOk={() => commandForm.submit()} confirmLoading={saveCommand.isPending} width={680} destroyOnClose>
      <Form form={commandForm} layout="vertical" onFinish={(values) => saveCommand.mutate(values)}>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="command_code" label={t('models.registry.commandCode')} rules={[{ required: true }]}><Input disabled={!!editingCommand} /></Form.Item>
          <Form.Item name="display_name_key" label={t('models.registry.displayNameKey')} rules={[{ required: true }]}><Input /></Form.Item>
        </Space>
        <Form.Item name="parameter_schema" label={t('models.registry.parameterSchema')} rules={[{ required: true }]}><Input.TextArea rows={8} style={{ fontFamily: 'monospace' }} /></Form.Item>
        <Space size="large">
          <Form.Item name="timeout_seconds" label={t('models.registry.timeoutSeconds')}><InputNumber min={1} max={3600} /></Form.Item>
          <Form.Item name="risk_level" label={t('models.registry.riskLevel')}><InputNumber min={1} max={3} /></Form.Item>
          <Form.Item name="requires_online" label={t('models.registry.requireOnline')} valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="is_enabled" label={t('common.enabled')} valuePropName="checked"><Switch /></Form.Item>
        </Space>
      </Form>
    </Modal>

    <Modal title={t('models.registry.newHeartbeatDraft')} open={protocolModalOpen} onCancel={() => setProtocolModalOpen(false)}
      onOk={() => protocolForm.submit()} confirmLoading={saveProtocol.isPending} width={760} destroyOnClose>
      <Form form={protocolForm} layout="vertical" onFinish={(values) => saveProtocol.mutate(values)}>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="protocol_code" label={t('models.registry.protocolCode')} rules={[{ required: true }]}><Input /></Form.Item>
          <Form.Item name="version" label={t('models.registry.versionNumber')} rules={[{ required: true }]}><InputNumber min={1} /></Form.Item>
          <Form.Item name="schema_hash" label="Schema Hash" rules={[{ required: true }]}><Input /></Form.Item>
        </Space>
        <Form.Item name="fields" label={t('models.registry.fixedArrayMapping')} rules={[{ required: true }]}><Input.TextArea rows={14} style={{ fontFamily: 'monospace' }} /></Form.Item>
      </Form>
    </Modal>
  </div>
}

export default ModelRegistryWorkspace
