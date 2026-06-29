import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Modal, Form, Input, Select, InputNumber, Tag,
  Space, Popconfirm, Typography, App, Empty,
} from 'antd'
import { PlusOutlined, ReloadOutlined, EditOutlined, DeleteOutlined, SafetyOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import { alertRuleApi } from '@/services/alertRuleApi'
import { ALARM_LEVEL_MAP, ALARM_LEVEL_OPTIONS } from '@/utils/constants'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'

const { Title } = Typography

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

const OPERATOR_OPTIONS = [
  { label: '>', value: 'gt' },
  { label: '<', value: 'lt' },
  { label: '=', value: 'eq' },
  { label: '>=', value: 'gte' },
  { label: '<=', value: 'lte' },
  { label: '!=', value: 'neq' },
]

const OPERATOR_LABEL_MAP: Record<string, string> = {
  gt: '>', lt: '<', eq: '=', gte: '>=', lte: '<=', neq: '!=',
}

const AlertRulesPage: React.FC = () => {
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { t } = useTranslation()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [modalOpen, setModalOpen] = useState(false)
  const [editingItem, setEditingItem] = useState<AlertRuleItem | null>(null)
  const [form] = Form.useForm()

  const FIELD_OPTIONS = [
    { label: t('acVoltage'), value: 'ac.voltage' },
    { label: t('acCurrent'), value: 'ac.current' },
    { label: t('acPower'), value: 'ac.power' },
    { label: t('acFrequency'), value: 'ac.frequency' },
    { label: t('acPF'), value: 'ac.pf' },
    { label: t('batterySOC'), value: 'battery.soc' },
    { label: t('batteryVoltage'), value: 'battery.voltage' },
    { label: t('batteryTemp'), value: 'battery.temp' },
    { label: t('inverterTemp'), value: 'sys_status.temp_inv' },
    { label: t('faultCodeField'), value: 'sys_status.fault_code' },
    { label: t('pvVoltage'), value: 'pv.pv_voltage' },
    { label: t('pvPower'), value: 'pv.pv_power' },
    { label: t('dailyPV'), value: 'energy.daily_pv' },
    { label: t('totalActivePower'), value: 'total_active_power' },
    { label: t('internalTemp'), value: 'internal_temperature' },
  ]

  const { data: listRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.alertRules.list({ page, pageSize }),
    queryFn: () => alertRuleApi.getRules({ page, pageSize }).then((r) => {
      const inner = r.data?.data ?? r.data ?? {}
      return {
        items: (Array.isArray(inner) ? inner : (inner?.items ?? inner?.list ?? [])) as AlertRuleItem[],
        total: inner?.total ?? 0,
      }
    }),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.alertRules.all })

  const createMutation = useMutation({
    mutationFn: (values: any) => alertRuleApi.createRule(values),
    onSuccess: () => { message.success(t('rule.createSuccess')); setModalOpen(false); form.resetFields(); invalidate() },
    onError: () => { message.error(t('rule.createFailed')) },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, values }: { id: number; values: any }) => alertRuleApi.updateRule(id, values),
    onSuccess: () => { message.success(t('rule.updateSuccess')); setModalOpen(false); form.resetFields(); invalidate() },
    onError: () => { message.error(t('rule.updateFailed')) },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => alertRuleApi.deleteRule(id),
    onSuccess: () => { message.success(t('rule.disableSuccess')); invalidate() },
    onError: () => { message.error(t('rule.deleteFailed')) },
  })

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
      if (editingItem) {
        updateMutation.mutate({ id: editingItem.id, values })
      } else {
        createMutation.mutate(values)
      }
    } catch { /* validation failed */ }
  }

  const columns: ColumnsType<AlertRuleItem> = [
    { title: t('rule.ruleName'), dataIndex: 'name', key: 'name', width: 150, ellipsis: true },
    {
      title: t('rule.monitorField'), dataIndex: 'field_name', key: 'field_name', width: 160,
      render: (val: string) => FIELD_OPTIONS.find((f) => f.value === val)?.label ?? val,
    },
    { title: t('rule.operator'), dataIndex: 'operator', key: 'operator', width: 70, render: (val: string) => OPERATOR_LABEL_MAP[val] ?? val },
    { title: t('rule.threshold'), dataIndex: 'threshold_value', key: 'threshold_value', width: 100 },
    {
      title: t('rule.alertLevel'), dataIndex: 'alarm_level', key: 'alarm_level', width: 90,
      render: (level: number) => {
        const cfg = ALARM_LEVEL_MAP[level] || { label: String(level), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    { title: t('rule.faultCode'), dataIndex: 'fault_code', key: 'fault_code', width: 100 },
    {
      title: t('rule.applyModel').split('（')[0], dataIndex: 'device_model', key: 'device_model', width: 110,
      render: (val: string | null) => val || <Tag>{t('rule.all')}</Tag>,
    },
    { title: t('rule.silentTime').split('（')[0], dataIndex: 'cooldown_minutes', key: 'cooldown_minutes', width: 80 },
    {
      title: t('rule.enabled'), dataIndex: 'is_active', key: 'is_active', width: 60,
      render: (val: boolean) => (val ? <Tag color="green">{t('common.yes')}</Tag> : <Tag color="red">{t('common.no')}</Tag>),
    },
    {
      title: t('common.operation'), key: 'action', width: 140,
      render: (_: any, record: AlertRuleItem) => (
        <Space>
          <Button type="link" size="small" icon={<EditOutlined />} onClick={() => openEdit(record)}>{t('rule.edit')}</Button>
          <Popconfirm title={t('rule.confirmDisable')} onConfirm={() => deleteMutation.mutate(record.id)}>
            <Button type="link" size="small" danger icon={<DeleteOutlined />}>{t('common.delete')}</Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  const data = listRes?.items ?? []
  const total = listRes?.total ?? 0

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <SafetyOutlined style={{ marginRight: 8 }} />{t('rule.title')}
      </Title>
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Space>
          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>{t('rule.addRule')}</Button>
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Space>
      </Card>

      <Table<AlertRuleItem>
        rowKey="id" columns={columns} dataSource={data} loading={isLoading} size="small"
        locale={{ emptyText: <Empty description={t('common.noData')} /> }}
        pagination={{
          current: page, pageSize, total, showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      <Modal
        title={editingItem ? t('rule.editRule') : t('rule.addRuleTitle')}
        open={modalOpen}
        onCancel={() => { setModalOpen(false); form.resetFields() }}
        onOk={handleSubmit}
        confirmLoading={createMutation.isPending || updateMutation.isPending}
        destroyOnClose width={600}
      >
        <Form form={form} layout="vertical">
          <Form.Item name="name" label={t('rule.ruleName')} rules={[{ required: true, message: t('common.pleaseInput') + t('rule.ruleName') }]}>
            <Input placeholder={t('common.pleaseInput') + t('rule.ruleName')} maxLength={100} />
          </Form.Item>
          <Form.Item name="field_name" label={t('rule.monitorField')} rules={[{ required: true, message: t('common.pleaseSelect') + t('rule.monitorField') }]}>
            <Select placeholder={t('common.pleaseSelect') + t('rule.monitorField')} options={FIELD_OPTIONS} showSearch
              filterOption={(input, option) => (option?.label ?? '').toLowerCase().includes(input.toLowerCase())} />
          </Form.Item>
          <Form.Item name="operator" label={t('rule.operator')} rules={[{ required: true, message: t('common.pleaseSelect') + t('rule.operator') }]}>
            <Select placeholder={t('common.pleaseSelect') + t('rule.operator')} options={OPERATOR_OPTIONS} />
          </Form.Item>
          <Form.Item name="threshold_value" label={t('rule.threshold')} rules={[{ required: true, message: t('common.pleaseInput') + t('rule.threshold') }]}>
            <InputNumber style={{ width: '100%' }} placeholder={t('common.pleaseInput') + t('rule.threshold')} step={0.1} />
          </Form.Item>
          <Form.Item name="alarm_level" label={t('rule.alertLevel')} rules={[{ required: true, message: t('common.pleaseSelect') + t('rule.alertLevel') }]}>
            <Select placeholder={t('common.pleaseSelect') + t('rule.alertLevel')} options={ALARM_LEVEL_OPTIONS} />
          </Form.Item>
          <Form.Item name="fault_code" label={t('rule.faultCode')} rules={[{ required: true, message: t('common.pleaseInput') + t('rule.faultCode') }]}>
            <Input placeholder="E001" maxLength={200} />
          </Form.Item>
          <Form.Item name="fault_message" label={t('rule.faultInfo')} rules={[{ required: true, message: t('common.pleaseInput') + t('rule.faultInfo') }]}>
            <Input.TextArea placeholder={t('common.pleaseInput') + t('rule.faultInfo')} rows={2} />
          </Form.Item>
          <Form.Item name="device_model" label={t('rule.applyModel')}>
            <Input placeholder="SPF-5000-ES" maxLength={50} />
          </Form.Item>
          <Form.Item name="cooldown_minutes" label={t('rule.silentTime')} rules={[{ required: true, message: t('common.pleaseInput') + t('rule.silentTime') }]}>
            <InputNumber min={1} max={1440} style={{ width: '100%' }} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default AlertRulesPage
