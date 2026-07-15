import { useQuery } from '@tanstack/react-query'
import { Card, Alert, Descriptions, Tag, Spin, Empty, Typography } from 'antd'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

interface ParallelTabProps {
  sn: string
}

const ParallelTab: React.FC<ParallelTabProps> = ({ sn }) => {
  const { t } = useTranslation()

  const { data: controlState, isLoading } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => r.data?.data ?? null),
  })

  const reported = controlState?.reported ?? {}
  const parallelGroup = (reported.parallel_group as string) ?? (reported.group_id as string) ?? null
  const role = (reported.parallel_role as string) ?? (reported.role as string) ?? 'standalone'
  const phaseConfig = (reported.phase_config as string) ?? null

  const roleLabel = role === 'master'
    ? t('deviceDetail.parallel.master')
    : role === 'slave'
      ? t('deviceDetail.parallel.slave')
      : t('deviceDetail.parallel.standalone')

  const roleColor = role === 'master' ? 'blue' : role === 'slave' ? 'default' : 'green'

  return (
    <Spin spinning={isLoading}>
      <Card
        title={t('deviceDetail.parallel.title')}
        bordered={false}
        style={{ marginBottom: 16, borderRadius: 12 }}
      >
        <Alert
          message={t('deviceDetail.parallel.placeholder')}
          type="info"
          showIcon
          style={{ marginBottom: 24 }}
        />

        {parallelGroup || role !== 'standalone' ? (
          <Descriptions bordered column={1} size="small">
            <Descriptions.Item label={t('deviceDetail.parallel.currentGroup')}>
              {parallelGroup ? <Text code>{parallelGroup}</Text> : '-'}
            </Descriptions.Item>
            <Descriptions.Item label={t('deviceDetail.parallel.role')}>
              <Tag color={roleColor}>{roleLabel}</Tag>
            </Descriptions.Item>
            <Descriptions.Item label={t('deviceDetail.parallel.phaseConfig')}>
              {phaseConfig || '-'}
            </Descriptions.Item>
          </Descriptions>
        ) : (
          <Empty
            description={t('deviceDetail.parallel.notAvailable')}
            image={Empty.PRESENTED_IMAGE_SIMPLE}
          />
        )}
      </Card>
    </Spin>
  )
}

export default ParallelTab
