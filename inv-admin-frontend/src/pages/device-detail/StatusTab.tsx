import { useQuery } from '@tanstack/react-query'
import { Card, Row, Col, Statistic, Tag, Spin, Empty, Typography, Table, Space } from 'antd'
import { CheckCircleFilled, CloseCircleFilled } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
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

  const snapshotColumns: ColumnsType<{ key: string; desired: string; reported: string }> = [
    { title: 'Key', dataIndex: 'key', key: 'key', width: 180, render: (v: string) => <Text code>{v}</Text> },
    { title: t('deviceDetail.diagnostics.desired'), dataIndex: 'desired', key: 'desired', render: (v: string) => v || '-' },
    { title: t('deviceDetail.diagnostics.reported'), dataIndex: 'reported', key: 'reported', render: (v: string) => v || '-' },
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
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={6}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Space>
              {statusIcon(isOnline)}
              <span>{t('deviceDetail.status.onlineStatus')}</span>
            </Space>
            <div style={{ marginTop: 8 }}>
              <Tag color={isOnline ? 'green' : 'red'}>{isOnline ? t('admin.connected') : t('admin.disconnected')}</Tag>
            </div>
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.workMode')} value={workMode} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.batterySoc')} value={batterySoc} suffix={typeof batterySoc === 'number' ? '%' : ''} />
          </Card>
        </Col>
        <Col span={6}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.syncStatus')} value={controlState?.sync_status ?? '-'} />
            {controlState?.reported_at && (
              <div style={{ color: '#999', fontSize: 12, marginTop: 4 }}>
                {t('deviceDetail.status.reportedAt')}: {formatInTimezone(controlState.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss')}
              </div>
            )}
          </Card>
        </Col>
      </Row>

      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.powerOutput')} value={powerOutput} suffix="W" />
          </Card>
        </Col>
        <Col span={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.powerInput')} value={powerInput} suffix="W" />
          </Card>
        </Col>
        <Col span={8}>
          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Statistic title={t('deviceDetail.status.loadPower')} value={loadPower} suffix="W" />
          </Card>
        </Col>
      </Row>

      <Card
        title={t('deviceDetail.diagnostics.configSnapshot')}
        size="small"
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        {snapshotData.length > 0 ? (
          <Table
            rowKey="key"
            columns={snapshotColumns}
            dataSource={snapshotData}
            size="small"
            pagination={false}
            scroll={{ y: 300 }}
          />
        ) : (
          <Empty description={t('deviceDetail.status.noData')} />
        )}
      </Card>
    </Spin>
  )
}

export default StatusTab
