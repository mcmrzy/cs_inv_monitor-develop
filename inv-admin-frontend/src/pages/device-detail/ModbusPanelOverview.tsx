import { useState } from 'react'
import { Link, createSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Alert, Button, Card, Col, Descriptions, Empty, Flex, Progress, Row, Skeleton, Statistic, Tag, Typography, theme } from 'antd'
import { ControlOutlined, DashboardOutlined, MobileOutlined, SunOutlined, ThunderboltOutlined } from '@ant-design/icons'

import QueryErrorAlert from '@/components/QueryErrorAlert'
import useTranslation from '@/hooks/useTranslation'
import { deviceApi } from '@/services/deviceApi'
import useTimezoneStore from '@/stores/timezoneStore'
import { measuredGridPower } from '@/utils/gridPower'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import { formatPower, formatSignedPower, isRealtimeFresh, parseRtTimestamp, toRtEnvelope } from './energyUtils'

const MODELS = new Set(['PWR2KH12H1', '2KU', '3KU', '6KU', '12KU', 'CS-MB-PANEL'])

export function isModbusPanelDevice(device?: { model?: string; reported_model?: string; firmware_esp?: string }): boolean {
  return [device?.model, device?.reported_model].some((value) => value != null && MODELS.has(value.trim().toUpperCase()))
    || /-modbus-full$/i.test(device?.firmware_esp?.trim() ?? '')
}

function readNumber(realtime: Record<string, unknown>, ...keys: string[]): number | null {
  for (const key of keys) {
    const [group, field] = key.split('.')
    const parent = realtime[group]
    const value = field ? (parent as Record<string, unknown> | null)?.[field] : parent
    if (typeof value === 'number' && Number.isFinite(value)) return value
  }
  return null
}

function valueWithUnit(value: number | null, unit: string): string {
  return value == null ? '—' : `${value} ${unit}`
}

function powerLabel(value: number | null): string {
  return value == null ? '—' : formatPower(value)
}

