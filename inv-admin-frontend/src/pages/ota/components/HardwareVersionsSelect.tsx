import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Alert, App, Button, Form, Input, Modal, Select, Space } from 'antd'
import { PlusOutlined } from '@ant-design/icons'
import { otaApi } from '@/services/otaApi'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'

interface Props {
  model?: string
  value?: string[]
  onChange?: (versions: string[]) => void
}

/** Uses the model's standard directory. Free-form hardware tags are never accepted. */
export default function HardwareVersionsSelect({ model, value, onChange }: Props) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  const [createOpen, setCreateOpen] = useState(false)
  const [form] = Form.useForm<{ version: string; description?: string }>()
  const { data: versions = [], isLoading, error } = useQuery({
    queryKey: ['ota', 'hardwareVersions', model],
    queryFn: async () => {
      const res = await otaApi.listHardwareVersions(model!)
      const data = res.data?.data ?? res.data
      return (Array.isArray(data) ? data : []) as { version: string; description?: string }[]
    },
    enabled: !!model,
  })
  const create = useMutation({
    mutationFn: (values: { version: string; description?: string }) =>
      otaApi.createHardwareVersion({ model: model!, ...values, version: values.version.trim().toUpperCase() }),
    onSuccess: async (_res, values) => {
      await queryClient.invalidateQueries({ queryKey: ['ota', 'hardwareVersions', model] })
      onChange?.([...new Set([...(value ?? []), values.version.trim().toUpperCase()])])
      setCreateOpen(false)
      form.resetFields()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || t('ota.hardwareSaveFailed')),
  })
  return (
    <Space direction="vertical" style={{ width: '100%' }}>
      {error && <Alert type="error" showIcon message={t('ota.hardwareLoadFailed')} />}
      <Select mode="multiple" value={value} onChange={onChange} disabled={!model || !!error}
        loading={isLoading} style={{ width: '100%' }} placeholder={t('ota.selectHardwareVersions')}
        options={versions.map((v) => ({ value: v.version, label: `${v.version}${v.description ? ` · ${v.description}` : ''}` }))} />
      {isSystemAdmin && <Button type="link" size="small" icon={<PlusOutlined />} disabled={!model}
        onClick={() => setCreateOpen(true)}>{t('ota.addHardwareVersion')}</Button>}
      <Modal title={t('ota.addHardwareVersion')} open={createOpen} confirmLoading={create.isPending}
        onCancel={() => { setCreateOpen(false); form.resetFields() }}
        onOk={() => { void form.validateFields().then((values) => create.mutate(values)).catch(() => {}) }} destroyOnClose>
        <Form form={form} layout="vertical">
          <Form.Item label={t('ota.model')}><Input value={model} disabled /></Form.Item>
          <Form.Item name="version" label={t('ota.hardwareVersion')} rules={[{ required: true, whitespace: true, message: t('ota.hardwareVersionRequired') }]}>
            <Input maxLength={64} placeholder="HW-1.0" />
          </Form.Item>
          <Form.Item name="description" label={t('common.description')}><Input.TextArea maxLength={500} /></Form.Item>
        </Form>
      </Modal>
    </Space>
  )
}
