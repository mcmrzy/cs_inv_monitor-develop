import type { Firmware } from '@/types'
import { useEffect, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Alert, App, Button, Checkbox, Form, Input, Modal, Spin } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import { hardwareApi, hardwareError } from '@/services/hardwareApi'
import HardwareBoardTypeModal from '@/pages/devices/components/HardwareBoardTypeModal'

export default function FirmwareBoardTypesEditor({ firmware, onClose }: { firmware: Firmware; onClose: () => void }) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const client = useQueryClient()
  const admin = useAuthStore(s => s.user?.isSystemAdmin === true)
  const [codes, setCodes] = useState<string[]>([])
  const [busy, setBusy] = useState(false)
  const [catalogOpen, setCatalogOpen] = useState(false)
  const [form] = Form.useForm<{ evidence_ref: string; reason: string }>()
  const catalog = useQuery({ queryKey: ['board-types', firmware.model, firmware.target_chip], queryFn: () => hardwareApi.listBoardTypes(firmware.model, firmware.target_chip) })
  const range = useQuery({ queryKey: ['firmware-board-types', firmware.id], queryFn: () => hardwareApi.getFirmwareBoardTypes(firmware.id) })
  useEffect(() => { if (range.data) setCodes(range.data) }, [range.data])
  const save = async () => {
    if (!admin) return
    let values: { evidence_ref: string; reason: string }
    try { values = await form.validateFields() } catch { return }
    setBusy(true)
    try {
      await hardwareApi.setFirmwareBoardTypes(firmware.id, codes, values.evidence_ref, values.reason)
      await client.invalidateQueries({ queryKey: ['ota'] })
      await client.invalidateQueries({ queryKey: ['firmware-board-types', firmware.id] })
      onClose(); message.success(t('hw.saved'))
    } catch (e) { message.error(hardwareError(e)) } finally { setBusy(false) }
  }
  const loadError = catalog.error || range.error
  return <Modal title={`${t('hw.editBoardRange')} · ${firmware.model} / ${firmware.target_chip} / ${firmware.version}`} open onCancel={onClose} onOk={() => void save()} okText={t('hw.saveRange')} confirmLoading={busy} okButtonProps={{ disabled: !admin || catalog.isLoading || range.isLoading || !!loadError || !codes.length }}>
    <Alert type="warning" showIcon message={t('hw.legacyHint')} description={(firmware.hardware_versions ?? []).join(', ') || '--'} style={{ marginBottom: 12 }} />
    <Alert type="info" message={t('hw.rangeHint')} style={{ marginBottom: 12 }} />
    {loadError && <Alert type="error" message={hardwareError(loadError)} action={<Button onClick={() => { void catalog.refetch(); void range.refetch() }}>{t('hw.retry')}</Button>} />}
    <Spin spinning={catalog.isLoading || range.isLoading}>
      <Checkbox.Group disabled={!admin} value={codes} onChange={values => setCodes(values.map(String))} options={(catalog.data ?? []).map(b => ({ value: b.board_code, label: `${b.board_code}${b.description ? ` — ${b.description}` : ''}` }))} />
      {catalog.isSuccess && !catalog.data.length && <Alert type="warning" message={t('hw.boardMissing')} />}
      {admin && catalog.isSuccess && <Button style={{ marginTop: 12 }} onClick={() => setCatalogOpen(true)}>{t('hw.boardCatalog')}</Button>}
      <Form form={form} layout="vertical" style={{ marginTop: 16 }}>
        <Form.Item name="evidence_ref" label={t('hw.evidence')} rules={[{ required: true, whitespace: true }]}><Input maxLength={256} disabled={!admin} /></Form.Item>
        <Form.Item name="reason" label={t('hw.reason')} rules={[{ required: true, whitespace: true }]}><Input.TextArea maxLength={1000} disabled={!admin} /></Form.Item>
      </Form>
    </Spin>
    {catalogOpen && <HardwareBoardTypeModal initialModel={firmware.model} initialTarget={firmware.target_chip} onClose={() => setCatalogOpen(false)} />}
  </Modal>
}