export default function ModbusPanelOverview({ sn }: { sn: string }) {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const { token } = theme.useToken()
  const [showBluetooth, setShowBluetooth] = useState(false)
  const { data, isPending, error, refetch } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((res) => toRtEnvelope(res.data?.data ?? res.data)),
    refetchInterval: 10_000,
  })

  const readings = data?.realtime ?? {}
  const sampleTime = parseRtTimestamp(data?.dataTime ?? readings.updated_at)
  const sampleTimeKnown = Number.isFinite(sampleTime)
  const live = !error && sampleTimeKnown && isRealtimeFresh(data)
  const read = (...keys: string[]) => readNumber(readings, ...keys)
  const pvPower = read('pv_total_power', 'pv_power_total', 'pv.pv_total_power')
  const load = read('output_power', 'ac_active_power', 'ac_power', 'ac.output_power', 'ac.power')
  const soc = read('battery_soc', 'batt_soc', 'battery.soc', 'bat.battery_soc')
  const batteryVoltage = read('battery_voltage', 'battery.voltage', 'bat.battery_voltage')
  const batteryCurrent = read('battery_current', 'battery.current', 'bat.battery_current')
  const gridPower = measuredGridPower(readings)
  const gridLabel = gridPower == null ? '—' : formatSignedPower(gridPower)
  const hasSample = sampleTimeKnown || [pvPower, load, soc, gridPower].some((value) => value != null)
  const groups = [
    {
      key: 'pv', title: t('deviceDetail.energy.pvCard'), icon: <SunOutlined />,
      fields: [
        [t('deviceDetail.realtime.pv1Voltage'), valueWithUnit(read('pv1_voltage', 'pv.pv1_voltage'), 'V')],
        ['PV1', powerLabel(read('pv1_power', 'pv.pv1_power'))],
        [t('deviceDetail.realtime.pv2Voltage'), valueWithUnit(read('pv2_voltage', 'pv.pv2_voltage'), 'V')],
        ['PV2', powerLabel(read('pv2_power', 'pv.pv2_power'))],
      ],
    },
    {
      key: 'battery', title: t('deviceDetail.modbus.battery'), icon: <ThunderboltOutlined />,
      fields: [
        [t('deviceDetail.realtime.battVoltage'), valueWithUnit(batteryVoltage, 'V')],
        [t('deviceDetail.energy.current'), valueWithUnit(batteryCurrent, 'A')],
        [t('deviceDetail.modbus.batteryTemperature'), valueWithUnit(read('battery_avg_temp', 'battery_temperature', 'battery.temp'), '°C')],
      ],
    },
    {
      key: 'load', title: t('deviceDetail.modbus.gridLoad'), icon: <ThunderboltOutlined />,
      fields: [
        [t('deviceDetail.modbus.gridPower'), gridLabel],
        [t('deviceDetail.modbus.outputVoltage'), valueWithUnit(read('ac_output_voltage', 'output_voltage', 'ac_voltage', 'ac.voltage'), 'V')],
        [t('deviceDetail.modbus.outputFrequency'), valueWithUnit(read('ac_output_frequency', 'output_frequency', 'ac_frequency', 'ac.frequency'), 'Hz')],
        [t('deviceDetail.energy.loadRatio'), valueWithUnit(read('load_percent', 'sys.load_percent'), '%')],
      ],
    },
    {
      key: 'temperature', title: t('deviceDetail.modbus.temperatureAlarms'), icon: <DashboardOutlined />,
      fields: [
        [t('deviceDetail.realtime.inverterTemp'), valueWithUnit(read('inverter_temperature', 'inverter_temp', 'sys.inverter_temperature'), '°C')],
        [t('deviceDetail.realtime.busVoltage'), valueWithUnit(read('dc_bus_voltage', 'sys.dc_bus_voltage'), 'V')],
        [t('deviceDetail.modbus.faultCode'), String(read('fault_code', 'sys.fault_code') ?? '—')],
        [t('deviceDetail.modbus.warningCode'), String(read('alarm_code', 'warning', 'sys.warning') ?? '—')],
      ],
    },
  ]

  return (
    <Flex vertical gap={16}>
      <Flex justify="space-between" gap={12} wrap="wrap" align="center">
        <Flex align="center" gap={8} wrap="wrap">
          {hasSample && (
            <Tag color={live ? 'success' : 'warning'} style={{ marginInlineEnd: 0 }}>
              {t(live ? 'deviceDetail.modbus.cloudLive' : 'deviceDetail.modbus.cloudLastSample')}
            </Tag>
          )}
          {sampleTimeKnown && (
            <Typography.Text type="secondary">
              {formatInTimezone(new Date(sampleTime).toISOString(), timezone, 'YYYY-MM-DD HH:mm:ss')}
            </Typography.Text>
          )}
        </Flex>
        <Flex gap={8} wrap="wrap" align="center">
          <Button icon={<MobileOutlined />} onClick={() => setShowBluetooth(!showBluetooth)} aria-expanded={showBluetooth}>
            {t('deviceDetail.modbus.bluetooth')}
          </Button>
          <Link to={{ pathname: '/remote-settings', search: createSearchParams({ sn }).toString() }}>
            <ControlOutlined /> {t('menu.remoteSettings')}
          </Link>
        </Flex>
      </Flex>
      {showBluetooth && (
        <Alert showIcon type="info" message={t('deviceDetail.modbus.bluetoothInApp')} description={t('deviceDetail.modbus.bluetoothInstructions')} />
      )}
      {error && <QueryErrorAlert error={error} onRetry={() => void refetch()} />}
      {isPending ? <Skeleton active /> : !hasSample ? (
        !error && <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t('deviceDetail.modbus.noSample')} />
      ) : (
        <>
          <Row gutter={[12, 12]}>
            <Col xs={24} md={12}>
              <Card style={{
                height: '100%', color: token.colorWhite,
                background: 'linear-gradient(120deg, #10283c, #15554f)', borderColor: 'transparent',
              }}>
                <Statistic
                  title={<span style={{ color: '#bfe8db' }}><SunOutlined /> {t('deviceDetail.realtime.pvPower')}</span>}
                  value={powerLabel(pvPower)}
                  valueStyle={{ color: token.colorWhite, fontSize: 32, fontWeight: 600 }}
                />
                <div style={{ color: '#cfe7ea', marginTop: 8 }}>
                  {t('deviceDetail.energy.loadCard')} · {powerLabel(load)}
                </div>
              </Card>
            </Col>
            <Col xs={24} sm={12} md={6}>
              <Card style={{ height: '100%' }}>
                <Statistic title={t('deviceDetail.modbus.batterySoc')} value={soc == null ? '—' : `${soc}%`} />
                {soc != null && soc >= 0 && soc <= 100 && <Progress percent={soc} showInfo={false} />}
              </Card>
            </Col>
            <Col xs={24} sm={12} md={6}>
              <Card style={{ height: '100%' }}>
                <Statistic title={t('deviceDetail.modbus.gridPower')} value={gridLabel} />
              </Card>
            </Col>
          </Row>
          <Row gutter={[12, 12]}>
            {groups.map((group) => (
              <Col xs={24} lg={12} key={group.key}>
                <Card size="small" title={<Flex align="center" gap={8}>{group.icon}{group.title}</Flex>} style={{ height: '100%' }}>
                  <Descriptions size="small" column={{ xs: 1, sm: 2, lg: 2, xl: 2 }}
                    items={group.fields.map(([label, value]) => ({ key: label, label, children: value }))}
                  />
                </Card>
              </Col>
            ))}
          </Row>
        </>
      )}
    </Flex>
  )
}
