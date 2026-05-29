import { useState, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Input, Space, Modal, Form, Select, Switch,
  Tag, Popconfirm, message, Typography, InputNumber, Tooltip, Drawer,
  Empty,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  PlusOutlined, SettingOutlined, DeleteOutlined, EditOutlined,
  ArrowUpOutlined, ArrowDownOutlined, HolderOutlined,
} from '@ant-design/icons'
import { modelApi, DeviceModelItem, DeviceModelFieldItem } from '@/services/modelApi'

const { Text } = Typography

const FIELD_TYPE_LABELS: Record<string, string> = {
  int: '整数',
  float: '浮点数',
  string: '字符串',
  bool: '布尔值',
}

const ModelsPage: React.FC = () => {
  const queryClient = useQueryClient()
  const [messageApi, contextHolder] = message.useMessage()

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

  const { data: modelList = [], isLoading, refetch } = useQuery({
    queryKey: ['models'],
    queryFn: () =>
      modelApi.listModels().then((res) => {
        const d = res.data
        return (Array.isArray(d?.data) ? d.data : (Array.isArray(d) ? d : [])) as DeviceModelItem[]
      }),
  })

  const { data: fieldList = [], refetch: refetchFields } = useQuery({
    queryKey: ['modelFields', currentModelId],
    queryFn: () =>
      modelApi.getFields(currentModelId!).then((res) => {
        const d = res.data
        return (Array.isArray(d?.data) ? d.data : (Array.isArray(d) ? d : [])) as DeviceModelFieldItem[]
      }),
    enabled: currentModelId != null,
  })

  const filteredModels = modelList.filter(
    (m) =>
      !keyword ||
      m.model_code.toLowerCase().includes(keyword.toLowerCase()) ||
      m.model_name.toLowerCase().includes(keyword.toLowerCase())
  )

  const createModelMut = useMutation({
    mutationFn: (data: any) => modelApi.createModel(data),
    onSuccess: () => {
      messageApi.success('型号创建成功')
      setModelModalOpen(false)
      modelForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['models'] })
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || '创建失败'),
  })

  const updateModelMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => modelApi.updateModel(id, data),
    onSuccess: () => {
      messageApi.success('型号更新成功')
      setModelModalOpen(false)
      modelForm.resetFields()
      queryClient.invalidateQueries({ queryKey: ['models'] })
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || '更新失败'),
  })

  const deleteModelMut = useMutation({
    mutationFn: (id: number) => modelApi.deleteModel(id),
    onSuccess: () => {
      messageApi.success('型号已删除')
      queryClient.invalidateQueries({ queryKey: ['models'] })
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || '删除失败'),
  })

  const createFieldMut = useMutation({
    mutationFn: ({ modelId, data }: { modelId: number; data: any }) =>
      modelApi.createField(modelId, data),
    onSuccess: () => {
      messageApi.success('字段添加成功')
      setFieldModalOpen(false)
      fieldForm.resetFields()
      refetchFields()
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || '添加失败'),
  })

  const updateFieldMut = useMutation({
    mutationFn: ({ modelId, fieldId, data }: { modelId: number; fieldId: number; data: any }) =>
      modelApi.updateField(modelId, fieldId, data),
    onSuccess: () => {
      messageApi.success('字段更新成功')
      setFieldModalOpen(false)
      fieldForm.resetFields()
      refetchFields()
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || '更新失败'),
  })

  const deleteFieldMut = useMutation({
    mutationFn: ({ modelId, fieldId }: { modelId: number; fieldId: number }) =>
      modelApi.deleteField(modelId, fieldId),
    onSuccess: () => {
      messageApi.success('字段已删除')
      refetchFields()
    },
    onError: (err: any) => messageApi.error(err?.response?.data?.message || '删除失败'),
  })

  const handleCreateModel = () => {
    setEditingModel(null)
    modelForm.resetFields()
    modelForm.setFieldsValue({ category: 'inverter', rated_power_kw: 0 })
    setModelModalOpen(true)
  }

  const handleEditModel = (record: DeviceModelItem) => {
    setEditingModel(record)
    modelForm.setFieldsValue(record)
    setModelModalOpen(true)
  }

  const handleModelSubmit = () => {
    modelForm.validateFields().then((values) => {
      if (editingModel) {
        updateModelMut.mutate({ id: editingModel.id, data: values })
      } else {
        createModelMut.mutate(values)
      }
    })
  }

  const handleManageFields = (record: DeviceModelItem) => {
    setCurrentModelId(record.id)
    setCurrentModelName(record.model_name)
    setFieldsDrawerOpen(true)
  }

  const handleCreateField = () => {
    setEditingField(null)
    fieldForm.resetFields()
    fieldForm.setFieldsValue({ field_type: 'float', sort: 0, is_show: true, is_control: false })
    setFieldModalOpen(true)
  }

  const handleEditField = (record: DeviceModelFieldItem) => {
    setEditingField(record)
    fieldForm.setFieldsValue(record)
    setFieldModalOpen(true)
  }

  const handleFieldSubmit = () => {
    fieldForm.validateFields().then((values) => {
      if (editingField) {
        updateFieldMut.mutate({
          modelId: currentModelId!,
          fieldId: editingField.id,
          data: values,
        })
      } else {
        createFieldMut.mutate({ modelId: currentModelId!, data: values })
      }
    })
  }

  const handleDeleteField = (fieldId: number) => {
    deleteFieldMut.mutate({ modelId: currentModelId!, fieldId })
  }

  const handleMoveField = (fieldId: number, direction: 'up' | 'down') => {
    const idx = fieldList.findIndex((f) => f.id === fieldId)
    if (idx < 0) return
    const swapIdx = direction === 'up' ? idx - 1 : idx + 1
    if (swapIdx < 0 || swapIdx >= fieldList.length) return

    const updated = [...fieldList]
    const currentSort = updated[idx].sort
    updated[idx] = { ...updated[idx], sort: updated[swapIdx].sort }
    updated[swapIdx] = { ...updated[swapIdx], sort: currentSort }

    modelApi.batchUpdateFields(currentModelId!, updated).then(() => {
      refetchFields()
    })
  }

  const modelColumns: ColumnsType<DeviceModelItem> = [
    { title: 'ID', dataIndex: 'id', key: 'id', width: 60 },
    { title: '型号编码', dataIndex: 'model_code', key: 'model_code', width: 140 },
    { title: '型号名称', dataIndex: 'model_name', key: 'model_name', width: 160 },
    { title: '厂商', dataIndex: 'manufacturer', key: 'manufacturer', width: 120, render: (v: string) => v || '-' },
    { title: '类别', dataIndex: 'category', key: 'category', width: 100, render: (v: string) => <Tag>{v}</Tag> },
    { title: '额定功率(kW)', dataIndex: 'rated_power_kw', key: 'rated_power_kw', width: 120, render: (v: number) => v != null ? `${v} kW` : '-' },
    {
      title: '状态', dataIndex: 'is_active', key: 'is_active', width: 80,
      render: (v: boolean) => <Tag color={v ? 'green' : 'red'}>{v ? '启用' : '禁用'}</Tag>,
    },
    {
      title: '操作', key: 'actions', width: 220, fixed: 'right',
      render: (_, record) => (
        <Space size="small">
          <Button size="small" icon={<SettingOutlined />} onClick={() => handleManageFields(record)}>
            字段配置
          </Button>
          <Button size="small" icon={<EditOutlined />} onClick={() => handleEditModel(record)} />
          <Popconfirm title="确定删除此型号？" onConfirm={() => deleteModelMut.mutate(record.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  const fieldColumns: ColumnsType<DeviceModelFieldItem> = [
    { title: '排序', key: 'sort', width: 100, render: (_, record) => (
      <Space size="small">
        <Button size="small" icon={<ArrowUpOutlined />} onClick={() => handleMoveField(record.id, 'up')} />
        <Button size="small" icon={<ArrowDownOutlined />} onClick={() => handleMoveField(record.id, 'down')} />
        <HolderOutlined style={{ color: '#999' }} />
        <Text type="secondary">{record.sort}</Text>
      </Space>
    )},
    { title: '字段标识', dataIndex: 'field_key', key: 'field_key', width: 160 },
    { title: '字段名称', dataIndex: 'field_name', key: 'field_name', width: 140 },
    {
      title: '类型', dataIndex: 'field_type', key: 'field_type', width: 80,
      render: (v: string) => <Tag>{FIELD_TYPE_LABELS[v] || v}</Tag>,
    },
    { title: '单位', dataIndex: 'unit', key: 'unit', width: 70, render: (v: string) => v || '-' },
    {
      title: '显示', dataIndex: 'is_show', key: 'is_show', width: 60,
      render: (v: boolean) => <Tag color={v ? 'green' : 'default'}>{v ? '是' : '否'}</Tag>,
    },
    {
      title: '控制指令', dataIndex: 'is_control', key: 'is_control', width: 80,
      render: (v: boolean) => <Tag color={v ? 'blue' : 'default'}>{v ? '是' : '否'}</Tag>,
    },
    {
      title: '解析规则', dataIndex: 'parse_rule', key: 'parse_rule', width: 200, ellipsis: true,
      render: (v: string) => v ? <Text code style={{ fontSize: 12 }}>{v}</Text> : '-',
    },
    {
      title: '操作', key: 'actions', width: 120, fixed: 'right',
      render: (_, record) => (
        <Space size="small">
          <Button size="small" icon={<EditOutlined />} onClick={() => handleEditField(record)} />
          <Popconfirm title="确定删除此字段？" onConfirm={() => handleDeleteField(record.id)}>
            <Button size="small" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <>
      {contextHolder}
      <Card
        title="型号管理"
        extra={
          <Space>
            <Input.Search
              placeholder="搜索型号编码/名称"
              allowClear
              style={{ width: 220 }}
              onSearch={setKeyword}
              onChange={(e) => !e.target.value && setKeyword('')}
            />
            <Button type="primary" icon={<PlusOutlined />} onClick={handleCreateModel}>
              新增型号
            </Button>
          </Space>
        }
      >
        <Table
          rowKey="id"
          columns={modelColumns}
          dataSource={filteredModels}
          loading={isLoading}
          pagination={{ pageSize: 20, showSizeChanger: true, showTotal: (t) => `共 ${t} 条` }}
          scroll={{ x: 900 }}
          locale={{ emptyText: <Empty description="暂无型号数据，请点击「新增型号」" /> }}
        />
      </Card>

      <Modal
        title={editingModel ? '编辑型号' : '新增型号'}
        open={modelModalOpen}
        onOk={handleModelSubmit}
        onCancel={() => setModelModalOpen(false)}
        confirmLoading={createModelMut.isPending || updateModelMut.isPending}
        width={560}
      >
        <Form form={modelForm} layout="vertical">
          <Form.Item name="model_code" label="型号编码" rules={[{ required: true, message: '请输入型号编码' }]}>
            <Input placeholder="如: INV-5K-48V" disabled={!!editingModel} />
          </Form.Item>
          <Form.Item name="model_name" label="型号名称" rules={[{ required: true, message: '请输入型号名称' }]}>
            <Input placeholder="如: 5kW离网逆变器" />
          </Form.Item>
          <Form.Item name="manufacturer" label="厂商">
            <Input placeholder="厂商名称" />
          </Form.Item>
          <Form.Item name="category" label="类别">
            <Select options={[
              { label: '逆变器', value: 'inverter' },
              { label: '储能', value: 'storage' },
              { label: '充电桩', value: 'charger' },
            ]} />
          </Form.Item>
          <Form.Item name="rated_power_kw" label="额定功率(kW)">
            <InputNumber min={0} step={0.1} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item name="description" label="描述">
            <Input.TextArea rows={3} placeholder="型号描述" />
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title={`字段配置 - ${currentModelName}`}
        open={fieldsDrawerOpen}
        onClose={() => setFieldsDrawerOpen(false)}
        width={960}
        extra={
          <Button type="primary" icon={<PlusOutlined />} onClick={handleCreateField}>
            新增字段
          </Button>
        }
      >
        <Table
          rowKey="id"
          columns={fieldColumns}
          dataSource={fieldList}
          pagination={false}
          scroll={{ x: 900 }}
          locale={{ emptyText: <Empty description="暂无字段配置" /> }}
        />
      </Drawer>

      <Modal
        title={editingField ? '编辑字段' : '新增字段'}
        open={fieldModalOpen}
        onOk={handleFieldSubmit}
        onCancel={() => setFieldModalOpen(false)}
        confirmLoading={createFieldMut.isPending || updateFieldMut.isPending}
        width={560}
      >
        <Form form={fieldForm} layout="vertical">
          <Form.Item name="field_key" label="字段标识" rules={[{ required: true, message: '请输入字段标识' }]}>
            <Input placeholder="如: ac.power, battery.soc" disabled={!!editingField} />
          </Form.Item>
          <Form.Item name="field_name" label="字段名称" rules={[{ required: true, message: '请输入字段名称' }]}>
            <Input placeholder="如: 交流功率, 电池SOC" />
          </Form.Item>
          <Form.Item name="field_type" label="字段类型" rules={[{ required: true }]}>
            <Select options={[
              { label: '整数 (int)', value: 'int' },
              { label: '浮点数 (float)', value: 'float' },
              { label: '字符串 (string)', value: 'string' },
              { label: '布尔值 (bool)', value: 'bool' },
            ]} />
          </Form.Item>
          <Form.Item name="unit" label="单位">
            <Input placeholder="如: W, V, %, ℃" />
          </Form.Item>
          <Form.Item name="sort" label="显示排序">
            <InputNumber min={0} style={{ width: '100%' }} />
          </Form.Item>
          <Form.Item name="is_show" label="前端显示" valuePropName="checked">
            <Switch checkedChildren="显示" unCheckedChildren="隐藏" />
          </Form.Item>
          <Form.Item name="is_control" label="控制指令" valuePropName="checked" help="开启后该字段可作为设备控制指令下发">
            <Switch checkedChildren="是" unCheckedChildren="否" />
          </Form.Item>
          <Form.Item name="parse_rule" label="解析规则" help="JSON格式的解析路径，如: $.data.ac.power">
            <Input placeholder="如: $.data.ac.power" />
          </Form.Item>
        </Form>
      </Modal>
    </>
  )
}

export default ModelsPage
