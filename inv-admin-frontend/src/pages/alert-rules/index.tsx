import React, { useState, useEffect, useCallback } from 'react'
import {
  Card,
  Table,
  Button,
  Modal,
  Form,
  Input,
  Select,
  InputNumber,
  Tag,
  Space,
  Switch,
  Popconfirm,
  message,
} from 'antd'
import {
  PlusOutlined,
  ReloadOutlined,
  EditOutlined,
  DeleteOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import { alertRuleApi } from '@/services/alertRuleApi'

interface AlertRuleItem {
  id: number
  name: string
  field_name: string
  operator: string
  threshold_value: number
  alarm_level: number
  fault_code: string
  fault_message: string
  device_model: string | null
  is_active: boolean
  cooldown_minutes: number
  created_at: string
}

const ALARM_LEVEL_OPTIONS = [
  { label: '信息', value: 1 },
  { label: '警告', value: 2 },
  { label: '严重', value: 3 },
]

const ALARM_LEVEL_MAP: Record<number, { label: string; color: string }> = {
  1: { label: '信息', color: '#1677ff' },
  2: { label: '警告', color: '#faad14' },
  3: { label: '严重', color: '#ff4d4f' },
}

const OPERATOR_OPTIONS = [
  { label: '>', value: 'gt' },
  { label: '<', value: 'lt' },
  { label: '=', value: 'eq' },
  { label: '>=', value: 'gte' },
  { label: '<=', value: 'lte' },
  { label: '!=', value: 'neq' },
]

const OPERATOR_LABEL_MAP: Record<string, string> = {
  gt: '>',
  lt: '<',
  eq: '=',
  gte: '>=',
  lte: '<=',
  neq: '!=',
}

const FIELD_OPTIONS = [
  { label: 'AC电压 (ac.voltage)', value: 'ac.voltage' },
  { label: 'AC电流 (ac.current)', value: 'ac.current' },
  { label: 'AC功率 (ac.power)', value: 'ac.power' },
  { label: 'AC频率 (ac.frequency)', value: 'ac.frequency' },
  { label: 'AC功率因数 (ac.pf)', value: 'ac.pf' },
  { label: '电池SOC (battery.soc)', value: 'battery.soc' },
  { label: '电池电压 (battery.voltage)', value: 'battery.voltage' },
  { label: '电池温度 (battery.temp)', value: 'battery.temp' },
  { label: '逆变器温度 (sys_status.temp_inv)', value: 'sys_status.temp_inv' },
  { label: '故障码 (sys_status.fault_code)', value: 'sys_status.fault_code' },
  { label: 'PV电压 (pv.pv_voltage)', value: 'pv.pv_voltage' },
  { label: 'PV功率 (pv.pv_power)', value: 'pv.pv_power' },
  { label: '日发电量 (energy.daily_pv)', value: 'energy.daily_pv' },
  { label: '总有功功率 (total_active_power)', value: 'total_active_power' },
  { label: '内部温度 (internal_temperature)', value: 'internal_temperature' },
]

const AlertRulesPage: React.FC = () => {
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<AlertRuleItem[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [modalOpen, setModalOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<AlertRuleItem | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [form] = Form.useForm()

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await alertRuleApi.getRules({ page, pageSize })
      setData(res.data?.data?.list ?? res.data?.list ?? [])
      setTotal(res.data?.data?.total ?? res.data?.total ?? 0)
    } catch {
      message.error('获取告警规则列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const openCreate = () => {
    setEditingItem(null)
    form.resetFields()
    form.setFieldsValue({ alarm_level: 2, cooldown_minutes: 5, operator: 'gt' })
    setModalOpen(true)
  }

  const openEdit = (record: AlertRuleItem) => {
    setEditingItem(record)
    form.setFieldsValue(record)
    setModalOpen(true)
  }

  const handleSubmit = async () => {
    try {
      const values = await form.validateFields()
      setSubmitting(true)
      if (editingItem) {
        await alertRuleApi.updateRule(editingItem.id, values)
        message.success('规则更新成功')
      } else {
        await alertRuleApi.createRule(values)
        message.success('规则创建成功')
      }
      setModalOpen(false)
      form.resetFields()
      fetchData()
    } catch {
      message.error('操作失败')
    } finally {
      setSubmitting(false)
    }
  }

  const handleDelete = async (id: number) => {
    try {
      await alertRuleApi.deleteRule(id)
      message.success('规则已停用')
      fetchData()
    } catch {
      message.error('删除失败')
    }
  }

  const columns: ColumnsType<AlertRuleItem> = [
    { title: '规则名称', dataIndex: 'name', key: 'name', width: 150, ellipsis: true },
    {
      title: '监控字段',
      dataIndex: 'field_name',
      key: 'field_name',
      width: 160,
      render: (val: string) => {
        const opt = FIELD_OPTIONS.find((f) => f.value === val)
        return opt?.label ?? val
      },
    },
    {
      title: '运算符',
      dataIndex: 'operator',
      key: 'operator',
      width: 70,
      render: (val: string) => OPERATOR_LABEL_MAP[val] ?? val,
    },
    {
      title: '阈值',
      dataIndex: 'threshold_value',
      key: 'threshold_value',
      width: 100,
    },
    {
      title: '告警级别',
      dataIndex: 'alarm_level',
      key: 'alarm_level',
      width: 90,
      render: (level: number) => {
        const cfg = ALARM_LEVEL_MAP[level] || { label: String(level), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '故障码',
      dataIndex: 'fault_code',
      key: 'fault_code',
      width: 100,
    },
    {
      title: '适用机型',
      dataIndex: 'device_model',
      key: 'device_model',
      width: 110,
      render: (val: string | null) => val || <Tag>全部</Tag>,
    },
    {
      title: '静默(分)',
      dataIndex: 'cooldown_minutes',
      key: 'cooldown_minutes',
      width: 80,
    },
    {
      title: '启用',
      dataIndex: 'is_active',
      key: 'is_active',
      width: 60,
      render: (val: boolean) => (val ? <Tag color="green">是</Tag> : <Tag color="red">否</Tag>),
    },
    {
      title: '操作',
      key: 'action',
      width: 140,
      render: (_: any, record: AlertRuleItem) => (
        <Space>
          <Button
            type="link"
            size="small"
            icon={<EditOutlined />}
            onClick={() => openEdit(record)}
          >
            编辑
          </Button>
          <Popconfirm
            title="确定停用该规则？"
            onConfirm={() => handleDelete(record.id)}
          >
            <Button
              type="link"
              size="small"
              danger
              icon={<DeleteOutlined />}
            >
              删除
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Space>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            新增规则
          </Button>
          <Button icon={<ReloadOutlined />} onClick={fetchData}>
            刷新
          </Button>
        </Space>
      </Card>

      <Table<AlertRuleItem>
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
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      <Modal
        title={editingItem ? '编辑告警规则' : '新增告警规则'}
        open={modalOpen}
        onCancel={() => { setModalOpen(false); form.resetFields() }}
        onOk={handleSubmit}
        confirmLoading={submitting}
        destroyOnClose
        width={600}
      >
        <Form form={form} layout="vertical">
          <Form.Item
            name="name"
            label="规则名称"
            rules={[{ required: true, message: '请输入规则名称' }]}
          >
            <Input placeholder="例如：电池过压告警" maxLength={100} />
          </Form.Item>
          <Form.Item
            name="field_name"
            label="监控字段"
            rules={[{ required: true, message: '请选择监控字段' }]}
          >
            <Select
              placeholder="选择遥测字段"
              options={FIELD_OPTIONS}
              showSearch
              filterOption={(input, option) =>
                (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
              }
            />
          </Form.Item>
          <Form.Item
            name="operator"
            label="运算符"
            rules={[{ required: true, message: '请选择运算符' }]}
          >
            <Select placeholder="选择比较运算符" options={OPERATOR_OPTIONS} />
          </Form.Item>
          <Form.Item
            name="threshold_value"
            label="阈值"
            rules={[{ required: true, message: '请输入阈值' }]}
          >
            <InputNumber
              style={{ width: '100%' }}
              placeholder="触发阈值"
              step={0.1}
            />
          </Form.Item>
          <Form.Item
            name="alarm_level"
            label="告警级别"
            rules={[{ required: true, message: '请选择告警级别' }]}
          >
            <Select placeholder="选择告警级别" options={ALARM_LEVEL_OPTIONS} />
          </Form.Item>
          <Form.Item
            name="fault_code"
            label="故障码"
            rules={[{ required: true, message: '请输入故障码' }]}
          >
            <Input placeholder="例如：E001" maxLength={200} />
          </Form.Item>
          <Form.Item
            name="fault_message"
            label="故障信息"
            rules={[{ required: true, message: '请输入故障信息' }]}
          >
            <Input.TextArea placeholder="故障描述信息" rows={2} />
          </Form.Item>
          <Form.Item name="device_model" label="适用机型（留空表示全部）">
            <Input placeholder="例如：SPF-5000-ES" maxLength={50} />
          </Form.Item>
          <Form.Item
            name="cooldown_minutes"
            label="静默时间（分钟）"
            rules={[{ required: true, message: '请输入静默时间' }]}
          >
            <InputNumber min={1} max={1440} style={{ width: '100%' }} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default AlertRulesPage
