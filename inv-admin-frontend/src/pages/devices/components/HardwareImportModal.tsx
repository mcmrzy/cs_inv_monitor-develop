import { useState } from 'react'
import { Alert, App, Button, Input, Modal, Space, Table, Tag, Upload } from 'antd'
import { useQueryClient } from '@tanstack/react-query'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import { hardwareApi, hardwareError } from '@/services/hardwareApi'
import { createOtaIdempotencyKey } from '@/services/otaApi'
import type { HardwareImportRow, HardwareImportPreview } from '@/types/hardware'
import HardwareBoardTypeModal from './HardwareBoardTypeModal'

/** CSV supports quoted commas, doubled quotes and embedded newlines; never splits evidence at commas. */
export function parseHardwareCsv(text: string): HardwareImportRow[] {
  const matrix: string[][] = []
  let line: string[] = [], value = '', quoted = false
  const input = text.replace(/^\uFEFF/, '')
  for (let i = 0; i < input.length; i++) {
    const c = input[i]
    if (c === '"') {
      if (quoted && input[i + 1] === '"') { value += '"'; i++ } else quoted = !quoted
    } else if (c === ',' && !quoted) { line.push(value); value = '' }
    else if ((c === '\n' || c === '\r') && !quoted) {
      if (c === '\r' && input[i + 1] === '\n') i++
      line.push(value); if (line.some(v => v.trim())) matrix.push(line)
      line = []; value = ''
    } else value += c
  }
  if (quoted) throw new Error('CSV: unterminated quoted field')
  line.push(value); if (line.some(v => v.trim())) matrix.push(line)
  if (matrix.length < 2) throw new Error('CSV: no data rows')
  const headers = matrix.shift()!.map(v => v.trim())
  const required = ['sn', 'verified_model', 'target_chip', 'board_code', 'evidence_ref']
  if (new Set(headers).size !== headers.length || required.some(h => !headers.includes(h))) throw new Error(`CSV: required columns ${required.join(',')}`)
  const rows = new Map<string, HardwareImportRow>()
  for (const [index, cells] of matrix.entries()) {
    if (cells.length !== headers.length) throw new Error(`CSV: invalid column count at row ${index + 2}`)
    const data = Object.fromEntries(headers.map((h, i) => [h, (cells[i] ?? '').trim()]))
    if (required.some(h => !data[h])) throw new Error(`CSV: missing value at row ${index + 2}`)
    if (!['esp', 'arm', 'dsp', 'bms'].includes(data.target_chip.toLowerCase())) throw new Error(`CSV: invalid target at row ${index + 2}`)
    const previous = rows.get(data.sn)
    if (previous && (previous.verified_model !== data.verified_model || previous.evidence_ref !== data.evidence_ref)) throw new Error(`CSV: inconsistent model/evidence for ${data.sn}`)
    const row = previous ?? { sn: data.sn, verified_model: data.verified_model, evidence_ref: data.evidence_ref, source: 'factory', reason: 'factory ledger import', modules: [] }
    if (row.modules.some(m => m.target_chip === data.target_chip.toLowerCase())) throw new Error(`CSV: duplicate target for ${data.sn}`)
    row.modules.push({ target_chip: data.target_chip.toLowerCase(), board_code: data.board_code, board_uid: data.board_uid || '', state: 'verified', protection_level: 'registry_verified' })
    rows.set(data.sn, row)
    if (rows.size > 10000) throw new Error('CSV: maximum 10000 devices')
  }
  return [...rows.values()]
}
export default function HardwareImportModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const admin = useAuthStore(s => s.user?.isSystemAdmin === true)
  const client = useQueryClient()
  const [text, setText] = useState('')
  const [preview, setPreview] = useState<HardwareImportPreview | null>(null)
  const [selected, setSelected] = useState<React.Key[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [key, setKey] = useState('')
  const [boardOpen, setBoardOpen] = useState(false)
  const showPreview = async () => {
    setError(''); setPreview(null); setSelected([]); setBusy(true)
    try {
      const result = await hardwareApi.previewImport(parseHardwareCsv(text))
      setPreview(result); setSelected(result.rows.filter(r => r.valid && r.status !== 'committed').map(r => r.row_index))
      setKey(createOtaIdempotencyKey('hardware-import'))
    } catch (e) { setError(hardwareError(e)) } finally { setBusy(false) }
  }
  const commit = async () => {
    if (!preview || !admin) return
    const valid = new Set(preview.rows.filter(r => r.valid && r.status !== 'committed').map(r => r.row_index))
    const indexes = selected.map(Number).filter(i => valid.has(i))
    if (!indexes.length) return
    setBusy(true); setError('')
    try {
      const result = await hardwareApi.commitImport(preview.id, indexes, key)
      setPreview(result); setSelected([]); setKey(createOtaIdempotencyKey('hardware-import'))
      await client.invalidateQueries({ queryKey: ['hardware'] })
      message.success(t('hw.importDone'))
    } catch (e) { setError(hardwareError(e)) } finally { setBusy(false) }
  }
  const updateText = (value: string) => { setText(value); setPreview(null); setSelected([]); setError('') }
  if (!admin) return null
  return <Modal title={t('hw.import')} open={open} onCancel={() => { if (!busy) onClose() }} width={960} footer={null} destroyOnClose>
    <Alert type="info" showIcon message={t('hw.importHint')} description={t('hw.csvHint')} style={{ marginBottom: 16 }} />
    <Space style={{ marginBottom: 12 }}>
      <Button onClick={() => setBoardOpen(true)}>{t('hw.boardCatalog')}</Button>
      <Upload accept=".csv,.xlsx,.xls" showUploadList={false} disabled={busy} beforeUpload={async file => {
        if (file.size > 20 * 1024 * 1024) { setError('CSV: maximum 20 MB'); return false }
        try {
          if (/\.xlsx?$/i.test(file.name)) {
            const xlsx = (window as Window & { XLSX?: { read: (buffer: ArrayBuffer, options: { type: string }) => { SheetNames: string[]; Sheets: Record<string, unknown> }; utils: { sheet_to_csv: (sheet: unknown) => string } } }).XLSX
            if (!xlsx) { setError(t('hw.xlsxUnavailable')); return false }
            const workbook = xlsx.read(await file.arrayBuffer(), { type: 'array' })
            if (!workbook.SheetNames.length) throw new Error('Excel: no worksheets')
            updateText(xlsx.utils.sheet_to_csv(workbook.Sheets[workbook.SheetNames[0]]))
          } else updateText(await file.text())
        } catch (e) { setError(hardwareError(e)) }
        return false
      }}><Button disabled={busy}>{t('hw.upload')}</Button></Upload>
      <Button disabled={busy} onClick={() => updateText('sn,verified_model,target_chip,board_code,board_uid,evidence_ref\n')}>CSV {t('hw.csv')}</Button>
    </Space>
    <label htmlFor="hardware-csv">{t('hw.csv')}</label>
    <Input.TextArea id="hardware-csv" rows={6} value={text} disabled={busy} onChange={e => updateText(e.target.value)} style={{ marginBottom: 12 }} />
    {error && <Alert type="error" showIcon message={error} style={{ marginBottom: 12 }} />}
    <Space><Button aria-label={t('hw.preview')} loading={busy} disabled={busy || !text.trim()} onClick={() => void showPreview()}>{t('hw.preview')}</Button>
      <Button aria-label={t('hw.commit')} type="primary" loading={busy} disabled={busy || !preview || !selected.length} onClick={() => void commit()}>{t('hw.commit')}</Button></Space>
    {preview && <Table style={{ marginTop: 16 }} size="small" rowKey="row_index" dataSource={preview.rows} pagination={{ pageSize: 10 }} rowSelection={{ selectedRowKeys: selected, onChange: keys => { setSelected(keys); setKey(createOtaIdempotencyKey('hardware-import')) }, getCheckboxProps: row => ({ disabled: !row.valid || row.status === 'committed' || busy }) }} columns={[
      { title: 'SN', render: (_, row) => row.data.sn }, { title: t('hw.model'), render: (_, row) => row.data.verified_model }, { title: t('hw.evidence'), render: (_, row) => row.data.evidence_ref },
      { title: t('hw.errors'), render: (_, row) => <><Tag color={row.valid ? 'success' : 'error'}>{row.status === 'committed' ? t('hw.committed') : row.valid ? t('hw.valid') : t('hw.invalid')}</Tag>{row.errors.join('; ')}</> },
    ]} />}
    {boardOpen && <HardwareBoardTypeModal onClose={() => setBoardOpen(false)} />}
  </Modal>
}
