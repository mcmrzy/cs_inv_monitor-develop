import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Alert, App, DatePicker, Form, Input, InputNumber, Modal, Select, Table, Tag } from 'antd'
import dayjs from 'dayjs'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import { hardwareApi, hardwareError } from '@/services/hardwareApi'
import type { CompatibilityWindow } from '@/types/hardware'

export default function CompatibilityWindowsModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const admin = useAuthStore(s => s.user?.isSystemAdmin === true)
  const [busy, setBusy] = useState(false)
  const [form] = Form.useForm<Omit<CompatibilityWindow, 'expires_at'> & { expires_at: dayjs.Dayjs }>()
  const windows = useQuery({ queryKey: ['ota-compatibility-windows'], queryFn: () => hardwareApi.listCompatibilityWindows(), enabled: open && admin })
  const save = async () => {
    let values: Omit<CompatibilityWindow, 'expires_at'> & { expires_at: dayjs.Dayjs }
    try { values = await form.validateFields() } catch { return }
    if (!admin) return
    setBusy(true)
    try {
      await hardwareApi.createCompatibilityWindow({ ...values, sn: values.sn.trim(), file_sha256: values.file_sha256.trim().toLowerCase(), expires_at: values.expires_at.toISOString() })
      form.resetFields(); await windows.refetch(); message.success(t('hw.saved'))
    } catch (e) { message.error(hardwareError(e)) } finally { setBusy(false) }
  }
  if (!admin) return null
  const required = { required: true, message: t('hw.required') }
  return <Modal title={t('hw.window')} open={open} onCancel={onClose} width={940} onOk={() => void save()} okText={t('hw.createWindow')} confirmLoading={busy}>
    <Alert type="warning" showIcon message={t('hw.windowHint')} style={{ marginBottom: 16 }} />
    {windows.isError && <Alert type="error" message={hardwareError(windows.error)} />}
    <Table size="small" rowKey={row => String(row.id ?? `${row.sn}:${row.firmware_id}:${row.expires_at}`)} loading={windows.isLoading} dataSource={windows.data ?? []} pagination={{ pageSize: 5 }} columns={[
      { title: 'SN', dataIndex: 'sn' }, { title: t('hw.target'), dataIndex: 'target_chip' }, { title: t('hw.firmwareId'), dataIndex: 'firmware_id' }, { title: t('hw.revision'), dataIndex: 'identity_revision' }, { title: t('hw.evidence'), dataIndex: 'evidence_ref' },
      { title: t('hw.expiry'), dataIndex: 'expires_at', render: v => <Tag color={dayjs(v).isAfter(dayjs()) ? 'warning' : 'default'}>{dayjs(v).format('YYYY-MM-DD HH:mm:ss')}</Tag> },
    ]} />
    <Form form={form} layout="vertical" style={{ marginTop: 16 }}>
      <Form.Item name="sn" label="SN" rules={[required, { whitespace: true }]}><Input maxLength={64} /></Form.Item>
      <Form.Item name="target_chip" label={t('hw.target')} rules={[required]}><Select options={['esp', 'arm', 'dsp', 'bms'].map(value => ({ value, label: value.toUpperCase() }))} /></Form.Item>
      <Form.Item name="firmware_id" label={t('hw.firmwareId')} rules={[required]}><InputNumber min={1} precision={0} /></Form.Item>
      <Form.Item name="file_sha256" label={t('hw.hash')} rules={[required, { pattern: /^[a-fA-F0-9]{64}$/, message: 'SHA-256: 64 hex characters' }]}><Input maxLength={64} /></Form.Item>
      <Form.Item name="identity_revision" label={t('hw.revision')} rules={[required]}><InputNumber min={1} precision={0} /></Form.Item>
      <Form.Item name="evidence_ref" label={t('hw.evidence')} rules={[required, { whitespace: true }]}><Input maxLength={256} /></Form.Item>
      <Form.Item name="reason" label={t('hw.reason')} rules={[required, { whitespace: true }]}><Input.TextArea maxLength={1000} /></Form.Item>
      <Form.Item name="expires_at" label={t('hw.expiry')} rules={[required, { validator: async (_, value) => { if (value && (!value.isAfter(dayjs()) || value.isAfter(dayjs().add(72, 'hour')))) throw new Error(`${t('hw.expiry')}: 1–72h`) } }]}><DatePicker showTime disabledDate={d => d.endOf('day').isBefore(dayjs()) || d.startOf('day').isAfter(dayjs().add(72, 'hour'))} /></Form.Item>
    </Form>
  </Modal>
}
