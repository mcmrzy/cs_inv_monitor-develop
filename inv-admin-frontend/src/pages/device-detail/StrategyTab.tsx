import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Form, InputNumber, Switch, Button, Row, Col, Spin, App, Space,
  Table, Modal, Input, Select, Tag, Popconfirm, Empty, Typography,
} from 'antd'
import { PlusOutlined, DeleteOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

interface StrategyTabProps {
  sn: string
}

interface OverrideRecord {
  id: string
  override_type: string
  override_value: number | string
  duration_minutes: number
  reason: string
  created_at: string
  expires_at: string | null
  status: string
}

const StrategyTab: React.FC<StrategyTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [form] = Form.useForm()
  const [overrideModalOpen, setOverrideModalOpen] = useState(false)
  const [overrideForm] = Form.useForm()

  const { isLoading } = useQuery({
    queryKey: queryKeys.devices.energySchedule(sn),
    queryFn: () => deviceApi.getEnergySchedule(sn).then((r) => {
      const d = r.data?.data ?? {}
      form.setFieldsValue({
        soc_min: d.soc_min ?? 20,
        soc_max: d.soc_max ?? 80,
        charge_priority: d.charge_priority ?? 'balanced',
        discharge_priority: d.discharge_priority ?? 'balanced',
        peak_shaving_enabled: d.peak_shaving_enabled ?? false,
      })
      return d
    }),
  })

  const { data: overridesRes, isLoading: overridesLoading } = useQuery({
    queryKey: queryKeys.devices.controlOverrides(sn),
    queryFn: () => deviceApi.getControlOverrides(sn).then((r) => r.data?.data ?? []),
    refetchInterval: 30000,
  })

  const overrides = ((overridesRes as OverrideRecord[]) ?? []).filter((o) => o.status !== 'cancelled' && o.status !== 'expired')

  const saveMutation = useMutation({
    mutationFn: (values: any) => deviceApi.updateEnergySchedule(sn, values),
    onSuccess: () => {
      message.success(t('deviceDetail.strategy.saveSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.energySchedule(sn) })
    },
    onError: () => { message.error(t('deviceDetail.strategy.saveFailed')) },
  })

  const createOverrideMutation = useMutation({
    mutationFn: (values: any) => deviceApi.createControlOverride(sn, values),
    onSuccess: () => {
      message.success(t('deviceDetail.diagnostics.sendSuccess'))
      setOverrideModalOpen(false)
      overrideForm.resetFields()
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlOverrides(sn) })
    },
    onError: () => { message.error(t('deviceDetail.diagnostics.sendFailed')) },
  })

  const deleteOverrideMutation = useMutation({
    mutationFn: (id: string) => deviceApi.deleteControlOverride(sn, id),
    onSuccess: () => {
      message.success(t('deviceDetail.strategy.deleteOverride'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlOverrides(sn) })
    },
    onError: () => { message.error(t('deviceDetail.diagnostics.sendFailed')) },
  })

  const overrideColumns: ColumnsType<OverrideRecord> = [
    { title: t('deviceDetail.strategy.overrideType'), dataIndex: 'override_type', key: 'override_type', width: 140, render: (v: string) => <Tag color="orange">{v}</Tag> },
    { title: t('deviceDetail.strategy.overrideValue'), dataIndex: 'override_value', key: 'override_value', width: 120 },
    { title: t('deviceDetail.strategy.overrideDuration'), dataIndex: 'duration_minutes', key: 'duration_minutes', width: 120, render: (v: number) => `${v} min` },
    { title: t('deviceDetail.strategy.overrideReason'), dataIndex: 'reason', key: 'reason', ellipsis: true },
    {
      title: t('common.createdAt'), dataIndex: 'created_at', key: 'created_at', width: 170,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: t('deviceDetail.strategy.overrideExpires'), dataIndex: 'expires_at', key: 'expires_at', width: 170,
      render: (v: string | null) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: t('common.actions'), key: 'actions', width: 100,
      render: (_: unknown, record: OverrideRecord) => (
        <Popconfirm title={t('deviceDetail.strategy.deleteConfirm')} onConfirm={() => deleteOverrideMutation.mutate(record.id)}>
          <Button size="small" danger icon={<DeleteOutlined />}>{t('deviceDetail.strategy.deleteOverride')}</Button>
        </Popconfirm>
      ),
    },
  ]

  return (
    <Spin spinning={isLoading}>
      <Card
        title={t('deviceDetail.strategy.title')}
        bordered={false}
        style={{ marginBottom: 16, borderRadius: 12 }}
      >
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="soc_min" label={t('deviceDetail.strategy.socMin')} rules={[{ required: true }]}>
                <InputNumber min={0} max={100} style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="soc_max" label={t('deviceDetail.strategy.socMax')} rules={[{ required: true }]}>
                <InputNumber min={0} max={100} style={{ width: '100%' }} />
              </Form.Item>
            </Col>
          </Row>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="charge_priority" label={t('deviceDetail.strategy.chargePriority')}>
                <Select options={[
                  { label: 'Balanced', value: 'balanced' },
                  { label: 'PV Priority', value: 'pv_priority' },
                  { label: 'Grid Priority', value: 'grid_priority' },
                ]} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="discharge_priority" label={t('deviceDetail.strategy.dischargePriority')}>
                <Select options={[
                  { label: 'Balanced', value: 'balanced' },
                  { label: 'Load Priority', value: 'load_priority' },
                  { label: 'Grid Feed-in', value: 'grid_feed_in' },
                ]} />
              </Form.Item>
            </Col>
          </Row>
          <Form.Item name="peak_shaving_enabled" label={t('deviceDetail.strategy.peakShavingEnabled')} valuePropName="checked">
            <Switch />
          </Form.Item>
          <Button type="primary" loading={saveMutation.isPending} onClick={async () => {
            try { saveMutation.mutate(await form.validateFields()) } catch {}
          }}>
            {t('deviceDetail.strategy.save')}
          </Button>
        </Form>
      </Card>

      <Card
        title={
          <Space>
            <span>{t('deviceDetail.strategy.overrides')}</span>
            <Button type="primary" size="small" icon={<PlusOutlined />} onClick={() => setOverrideModalOpen(true)}>
              {t('deviceDetail.strategy.addOverride')}
            </Button>
          </Space>
        }
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        <Table<OverrideRecord>
          rowKey="id"
          columns={overrideColumns}
          dataSource={overrides}
          loading={overridesLoading}
          size="small"
          pagination={false}
          locale={{ emptyText: <Empty description={t('deviceDetail.strategy.noOverrides')} /> }}
        />
      </Card>

      <Modal
        title={t('deviceDetail.strategy.addOverride')}
        open={overrideModalOpen}
        onOk={async () => {
          try { createOverrideMutation.mutate(await overrideForm.validateFields()) } catch {}
        }}
        onCancel={() => { setOverrideModalOpen(false); overrideForm.resetFields() }}
        confirmLoading={createOverrideMutation.isPending}
        destroyOnClose
      >
        <Form form={overrideForm} layout="vertical" preserve={false}>
          <Form.Item name="override_type" label={t('deviceDetail.strategy.overrideType')} rules={[{ required: true }]}>
            <Select options={[
              { label: 'Force Charge', value: 'force_charge' },
              { label: 'Force Discharge', value: 'force_discharge' },
              { label: 'Pause', value: 'pause' },
              { label: 'Standby', value: 'standby' },
            ]} />
          </Form.Item>
          <Form.Item name="override_value" label={t('deviceDetail.strategy.overrideValue')}>
            <InputNumber style={{ width: '100%' }} placeholder="0-100" />
          </Form.Item>
          <Form.Item name="duration_minutes" label={t('deviceDetail.strategy.overrideDuration')} rules={[{ required: true }]}>
            <InputNumber min={1} max={1440} style={{ width: '100%' }} placeholder="60" />
          </Form.Item>
          <Form.Item name="reason" label={t('deviceDetail.strategy.overrideReason')}>
            <Input.TextArea rows={2} placeholder="..." />
          </Form.Item>
        </Form>
      </Modal>
    </Spin>
  )
}

export default StrategyTab
