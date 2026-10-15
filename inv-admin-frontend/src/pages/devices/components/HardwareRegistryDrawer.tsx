import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Alert, App, Button, Descriptions, Drawer, Empty, Form, Input, Modal, Select, Space, Table, Tag, Tabs } from 'antd'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import { hardwareApi, hardwareError } from '@/services/hardwareApi'
import type { RegistryMutation } from '@/types/hardware'
import HardwareBoardTypeModal from './HardwareBoardTypeModal'

type Action = 'verify' | 'corrections' | 'service-changes' | 'freeze'
export default function HardwareRegistryDrawer({ sn, onClose }: { sn: string; onClose: () => void }) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const admin = useAuthStore(s => s.user?.isSystemAdmin === true)
  const client = useQueryClient()
  const [action, setAction] = useState<Action | null>(null)
  const [busy, setBusy] = useState(false)
  const [catalogOpen, setCatalogOpen] = useState(false)
  const [historyPage, setHistoryPage] = useState(1)
  const [form] = Form.useForm<RegistryMutation>()
  const model = Form.useWatch('verified_model', form)
  const registry = useQuery({ queryKey: ['hardware', sn], queryFn: async () => {
    try { return await hardwareApi.getRegistry(sn) } catch (e) {
      if ((e as { response?: { status?: number } }).response?.status === 404) return null
      throw e
    }
  } })
  const catalog = useQuery({ queryKey: ['hardware-board-types'], queryFn: () => hardwareApi.listBoardTypes(), enabled: admin })
  const history = useQuery({ queryKey: ['hardware-history', sn, historyPage], queryFn: () => hardwareApi.getHistory(sn, historyPage), enabled: !!registry.data?.identity_revision })
  const record = registry.data
  const begin = (next: Action) => {
    form.resetFields()
    form.setFieldsValue({ expected_revision: record?.identity_revision ?? 0, verified_model: record?.verified_model ?? '', source: next === 'service-changes' ? 'service' : 'factory', modules: (record?.modules ?? []).map(m => ({ ...m, protection_level: 'registry_verified' })) })
    setAction(next)
  }
  const save = async () => {
    let values: RegistryMutation
    try { values = await form.validateFields() } catch { return }
    setBusy(true)
    try {
      const expected_revision = form.getFieldValue('expected_revision') as number
      const body = action === 'freeze' ? { expected_revision, evidence_ref: values.evidence_ref, reason: values.reason, source: values.source, frozen: !record?.frozen } : { ...values, expected_revision, modules: values.modules?.map(m => ({ target_chip: m.target_chip, board_code: m.state === 'absent' ? '' : m.board_code, board_uid: m.state === 'absent' ? '' : m.board_uid, state: m.state ?? 'verified', protection_level: 'registry_verified' })) }
      await hardwareApi.mutateRegistry(sn, action!, body)
      setAction(null)
      setHistoryPage(1)
      await Promise.all([client.invalidateQueries({ queryKey: ['hardware', sn] }), client.invalidateQueries({ queryKey: ['hardware-history', sn] }), client.invalidateQueries({ queryKey: ['devices'] })])
      message.success(t('hw.saved'))
    } catch (e) { message.error(hardwareError(e)); void registry.refetch() } finally { setBusy(false) }
  }
  const stateColor = record?.identity_state === 'verified' && !record.frozen ? 'success' : 'warning'
  const moduleEditor = <Form.List name="modules" rules={[{ validator: async (_, rows) => { if (!rows?.length) throw new Error(t('hw.required')) } }]}>{(fields, { add, remove }, { errors }) => <>
    {fields.map(field => <Space key={field.key} align="start" wrap style={{ display: 'flex' }}>
      <Form.Item name={[field.name, 'target_chip']} label={t('hw.target')} rules={[{ required: true }]}><Select style={{ width: 110 }} options={['esp', 'arm', 'dsp', 'bms'].map(value => ({ value, label: value.toUpperCase() }))} /></Form.Item>
      <Form.Item name={[field.name, 'state']} label={t('hw.state')} initialValue="verified"><Select style={{ width: 115 }} options={[{ value: 'verified', label: t('hw.present') }, { value: 'absent', label: t('hw.absent') }]} /></Form.Item>
      <Form.Item noStyle shouldUpdate>{({ getFieldValue }) => {
        const target = getFieldValue(['modules', field.name, 'target_chip'])
        const absent = getFieldValue(['modules', field.name, 'state']) === 'absent'
        return <Form.Item name={[field.name, 'board_code']} label={t('hw.board')} rules={[{ required: !absent }]}><Select disabled={absent} loading={catalog.isLoading} style={{ width: 180 }} options={(catalog.data ?? []).filter(b => b.model === model && b.target_chip === target).map(b => ({ value: b.board_code, label: b.board_code }))} /></Form.Item>
      }}</Form.Item>
      <Form.Item name={[field.name, 'board_uid']} label={t('hw.uid')}><Input style={{ width: 160 }} maxLength={128} /></Form.Item>
      <Button onClick={() => remove(field.name)} style={{ marginTop: 30 }}>{t('hw.remove')}</Button>
    </Space>)}
    <Form.ErrorList errors={errors} /><Button onClick={() => add({ state: 'verified', protection_level: 'registry_verified' })}>{t('hw.addModule')}</Button>
  </>}</Form.List>
  return <>
    <Drawer title={`${t('hw.registry')} · ${sn}`} open onClose={onClose} width={840} loading={registry.isLoading}>
      <Alert showIcon type="info" message={t('hw.trustHint')} style={{ marginBottom: 16 }} />
      {registry.isError ? <Alert type="error" message={hardwareError(registry.error)} action={<Button onClick={() => void registry.refetch()}>{t('hw.retry')}</Button>} /> : <>
        {!record?.identity_revision && !registry.isLoading && <Alert type="warning" message={t('hw.noRegistry')} />}
        {record && <>
          <Descriptions column={2} bordered size="small">
            <Descriptions.Item label={t('hw.model')}>{record.verified_model || '--'}</Descriptions.Item>
            <Descriptions.Item label={t('hw.state')}><Tag color={stateColor}>{t(`hw.${record.identity_state}`)}</Tag>{record.frozen && <Tag color="error">{t('hw.frozen')}</Tag>}</Descriptions.Item>
            <Descriptions.Item label={t('hw.revision')}>{record.identity_revision}</Descriptions.Item>
            <Descriptions.Item label={t('hw.source')}>{record.source || '--'}</Descriptions.Item>
            <Descriptions.Item label={t('hw.evidence')}>{record.evidence_ref || '--'}</Descriptions.Item>
          </Descriptions>
          <Tabs items={[
            { key: 'modules', label: t('hw.modules'), children: <Table size="small" rowKey="target_chip" pagination={false} dataSource={record.modules ?? []} columns={[
              { title: t('hw.target'), dataIndex: 'target_chip' }, { title: t('hw.board'), dataIndex: 'board_code', render: v => v || '--' }, { title: t('hw.uid'), dataIndex: 'board_uid', render: v => v || '--' },
              { title: t('hw.state'), dataIndex: 'state', render: v => t(`hw.${v}`) }, { title: t('hw.protection'), dataIndex: 'protection_level', render: v => v === 'registry_verified' || v === 'legacy' || !v ? t('hw.registryVerified') : v },
            ]} /> },
            { key: 'observations', label: t('hw.observations'), children: record.observations?.length ? <Table size="small" rowKey={(_, i) => String(i)} pagination={{ pageSize: 10 }} dataSource={record.observations} columns={[
              { title: t('hw.at'), dataIndex: 'reported_at', render: (v, row) => String(v ?? row.created_at ?? '--') }, { title: t('hw.source'), dataIndex: 'source' }, { title: t('hw.model'), dataIndex: 'reported_model', render: v => v || '--' }, { title: t('hw.target'), dataIndex: 'scope' }, { title: t('hw.board'), dataIndex: 'reported_board_code', render: v => v || '--' }, { title: t('hw.uid'), dataIndex: 'reported_board_uid', render: v => v || '--' },
            ]} /> : <Empty description={t('hw.empty')} /> },
            { key: 'history', label: t('hw.history'), children: history.isError ? <Alert type="error" message={hardwareError(history.error)} /> : <Table size="small" rowKey="id" loading={history.isLoading} dataSource={history.data?.items ?? []} pagination={{ current: historyPage, total: history.data?.total ?? 0, pageSize: 10, showSizeChanger: false, onChange: setHistoryPage }} columns={[
              { title: t('hw.action'), dataIndex: 'action' }, { title: t('hw.revision'), dataIndex: 'identity_revision' }, { title: t('hw.evidence'), dataIndex: 'evidence_ref' }, { title: t('hw.reason'), dataIndex: 'reason' }, { title: t('hw.at'), dataIndex: 'created_at' },
            ]} /> },
          ]} />
        </>}
        {admin && <Space wrap style={{ marginTop: 16 }}>
          {(!record || record.identity_state === 'unverified') && <Button type="primary" onClick={() => begin('verify')}>{t('hw.verify')}</Button>}
          {!!record?.identity_revision && <><Button onClick={() => begin('corrections')}>{t('hw.correct')}</Button><Button disabled={!record.frozen} onClick={() => begin('service-changes')}>{t('hw.service')}</Button><Button danger={ !record.frozen } disabled={record.frozen && record.identity_state !== 'verified'} onClick={() => begin('freeze')}>{t(record.frozen ? 'hw.unfreeze' : 'hw.freeze')}</Button></>}
          <Button onClick={() => setCatalogOpen(true)}>{t('hw.boardCatalog')}</Button>
        </Space>}
      </>}
    </Drawer>
    <Modal title={t(action === 'freeze' ? record?.frozen ? 'hw.unfreeze' : 'hw.freeze' : action === 'service-changes' ? 'hw.service' : action === 'corrections' ? 'hw.correct' : 'hw.verify')} open={!!action} width={820} onCancel={() => setAction(null)} onOk={() => void save()} okText={t('hw.submit')} confirmLoading={busy} destroyOnClose>
      <Alert type="warning" showIcon message={t('hw.changeHint')} style={{ marginBottom: 16 }} />
      <Form form={form} layout="vertical">
        {action !== 'freeze' && <Form.Item name="verified_model" label={t('hw.model')} rules={[{ required: true }]}><Input maxLength={64} /></Form.Item>}
        <Form.Item name="source" label={t('hw.source')} rules={[{ required: true }]}><Select options={[{ value: 'factory', label: t('hw.factory') }, { value: 'service', label: t('hw.serviceSource') }, { value: 'manual', label: t('hw.reviewSource') }]} /></Form.Item>
        <Form.Item name="evidence_ref" label={t('hw.evidence')} rules={[{ required: true, whitespace: true }]}><Input maxLength={256} /></Form.Item>
        <Form.Item name="reason" label={t('hw.reason')} rules={[{ required: true, whitespace: true }]}><Input.TextArea maxLength={1000} /></Form.Item>
        {action !== 'freeze' && moduleEditor}
        {catalog.isError && <Alert type="error" message={hardwareError(catalog.error)} />}
      </Form>
    </Modal>
    {catalogOpen && <HardwareBoardTypeModal initialModel={record?.verified_model} onClose={() => setCatalogOpen(false)} />}
  </>
}
