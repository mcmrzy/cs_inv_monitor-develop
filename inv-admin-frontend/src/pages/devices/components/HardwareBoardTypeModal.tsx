import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { App, Form, Input, Modal, Select } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import { hardwareApi, hardwareError } from '@/services/hardwareApi'
import type { BoardType } from '@/types/hardware'

export default function HardwareBoardTypeModal({ onClose, initialModel }: { onClose: () => void; initialModel?: string }) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const client = useQueryClient()
  const admin = useAuthStore(s => s.user?.isSystemAdmin === true)
  const [form] = Form.useForm<BoardType>()
  const [busy, setBusy] = useState(false)
  const save = async () => {
    let values: BoardType
    try { values = await form.validateFields() } catch { return }
    if (!admin) return
    setBusy(true)
    try {
      await hardwareApi.createBoardType(values)
      await Promise.all([client.invalidateQueries({ queryKey: ['hardware-board-types'] }), client.invalidateQueries({ queryKey: ['board-types'] })])
      onClose(); message.success(t('hw.saved'))
    } catch (e) { message.error(hardwareError(e)) } finally { setBusy(false) }
  }
  if (!admin) return null
  return <Modal title={t('hw.boardCatalog')} open onCancel={onClose} onOk={() => void save()} confirmLoading={busy} okText={t('hw.submit')}>
    <Form form={form} layout="vertical" initialValues={{ model: initialModel }}>
      <Form.Item name="model" label={t('hw.model')} rules={[{ required: true, whitespace: true }]}><Input maxLength={64} /></Form.Item>
      <Form.Item name="target_chip" label={t('hw.target')} rules={[{ required: true }]}><Select options={['esp', 'arm', 'dsp', 'bms'].map(value => ({ value, label: value.toUpperCase() }))} /></Form.Item>
      <Form.Item name="board_code" label={t('hw.board')} rules={[{ required: true, whitespace: true }]}><Input maxLength={128} /></Form.Item>
      <Form.Item name="description" label={t('hw.description')}><Input maxLength={500} /></Form.Item>
    </Form>
  </Modal>
}
