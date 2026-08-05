import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Card, Descriptions, Progress, Spin, Tag, Typography, Space, Button, App, Empty, Tooltip,
} from 'antd'
import { ReloadOutlined, CheckCircleOutlined } from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { otaApi } from '@/services/otaApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Text } = Typography

interface InfoTabProps {
  sn: string
}

// 详情接口返回：{ device, realtime_data, load_percent, ota_available, online_status }
interface DeviceDetailPayload {
  device?: any
  load_percent?: number | null
  ota_available?: boolean
}

// 设备信息 tab（V2.1 决策 4）：DB 权威（详情接口），静态信息 5 分钟轮询；
// 四分组展示：固件 / 身份 / 额定 / 电池 + 负载率卡片。
const InfoTab: React.FC<InfoTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()

  const { data: detail, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.devices.detail(sn),
    queryFn: () => deviceApi.getDeviceBySn(sn).then((r) => (r.data?.data ?? null) as DeviceDetailPayload | null),
    refetchInterval: 300_000, // 静态信息 5min 轮询
  })

  const device = detail?.device
  const loadPercent = detail?.load_percent ?? null
  const otaAvailable = detail?.ota_available ?? false

  // 可升级目标版本（调 CheckUpdate 等价物：available-packages）
  const { data: packagesRes } = useQuery({
    queryKey: ['ota-available', sn],
    queryFn: () => otaApi.getAvailablePackages(sn).then((r) => (r.data?.data ?? r.data) as any[] | null),
    enabled: otaAvailable,
    staleTime: 60_000,
  })
  const packages = Array.isArray(packagesRes) ? packagesRes : ((packagesRes as any)?.items ?? [])
  const upgradeTarget = (packages as any[])?.[0]?.user_version ?? (packages as any[])?.[0]?.version

  const refreshMutation = useMutation({
    mutationFn: () => deviceApi.sendCommand(sn, { command: 'query_info', params: {} }),
    onSuccess: () => {
      message.success(t('deviceDetail.info.refreshQueued'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.detail(sn) })
    },
    onError: () => { message.error(t('deviceDetail.info.refreshFailed')) },
  })

  const fmtTime = (v?: string | null) => (v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-')
  const notRegistered = device?.model && !device?.model_id
  const ratedKw = device?.rated_power_w ? (device.rated_power_w / 1000).toFixed(2) : null

  const firmwareItems = (
    <>
      <Descriptions.Item label={t('deviceDetail.info.firmwareArm')}>
        <Space size={6}>
          <span>{device?.firmware_arm || '-'}</span>
          {otaAvailable && <Tag color="blue">{t('deviceDetail.info.upgradeAvailable')}{upgradeTarget ? ` ${upgradeTarget}` : ''}</Tag>}
        </Space>
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.firmwareEsp')}>
        <Space size={6}>
          <span>{device?.firmware_esp || '-'}</span>
          {otaAvailable && <Tag color="blue">{t('deviceDetail.info.upgradeAvailable')}{upgradeTarget ? ` ${upgradeTarget}` : ''}</Tag>}
        </Space>
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.firmwareDsp')}>{device?.firmware_dsp || t('deviceDetail.info.none')}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.firmwareBms')}>{device?.firmware_bms || t('deviceDetail.info.none')}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.bootloader')}>{device?.bootloader_version || '-'}</Descriptions.Item>
    </>
  )

  const identityItems = (
    <>
      <Descriptions.Item label={t('deviceDetail.deviceSn')}>
        <Text code>{device?.sn ?? sn}</Text>
      </Descriptions.Item>
      <Descriptions.Item label={t('common.model')}>
        <Space size={6}>
          <span>{device?.model || '-'}</span>
          {notRegistered && <Tag color="orange">{t('deviceDetail.info.modelNotRegistered')}</Tag>}
        </Space>
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.manufacturer')}>{device?.manufacturer || '-'}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.inverterModule')}>{device?.inverter_module || '-'}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.hardwareVersion')}>{device?.hardware_version || '-'}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.deviceType')}>
        {device?.device_type ? <Tag>{device.device_type}</Tag> : '-'}
      </Descriptions.Item>
    </>
  )

  const ratedItems = (
    <>
      <Descriptions.Item label={t('deviceDetail.info.ratedPower')}>
        {ratedKw ? `${ratedKw} kW` : '-'}
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.ratedVoltage')}>
        {device?.rated_voltage ? `${device.rated_voltage} V` : '-'}
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.ratedFrequency')}>
        {device?.rated_freq ? `${device.rated_freq} Hz` : '-'}
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.phase')}>{device?.phase || '-'}</Descriptions.Item>
    </>
  )

  const batteryItems = (
    <>
      <Descriptions.Item label={t('deviceDetail.info.batteryType')}>{device?.battery_type || '-'}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.batteryNominalVoltage')}>
        {device?.battery_voltage ? `${device.battery_voltage} V` : '-'}
      </Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.cellCount')}>{device?.cell_count ?? '-'}</Descriptions.Item>
      <Descriptions.Item label={t('deviceDetail.info.tempSensorCount')}>{device?.temp_sensor_count ?? '-'}</Descriptions.Item>
    </>
  )

  return (
    <Spin spinning={isLoading}>
      {error && (
        <QueryErrorAlert error={error} onRetry={() => void refetch()} style={{ marginBottom: 16 }} />
      )}

      {!isLoading && !device && (
        <Empty description={t('deviceDetail.status.noData')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
      )}

      {device && (
        <div>
          {/* 负载率卡片 */}
          <Card size="small" title={t('deviceDetail.info.loadTitle')} style={{ marginBottom: 16, borderRadius: 12 }} bordered={false}>
            {loadPercent != null ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
                <Progress
                  type="circle"
                  size={88}
                  percent={Math.round(loadPercent)}
                  strokeColor={loadPercent >= 90 ? '#fa541c' : loadPercent >= 75 ? '#faad14' : '#52c41a'}
                />
                <div>
                  <Text type="secondary" style={{ display: 'block' }}>{t('deviceDetail.info.loadHint')}</Text>
                  <Text strong style={{ fontSize: 20 }}>{Math.round(loadPercent)}%</Text>
                </div>
              </div>
            ) : (
              <Text type="secondary">{t('deviceDetail.info.noLoadData')}</Text>
            )}
          </Card>

          {/* 四分组：固件 / 身份 / 额定 / 电池 */}
          <Card size="small" title={t('deviceDetail.info.groupFirmware')} style={{ marginBottom: 16, borderRadius: 12 }} bordered={false}>
            <Descriptions column={2} size="small">{firmwareItems}</Descriptions>
          </Card>
          <Card size="small" title={t('deviceDetail.info.groupIdentity')} style={{ marginBottom: 16, borderRadius: 12 }} bordered={false}>
            <Descriptions column={2} size="small">{identityItems}</Descriptions>
          </Card>
          <Card size="small" title={t('deviceDetail.info.groupRated')} style={{ marginBottom: 16, borderRadius: 12 }} bordered={false}>
            <Descriptions column={2} size="small">{ratedItems}</Descriptions>
          </Card>
          <Card size="small" title={t('deviceDetail.info.groupBattery')} style={{ marginBottom: 16, borderRadius: 12 }} bordered={false}>
            <Descriptions column={2} size="small">{batteryItems}</Descriptions>
          </Card>

          <Card size="small" bordered={false} style={{ borderRadius: 12 }}>
            <Space size={16} wrap>
              <Tooltip title={t('deviceDetail.info.refreshHint')}>
                <Button
                  icon={<ReloadOutlined />}
                  loading={refreshMutation.isPending}
                  onClick={() => refreshMutation.mutate()}
                >
                  {t('deviceDetail.info.refreshInfo')}
                </Button>
              </Tooltip>
              <Text type="secondary" style={{ fontSize: 12 }}>
                <CheckCircleOutlined style={{ marginRight: 4 }} />
                {t('deviceDetail.info.reportedAt')}: {fmtTime(device?.info_reported_at)}
              </Text>
            </Space>
          </Card>
        </div>
      )}
    </Spin>
  )
}

export default InfoTab
