import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Alert, Button, Select, Space } from 'antd'
import { hardwareApi, hardwareError } from '@/services/hardwareApi'
import HardwareBoardTypeModal from '@/pages/devices/components/HardwareBoardTypeModal'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'

export default function BoardTypesSelect({ model, target, value, onChange }: { model?: string; target?: string; value?: string[]; onChange?: (values: string[]) => void }) {
  const { t } = useTranslation()
  const admin = useAuthStore(s => s.user?.isSystemAdmin === true)
  const [createOpen, setCreateOpen] = useState(false)
  const catalog = useQuery({ queryKey: ['board-types', model, target], queryFn: () => hardwareApi.listBoardTypes(model, target), enabled: !!model && !!target })
  return <Space direction="vertical" style={{ width: '100%' }}>
    {catalog.isError && <Alert type="error" message={hardwareError(catalog.error)} />}
    <Select mode="multiple" style={{ width: '100%' }} disabled={!model || !target || catalog.isError} loading={catalog.isLoading} value={value} onChange={onChange} options={(catalog.data ?? []).map(b => ({ value: b.board_code, label: `${b.board_code}${b.description ? ` · ${b.description}` : ''}` }))} />
    {admin && <Button type="link" disabled={!model || !target} onClick={() => setCreateOpen(true)}>{t('hw.boardCatalog')}</Button>}
    {createOpen && <HardwareBoardTypeModal initialModel={model} onClose={() => setCreateOpen(false)} />}
  </Space>
}
