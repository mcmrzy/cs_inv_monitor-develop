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
    queryFn: async () => {
      try { return unwrap<Record<string, unknown>>(await modelApi.getProtocolSchema(selectedModel!.id)) }
      catch { return null }
    },
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
    onSuccess: () => { messageApi.success('型号已保存'); setModelModalOpen(false); refreshModel() },
    onError: () => messageApi.error('型号保存失败'),
  })
  const retireModel = useMutation({
    mutationFn: (id: number) => modelApi.deleteModel(id),
    onSuccess: () => { messageApi.success('型号已停用'); refreshModel() },
    onError: () => messageApi.error('型号停用失败'),
  })
  const saveCatalog = useMutation({
    mutationFn: (values: Partial<FieldCatalogItem>) => modelApi.saveFieldCatalog(values),
    onSuccess: () => {
      messageApi.success('标准字段已保存'); setFieldModalOpen(false)
      queryClient.invalidateQueries({ queryKey: ['field-catalog'] }); refreshModel()
    },
    onError: () => messageApi.error('标准字段保存失败'),
  })
  const patchCapability = useMutation({
    mutationFn: (field: Partial<ModelFieldCapability>) =>
      modelApi.batchUpdateFieldCapabilities(selectedModel!.id, [field]),
    onSuccess: refreshModel,
    onError: () => messageApi.error('字段能力更新失败'),
  })
  const saveCommand = useMutation({
    mutationFn: (values: Record<string, unknown>) => modelApi.saveCommandCapability(selectedModel!.id, {
      ...values,
      parameter_schema: JSON.parse(String(values.parameter_schema || '{"args":[]}')),
    }),
    onSuccess: () => { messageApi.success('控制能力已保存'); setCommandModalOpen(false); refreshModel() },
    onError: () => messageApi.error('控制能力保存失败，请检查参数 Schema'),
  })
  const bindProtocol = useMutation({
    mutationFn: (protocolId: number) => modelApi.bindProtocolVersion(selectedModel!.id, protocolId),
    onSuccess: () => { messageApi.success('协议版本已绑定'); refreshModel() },
    onError: () => messageApi.error('只能绑定已发布的协议版本'),
  })
  const saveProtocol = useMutation({
    mutationFn: (values: Record<string, unknown>) => modelApi.createProtocolVersion({
      protocol_code: String(values.protocol_code), version: Number(values.version),
      schema_hash: String(values.schema_hash),
      fields: JSON.parse(String(values.fields)) as ProtocolFieldInput[],
    }),
    onSuccess: () => {
      messageApi.success('协议草稿已创建'); setProtocolModalOpen(false)
      queryClient.invalidateQueries({ queryKey: ['protocol-versions'] })
    },
    onError: () => messageApi.error('协议草稿创建失败，请检查字段映射 JSON'),
  })
  const releaseProtocol = useMutation({
    mutationFn: (id: number) => modelApi.releaseProtocolVersion(id),
    onSuccess: () => { messageApi.success('协议版本已发布并锁定'); queryClient.invalidateQueries({ queryKey: ['protocol-versions'] }) },
    onError: () => messageApi.error('协议发布失败'),
  })
  const validateModel = useMutation({
    mutationFn: () => modelApi.validateRegistry(selectedModel!.id),
    onSuccess: (response) => {
      const result = unwrap<{ valid: boolean; issues: string[] }>(response)
      result.valid ? messageApi.success('型号配置校验通过') : Modal.warning({ title: '型号配置未通过', content: result.issues.join('；') })
    },
  })
  const activateModel = useMutation({
    mutationFn: () => modelApi.activateRegistry(selectedModel!.id),
    onSuccess: () => { messageApi.success('型号已启用'); refreshModel() },
    onError: () => messageApi.error('启用失败，请先完成字段、命令和协议配置'),
  })

  const releasedVersions = useMemo(
    () => (versionsQuery.data || []).filter((item) => item.status === 'released'),
    [versionsQuery.data],
  )

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
    { title: '型号编码', dataIndex: 'model_code', width: 170 },
    { title: '型号名称', dataIndex: 'model_name' },
    { title: '厂商', dataIndex: 'manufacturer' },
    { title: '品类', dataIndex: 'category', width: 110 },
    { title: '额定功率', dataIndex: 'rated_power_kw', width: 110, render: (value: number) => `${value || 0} kW` },
    { title: '状态', width: 90, render: (_: unknown, row: DeviceModelItem) => <Tag color={row.is_active ? 'green' : 'default'}>{row.is_active ? '启用' : '停用'}</Tag> },
    { title: '设备数', dataIndex: 'device_count', width: 80 },
    { title: '操作', width: 210, render: (_: unknown, row: DeviceModelItem) => <Space>
      <Button type="link" icon={<SettingOutlined />} onClick={() => setSelectedModel(row)}>治理</Button>
      {canEdit && <Button type="link" icon={<EditOutlined />} onClick={() => openModelModal(row)}>编辑</Button>}
      {canEdit && row.is_active && <Popconfirm title="确认停用该型号？" onConfirm={() => retireModel.mutate(row.id)}><Button type="link" danger>停用</Button></Popconfirm>}
    </Space> },
  ]

  const catalogColumns = [
    { title: '字段键', dataIndex: 'field_key', width: 210 },
    { title: '数据类型', dataIndex: 'field_type', width: 110 },
    { title: '分类', dataIndex: 'category', width: 130 },
    { title: '标准单位', dataIndex: 'base_unit', width: 100, render: (value?: string) => value || '-' },
    { title: '时序', dataIndex: 'is_timeseries', width: 80, render: (value: boolean) => value ? '是' : '否' },
    { title: '聚合方式', dataIndex: 'allowed_aggregates', render: (values: string[]) => (values || []).map((v) => <Tag key={v}>{v}</Tag>) },
    { title: '状态', dataIndex: 'status', width: 90, render: (value: string) => <Tag color={statusColor[value]}>{value}</Tag> },
    { title: '操作', width: 90, render: (_: unknown, row: FieldCatalogItem) => canEditDictionary && <Button type="link" icon={<EditOutlined />} onClick={() => openFieldModal(row)}>编辑</Button> },
  ]

  const protocolColumns = [
    { title: '协议编码', dataIndex: 'protocol_code' },
    { title: '版本', dataIndex: 'version', width: 90, render: (value: number) => `v${value}` },
    { title: 'Schema Hash', dataIndex: 'schema_hash' },
    { title: '字段数', dataIndex: 'field_count', width: 90 },
    { title: '状态', dataIndex: 'status', width: 100, render: (value: string) => <Tag color={statusColor[value]}>{value}</Tag> },
    { title: '发布时间', dataIndex: 'released_at', width: 190, render: (value?: string) => value ? new Date(value).toLocaleString() : '-' },
    { title: '操作', width: 100, render: (_: unknown, row: ProtocolVersionItem) => canPublishProtocol && row.status === 'draft'
      ? <Popconfirm title="发布后字段下标不可修改，确认发布？" onConfirm={() => releaseProtocol.mutate(row.id)}><Button type="link">发布</Button></Popconfirm> : null },
  ]

  const capabilityColumns = [
    { title: '字段', dataIndex: 'field_key', width: 210 },
    { title: '分类', dataIndex: 'category', width: 120 },
    { title: '类型/单位', width: 130, render: (_: unknown, row: ModelFieldCapability) => `${row.field_type}${row.base_unit ? ` / ${row.base_unit}` : ''}` },
    ...([
      ['is_supported', '支持'], ['is_visible', '展示'], ['show_realtime', '实时'],
      ['show_history', '历史'], ['allow_compare', '对比'], ['allow_alarm_rule', '告警'], ['default_chart', '默认图表'],
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
    { title: '命令编码', dataIndex: 'command_code', width: 190 },
    { title: '名称键', dataIndex: 'display_name_key' },
    { title: '超时', dataIndex: 'timeout_seconds', width: 90, render: (value: number) => `${value}s` },
    { title: '风险', dataIndex: 'risk_level', width: 80, render: (value: number) => <Tag color={value >= 3 ? 'red' : value === 2 ? 'orange' : 'blue'}>L{value}</Tag> },
    { title: '需在线', dataIndex: 'requires_online', width: 90, render: (value: boolean) => value ? '是' : '否' },
    { title: '启用', dataIndex: 'is_enabled', width: 80, render: (value: boolean) => value ? '是' : '否' },
    { title: '操作', width: 90, render: (_: unknown, row: ModelCommandCapability) => canEdit && <Button type="link" icon={<EditOutlined />} onClick={() => openCommandModal(row)}>编辑</Button> },
  ]

  const migration = migrationQuery.data || {}
  const drawerTabs = [
    { key: 'basic', label: '基础信息', children: <>
      <Descriptions bordered size="small" column={2}>
        <Descriptions.Item label="型号编码">{selectedModel?.model_code}</Descriptions.Item>
        <Descriptions.Item label="型号名称">{selectedModel?.model_name}</Descriptions.Item>
        <Descriptions.Item label="厂商">{selectedModel?.manufacturer || '-'}</Descriptions.Item>
        <Descriptions.Item label="额定功率">{selectedModel?.rated_power_kw || 0} kW</Descriptions.Item>
        <Descriptions.Item label="状态"><Tag color={selectedModel?.is_active ? 'green' : 'default'}>{selectedModel?.is_active ? '启用' : '停用'}</Tag></Descriptions.Item>
        <Descriptions.Item label="设备数">{selectedModel?.device_count || 0}</Descriptions.Item>
      </Descriptions>
      {canEdit && <Space style={{ marginTop: 16 }}>
        <Button icon={<SafetyCertificateOutlined />} onClick={() => validateModel.mutate()}>校验配置</Button>
        <Button type="primary" icon={<CheckCircleOutlined />} onClick={() => activateModel.mutate()}>启用型号</Button>
      </Space>}
    </> },
    { key: 'fields', label: `支持字段 (${capabilitiesQuery.data?.filter((f) => f.is_supported).length || 0})`, children:
      <Table rowKey="field_key" size="small" pagination={{ pageSize: 20 }} loading={capabilitiesQuery.isLoading} dataSource={capabilitiesQuery.data || []} columns={capabilityColumns} scroll={{ x: 1150 }} /> },
    { key: 'commands', label: `控制能力 (${commandsQuery.data?.length || 0})`, children: <>
      {canEdit && <Button icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => openCommandModal()}>新增命令</Button>}
      <Table rowKey="command_code" size="small" pagination={false} dataSource={commandsQuery.data || []} columns={commandColumns} />
    </> },
    { key: 'protocol', label: '协议映射', children: <>
      <Space style={{ marginBottom: 16 }}>
        <Select style={{ width: 330 }} placeholder="选择已发布 heartbeat 协议" value={selectedModel?.heartbeat_protocol_id}
          disabled={!canEdit} options={releasedVersions.map((v) => ({ value: v.id, label: `${v.protocol_code} v${v.version} (${v.field_count} fields)` }))}
          onChange={(value) => bindProtocol.mutate(value)} />
      </Space>
      {schemaQuery.data ? <>
        <Descriptions bordered size="small" column={3}>
          <Descriptions.Item label="协议">{String(schemaQuery.data.protocol_code)}</Descriptions.Item>
          <Descriptions.Item label="版本">v{String(schemaQuery.data.version)}</Descriptions.Item>
          <Descriptions.Item label="状态"><Tag color="green">{String(schemaQuery.data.status)}</Tag></Descriptions.Item>
        </Descriptions>
        <Table rowKey={(row) => `${row.group_code}-${row.field_index}`} size="small" pagination={false}
          dataSource={(schemaQuery.data.fields as Record<string, unknown>[]) || []}
          columns={[
            { title: '数组组', dataIndex: 'group_code' }, { title: '下标', dataIndex: 'field_index', width: 80 },
            { title: '标准字段', dataIndex: 'field_key' }, { title: '线型', dataIndex: 'wire_type' },
            { title: '比例', dataIndex: 'scale', width: 90 },
          ]} style={{ marginTop: 16 }} />
      </> : <Alert type="warning" showIcon message="尚未绑定已发布的 heartbeat 协议版本" />}
    </> },
    { key: 'migration', label: '迁移与预览', children: <>
      <Alert type={migration.migration_status === 'needs_review' ? 'warning' : 'info'} showIcon
        message={`旧数据迁移状态：${String(migration.migration_status || 'pending')}`}
        description={migration.migration_status === 'needs_review' ? '旧 field_mapping 已原样保留，需由研发核对后新建并发布数组协议版本。' : undefined} />
      <Descriptions bordered size="small" column={4} style={{ marginTop: 16 }}>
        <Descriptions.Item label="旧结构字段">{String(migration.legacy_field_count ?? 0)}</Descriptions.Item>
        <Descriptions.Item label="旧 JSON 字段">{String(migration.legacy_json_field_count ?? 0)}</Descriptions.Item>
        <Descriptions.Item label="已迁移字段">{String(migration.migrated_field_count ?? 0)}</Descriptions.Item>
        <Descriptions.Item label="待核对映射">{String(migration.legacy_mapping_count ?? 0)}</Descriptions.Item>
      </Descriptions>
      <Title level={5} style={{ marginTop: 20 }}>最近一帧标准化数据</Title>
      <pre style={{ maxHeight: 360, overflow: 'auto', padding: 12, background: '#f5f5f5', borderRadius: 4 }}>
        {previewQuery.isError ? '暂无该型号设备的遥测数据' : JSON.stringify(previewQuery.data || {}, null, 2)}
      </pre>
    </> },
  ]

  return <div>
    {contextHolder}
    <Space align="center" style={{ width: '100%', justifyContent: 'space-between', marginBottom: 16 }}>
      <div><Title level={3} style={{ margin: 0, letterSpacing: 0 }}>型号与协议治理</Title><Text type="secondary">统一维护型号能力、标准字段和已发布协议版本</Text></div>
    </Space>
    <Tabs items={[
      { key: 'models', label: <span><SettingOutlined /> 型号注册</span>, children: <>
        {hasPermission('models:create') && <Button type="primary" icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => openModelModal()}>新增型号</Button>}
        <Table rowKey="id" loading={modelsQuery.isLoading} dataSource={modelsQuery.data || []} columns={modelColumns} pagination={{ pageSize: 15 }} />
      </> },
      { key: 'catalog', label: <span><EyeOutlined /> 标准字段字典</span>, children: <>
        {canEditDictionary && <Button type="primary" icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => openFieldModal()}>新增标准字段</Button>}
        <Table rowKey="field_key" loading={catalogQuery.isLoading} dataSource={catalogQuery.data || []} columns={catalogColumns} pagination={{ pageSize: 20 }} />
      </> },
      { key: 'protocols', label: <span><ApiOutlined /> 协议版本</span>, children: <>
        {canPublishProtocol && <Button type="primary" icon={<PlusOutlined />} style={{ marginBottom: 12 }} onClick={() => {
          protocolForm.setFieldsValue({ protocol_code: 'heartbeat', version: 1, fields: '[\n  {"group_code":"ac","field_index":0,"field_key":"ac_voltage","wire_type":"number","scale":1}\n]' })
          setProtocolModalOpen(true)
        }}>新建协议草稿</Button>}
        <Table rowKey="id" loading={versionsQuery.isLoading} dataSource={versionsQuery.data || []} columns={protocolColumns} pagination={false} />
      </> },
    ]} />

    <Drawer width={1040} open={!!selectedModel && !modelModalOpen} onClose={() => setSelectedModel(null)}
      title={selectedModel ? `${selectedModel.model_code} · ${selectedModel.model_name}` : ''} destroyOnClose>
      <Tabs items={drawerTabs} />
    </Drawer>

    <Modal title={selectedModel ? '编辑型号' : '新增型号'} open={modelModalOpen} onCancel={() => { setModelModalOpen(false); setSelectedModel(null) }}
      onOk={() => modelForm.submit()} confirmLoading={saveModel.isPending} destroyOnClose>
      <Form form={modelForm} layout="vertical" onFinish={(values) => saveModel.mutate(values)}>
        <Form.Item name="model_code" label="型号编码" rules={[{ required: true }]}><Input disabled={!!selectedModel} /></Form.Item>
        <Form.Item name="model_name" label="型号名称" rules={[{ required: true }]}><Input /></Form.Item>
        <Form.Item name="manufacturer" label="厂商"><Input /></Form.Item>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="category" label="品类" rules={[{ required: true }]}><Select style={{ width: 180 }} options={[{ value: 'inverter', label: '离网逆变器' }]} /></Form.Item>
          <Form.Item name="rated_power_kw" label="额定功率 (kW)"><InputNumber min={0} precision={2} /></Form.Item>
        </Space>
        <Form.Item name="description" label="备注"><Input.TextArea rows={3} /></Form.Item>
      </Form>
    </Modal>

    <Modal title={editingField ? '编辑标准字段' : '新增标准字段'} open={fieldModalOpen} onCancel={() => setFieldModalOpen(false)}
      onOk={() => fieldForm.submit()} confirmLoading={saveCatalog.isPending} destroyOnClose>
      <Form form={fieldForm} layout="vertical" onFinish={(values) => saveCatalog.mutate(values)}>
        <Form.Item name="field_key" label="字段键" rules={[{ required: true, pattern: /^[a-z][a-z0-9_]*$/ }]}><Input disabled={!!editingField} /></Form.Item>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="field_type" label="数据类型" rules={[{ required: true }]}><Select style={{ width: 150 }} options={['float', 'integer', 'boolean', 'string', 'bitmask'].map((value) => ({ value }))} /></Form.Item>
          <Form.Item name="category" label="分类" rules={[{ required: true }]}><Input /></Form.Item>
          <Form.Item name="base_unit" label="标准单位"><Input style={{ width: 110 }} /></Form.Item>
        </Space>
        <Form.Item name="description" label="字段说明"><Input /></Form.Item>
        <Form.Item name="allowed_aggregates" label="允许聚合"><Select mode="multiple" options={['avg', 'min', 'max', 'sum', 'last'].map((value) => ({ value }))} /></Form.Item>
        <Space size="large">
          <Form.Item name="is_timeseries" label="时序字段" valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="is_aggregatable" label="允许聚合" valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="status" label="状态"><Select style={{ width: 120 }} options={[{ value: 'active' }, { value: 'deprecated' }]} /></Form.Item>
        </Space>
      </Form>
    </Modal>

    <Modal title={editingCommand ? '编辑控制能力' : '新增控制能力'} open={commandModalOpen} onCancel={() => setCommandModalOpen(false)}
      onOk={() => commandForm.submit()} confirmLoading={saveCommand.isPending} width={680} destroyOnClose>
      <Form form={commandForm} layout="vertical" onFinish={(values) => saveCommand.mutate(values)}>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="command_code" label="命令编码" rules={[{ required: true }]}><Input disabled={!!editingCommand} /></Form.Item>
          <Form.Item name="display_name_key" label="显示名称键" rules={[{ required: true }]}><Input /></Form.Item>
        </Space>
        <Form.Item name="parameter_schema" label="有序参数 Schema" rules={[{ required: true }]}><Input.TextArea rows={8} style={{ fontFamily: 'monospace' }} /></Form.Item>
        <Space size="large">
          <Form.Item name="timeout_seconds" label="超时秒数"><InputNumber min={1} max={3600} /></Form.Item>
          <Form.Item name="risk_level" label="风险等级"><InputNumber min={1} max={3} /></Form.Item>
          <Form.Item name="requires_online" label="要求在线" valuePropName="checked"><Switch /></Form.Item>
          <Form.Item name="is_enabled" label="启用" valuePropName="checked"><Switch /></Form.Item>
        </Space>
      </Form>
    </Modal>

    <Modal title="新建 heartbeat 协议草稿" open={protocolModalOpen} onCancel={() => setProtocolModalOpen(false)}
      onOk={() => protocolForm.submit()} confirmLoading={saveProtocol.isPending} width={760} destroyOnClose>
      <Form form={protocolForm} layout="vertical" onFinish={(values) => saveProtocol.mutate(values)}>
        <Space size="middle" style={{ display: 'flex' }}>
          <Form.Item name="protocol_code" label="协议编码" rules={[{ required: true }]}><Input /></Form.Item>
          <Form.Item name="version" label="版本号" rules={[{ required: true }]}><InputNumber min={1} /></Form.Item>
          <Form.Item name="schema_hash" label="Schema Hash" rules={[{ required: true }]}><Input /></Form.Item>
        </Space>
        <Form.Item name="fields" label="固定数组字段映射" rules={[{ required: true }]}><Input.TextArea rows={14} style={{ fontFamily: 'monospace' }} /></Form.Item>
      </Form>
    </Modal>
  </div>
}

export default ModelRegistryWorkspace
