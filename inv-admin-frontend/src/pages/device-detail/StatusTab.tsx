import { useQuery } from '@tanstack/react-query'
import { Statistic, Tag, Spin, Empty, Typography, Space } from 'antd'
import { ProCard, ProTable } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import { CheckCircleFilled, CloseCircleFilled } from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text } = Typography

interface StatusTabProps {
  sn: string
}

const StatusTab: React.FC<StatusTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()

  const { data: controlState, isLoading: stateLoading, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => r.data?.data ?? null),
    refetchInterval: 15000,
  })

  const { data: realtime, isLoading: rtLoading, error: realtimeError, refetch: refetchRealtime } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => r.data?.data ?? null),
    refetchInterval: 10000,
  })

  const { data: deviceInfo, error: deviceError, refetch: refetchDevice } = useQuery({
    queryKey: queryKeys.devices.detail(sn),
    queryFn: () => deviceApi.getDeviceBySn(sn).then((r) => r.data?.data ?? null),
  })

  const isOnline = deviceInfo?.status === 'online'
  const reported = controlState?.reported ?? {}
  const rtData = realtime ?? {}

  // Extract power-related fields from realtime data
  const powerOutput = rtData.output_power ?? rtData.power_output ?? '-'
  const powerInput = rtData.input_power ?? rtData.power_input ?? '-'
  const loadPower = rtData.load_power ?? '-'
  const batterySoc = rtData.battery_soc ?? rtData.soc ?? reported.battery_soc ?? '-'
  const workMode = rtData.work_mode ?? reported.work_mode ?? '-'

  const statusIcon = (ok: boolean) => ok
    ? <CheckCircleFilled style={{ color: '#52c41a', fontSize: 18 }} />
    : <CloseCircleFilled style={{ color: '#ff4d4f', fontSize: 18 }} />

  const snapshotColumns: ProColumns<{ key: string; desired: string; reported: string }>[] = [
    { title: 'Key', dataIndex: 'key', key: 'key', width: 180, render: (_, record) => <Text code>{record.key}</Text> },
    { title: t('deviceDetail.diagnostics.desired'), dataIndex: 'desired', key: 'desired', render: (_, record) => record.desired || '-' },
    { title: t('deviceDetail.diagnostics.reported'), dataIndex: 'reported', key: 'reported', render: (_, record) => record.reported || '-' },
  ]

  const allKeys = Array.from(new Set([
    ...Object.keys(controlState?.desired ?? {}),
    ...Object.keys(controlState?.reported ?? {}),
  ])).sort()

  const snapshotData = allKeys.map((key) => ({
    key,
    desired: String(controlState?.desired?.[key] ?? ''),
    reported: String(controlState?.reported?.[key] ?? ''),
  }))

  return (
    <Spin spinning={stateLoading || rtLoading}>
      {(stateError || realtimeError || deviceError) && (
        <QueryErrorAlert
          error={stateError || realtimeError || deviceError}
          onRetry={() => {
            void (stateError ? refetchState() : realtimeError ? refetchRealtime() : refetchDevice())
          }}
          style={{ marginBottom: 16 }}
        />
      )}
      <ProCard gutter={16} style={{ marginBottom: 16 }}>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Space>
            {statusIcon(isOnline)}
            <span>{t('deviceDetail.status.onlineStatus')}</span>
          </Space>
          <div style={{ marginTop: 8 }}>
            <Tag color={isOnline ? 'green' : 'red'}>{isOnline ? t('admin.connected') : t('admin.disconnected')}</Tag>
          </div>
        </ProCard>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.workMode')} value={workMode} />
        </ProCard>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.batterySoc')} value={batterySoc} suffix={typeof batterySoc === 'number' ? '%' : ''} />
        </ProCard>
        <ProCard colSpan={6} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.syncStatus')} value={controlState?.sync_status ?? '-'} />
          {controlState?.reported_at && (
            <div style={{ color: '#999', fontSize: 12, marginTop: 4 }}>
              {t('deviceDetail.status.reportedAt')}: {formatInTimezone(controlState.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss')}
            </div>
          )}
        </ProCard>
      </ProCard>

      <ProCard gutter={16} style={{ marginBottom: 16 }}>
        <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.powerOutput')} value={powerOutput} suffix="W" />
        </ProCard>
        <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.powerInput')} value={powerInput} suffix="W" />
        </ProCard>
        <ProCard colSpan={8} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Statistic title={t('deviceDetail.status.loadPower')} value={loadPower} suffix="W" />
        </ProCard>
      </ProCard>

      <ProCard
        title={t('deviceDetail.diagnostics.configSnapshot')}
        size="small"
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        {snapshotData.length > 0 ? (
          <ProTable
            rowKey="key"
            columns={snapshotColumns}
            dataSource={snapshotData}
            size="small"
            search={false}
            options={{ density: true, reload: false, setting: true }}
            pagination={false}
            scroll={{ y: 300 }}
          />
        ) : (
          <Empty description={t('deviceDetail.status.noData')} />
        )}
      </ProCard>
    </Spin>
  )
}

export default StatusTab
