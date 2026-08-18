/**
 * 能源中心（Energy Dashboard 首页）
 * 结构：顶部 4 卡片（光伏/电池/负载/电网）→ 中部能量流图（sys_status 状态位驱动动画）。
 * 离线或数据过期时统一空态，绝不展示 Redis 陈旧缓存值。
 */
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Progress, Spin, Tag, Typography, Empty } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import { SunOutlined, ThunderboltOutlined, HomeOutlined, GlobalOutlined } from '@ant-design/icons'

import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import EnergyFlowDiagram from '@/pages/stations/components/EnergyFlowDiagram'
import {
  toRtEnvelope, isRealtimeFresh, freshRealtime, extractEnergyMetrics,
  formatPower, formatSignedPower, getGridState, parseRtTimestamp, ENERGY_COLORS, getSysBits,
} from './energyUtils'

const { Text } = Typography

interface EnergyCenterTabProps {
  sn: string
}

const CARD_SHADOW = '0 2px 8px rgba(17,24,39,0.06)'

const IconChip: React.FC<{ bg: string; color: string; children: React.ReactNode }> = ({ bg, color, children }) => (
  <div style={{
    width: 44, height: 44, borderRadius: 12, background: bg,
    display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22, color, flexShrink: 0,
  }}>
    {children}
  </div>
)

const CardTitle: React.FC<{ emoji: string; label: string }> = ({ emoji, label }) => (
  <span style={{ fontSize: 13, color: '#6b7280', fontWeight: 500 }}>{emoji} {label}</span>
)

/** 卡片内键值行：标签左 / 值右 */
const KvRow: React.FC<{ label: string; value: string; color?: string }> = ({ label, value, color }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6, fontSize: 12 }}>
    <span style={{ color: '#6b7280' }}>{label}</span>
    <span style={{ color: color ?? ENERGY_COLORS.dark, fontWeight: 600 }}>{value}</span>
  </div>
)

const EnergyCenterTab: React.FC<EnergyCenterTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()

  const { data: envelope, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(sn).then((r) => toRtEnvelope(r.data?.data ?? r.data)),
    refetchInterval: () => (document.visibilityState === 'visible' ? 10_000 : false),
  })

  const fresh = isRealtimeFresh(envelope)
  const rt = freshRealtime(envelope)
  const m = extractEnergyMetrics(rt)

  if (error) {
    return <QueryErrorAlert error={error} onRetry={() => void refetch()} />
  }

  // 离线 / 数据过期统一空态
  if (!isLoading && !fresh) {
    const lastTs = parseRtTimestamp(envelope?.dataTime)
    return (
      <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW }} bodyStyle={{ padding: '64px 24px' }}>
        <Empty
          image={Empty.PRESENTED_IMAGE_SIMPLE}
          description={
            <div>
              <div style={{ fontSize: 15, fontWeight: 600, color: ENERGY_COLORS.dark }}>
                {t('deviceDetail.energy.offlineTitle')}
              </div>
              <Text type="secondary" style={{ display: 'block', marginTop: 6 }}>
                {t('deviceDetail.energy.offlineEmpty')}
              </Text>
              {Number.isFinite(lastTs) && (
                <Text type="secondary" style={{ display: 'block', marginTop: 4, fontSize: 12 }}>
                  {t('deviceDetail.energy.lastDataTime')}: {formatInTimezone(new Date(lastTs).toISOString(), timezone, 'YYYY-MM-DD HH:mm:ss')}
                </Text>
              )}
            </div>
          }
        />
      </ProCard>
    )
  }

  // 状态位（V2 位掩码优先，V1 功率推导兜底）：驱动卡片状态文案与能流动画
  const bits = getSysBits(m)

  const battStateCfg = bits.charge
    ? { label: t('deviceDetail.energy.charging'), color: ENERGY_COLORS.energyGreen }
    : bits.discharge
      ? { label: t('deviceDetail.energy.discharging'), color: '#F59E0B' }
      : { label: t('deviceDetail.energy.standby'), color: '#9ca3af' }

  const gridState = getGridState(m.gridPower)
  const gridStateCfg = {
    import: { label: t('deviceDetail.energy.gridImport'), color: ENERGY_COLORS.smartBlue },
    export: { label: t('deviceDetail.energy.gridExport'), color: ENERGY_COLORS.energyGreen },
    idle: { label: t('deviceDetail.energy.standby'), color: '#9ca3af' },
  }[gridState]

  // PV2 电压≤ 0 视为未接组串，显示 '--'
  const pv2VoltStr = m.pv2Voltage > 0 ? `${m.pv2Voltage.toFixed(1)} V` : '--'
  const pv1VoltStr = m.pv1Voltage > 0 ? `${m.pv1Voltage.toFixed(1)} V` : '--'

  return (
    <Spin spinning={isLoading}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* ── 顶部 4 卡片 ── */}
        <Row gutter={[16, 16]}>
          {/* ☀️ 光伏：实时功率 + PV1/PV2 电压 + 今日/累计发电 */}
          <Col xs={24} sm={12} xl={6}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} bodyStyle={{ padding: 20 }}>
              <Row align="middle" gutter={12} style={{ marginBottom: 12 }}>
                <Col><IconChip bg="#F59E0B18" color={ENERGY_COLORS.pv}><SunOutlined /></IconChip></Col>
                <Col flex={1}><CardTitle emoji="☀️" label={t('deviceDetail.energy.pvCard')} /></Col>
              </Row>
              <div style={{ fontSize: 28, fontWeight: 700, color: ENERGY_COLORS.dark, lineHeight: 1.1 }}>
                {formatPower(m.pvPower)}
              </div>
              <Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 4 }}>
                {t('deviceDetail.energy.realtimePower')}
              </Text>
              <div style={{ marginTop: 8 }}>
                <KvRow label="PV1" value={pv1VoltStr} />
                <KvRow label="PV2" value={pv2VoltStr} />
                <KvRow label={t('deviceDetail.energy.todayGeneration')} value={`${m.dailyPv.toFixed(1)} kWh`} />
                <KvRow label={t('deviceDetail.energy.totalGeneration')} value={`${m.totalPv.toFixed(1)} kWh`} />
              </div>
            </ProCard>
          </Col>

          {/* 🔋 电池：SOC 大圆环 + 电压/状态/功率/电流 */}
          <Col xs={24} sm={12} xl={6}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} bodyStyle={{ padding: 20 }}>
              <Row align="middle" gutter={16} wrap={false}>
                <Col>
                  <Progress
                    type="circle"
                    size={96}
                    percent={Math.round(m.battSoc)}
                    strokeColor={{ '0%': ENERGY_COLORS.smartBlue, '100%': ENERGY_COLORS.energyGreen }}
                    format={(p) => (
                      <div>
                        <div style={{ fontSize: 22, fontWeight: 700, color: ENERGY_COLORS.dark }}>{p}%</div>
                        <div style={{ fontSize: 11, color: '#9ca3af' }}>SOC</div>
                      </div>
                    )}
                  />
                </Col>
                <Col flex={1}>
                  <CardTitle emoji="🔋" label={t('deviceDetail.energy.battCard')} />
                  <div style={{ marginTop: 8 }}>
                    <Tag color={battStateCfg.color} style={{ borderRadius: 8, fontWeight: 600 }}>{battStateCfg.label}</Tag>
                  </div>
                  <div style={{ fontSize: 18, fontWeight: 700, color: ENERGY_COLORS.dark, marginTop: 6 }}>
                    {formatSignedPower(m.battPower)}
                  </div>
                  <Text type="secondary" style={{ fontSize: 12 }}>
                    {m.battVoltage != null ? `${m.battVoltage.toFixed(1)} V` : '--'}
                    {m.battCurrent != null ? ` · ${m.battCurrent.toFixed(1)} A` : ''}
                  </Text>
                </Col>
              </Row>
            </ProCard>
          </Col>

          {/* 🏠 负载：功率 + 负载率 + 电流 */}
          <Col xs={24} sm={12} xl={6}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} bodyStyle={{ padding: 20 }}>
              <Row align="middle" gutter={12} style={{ marginBottom: 12 }}>
                <Col><IconChip bg="#00D4FF18" color={ENERGY_COLORS.load}><HomeOutlined /></IconChip></Col>
                <Col flex={1}><CardTitle emoji="🏠" label={t('deviceDetail.energy.loadCard')} /></Col>
              </Row>
              <div style={{ fontSize: 28, fontWeight: 700, color: ENERGY_COLORS.dark, lineHeight: 1.1 }}>
                {formatPower(m.loadPower)}
              </div>
              <Text type="secondary" style={{ fontSize: 12, display: 'block', marginTop: 8 }}>
                {t('deviceDetail.energy.loadRatio')}:{' '}
                <Text strong>{m.loadPercent != null ? `${Math.round(m.loadPercent)}%` : '--'}</Text>
                {m.acCurrent != null && (
                  <span style={{ marginLeft: 10 }}>{t('deviceDetail.energy.current')}: <Text strong>{m.acCurrent.toFixed(1)} A</Text></span>
                )}
              </Text>
              {m.loadPercent != null && (
                <Progress
                  percent={Math.min(Math.round(m.loadPercent), 100)}
                  showInfo={false}
                  size="small"
                  strokeColor={m.loadPercent >= 90 ? '#ff4d4f' : m.loadPercent >= 75 ? '#faad14' : ENERGY_COLORS.energyGreen}
                  style={{ marginTop: 6, marginBottom: 0 }}
                />
              )}
            </ProCard>
          </Col>

          {/* 🌐 电网 */}
          <Col xs={24} sm={12} xl={6}>
            <ProCard style={{ borderRadius: 12, boxShadow: CARD_SHADOW, height: '100%' }} bodyStyle={{ padding: 20 }}>
              <Row align="middle" gutter={12} style={{ marginBottom: 12 }}>
                <Col><IconChip bg="#8B5CF618" color={ENERGY_COLORS.grid}><GlobalOutlined /></IconChip></Col>
                <Col flex={1}><CardTitle emoji="🌐" label={t('deviceDetail.energy.gridCard')} /></Col>
              </Row>
              <div style={{ fontSize: 22, fontWeight: 700, color: ENERGY_COLORS.dark, lineHeight: 1.2 }}>
                {m.gridVoltage != null ? `${m.gridVoltage.toFixed(1)} V` : '--'}
                <Text type="secondary" style={{ fontSize: 14, fontWeight: 500, marginLeft: 8 }}>
                  {m.gridFreq != null ? `${m.gridFreq.toFixed(1)} Hz` : ''}
                </Text>
              </div>
              <div style={{ marginTop: 8 }}>
                <Tag color={gridStateCfg.color} style={{ borderRadius: 8, fontWeight: 600 }}>{gridStateCfg.label}</Tag>
                <Text type="secondary" style={{ fontSize: 12, marginLeft: 6 }}>{formatPower(m.gridPower)}</Text>
              </div>
            </ProCard>
          </Col>
        </Row>

        {/* ── 中部：能量流图（sys_status 状态位驱动流动动画）── */}
        <ProCard
          style={{ borderRadius: 12, boxShadow: CARD_SHADOW }}
          title={<span style={{ fontWeight: 600 }}><ThunderboltOutlined style={{ color: ENERGY_COLORS.smartBlue, marginRight: 6 }} />{t('deviceDetail.energy.flowTitle')}</span>}
          size="small"
        >
          <EnergyFlowDiagram
            pvPower={m.pvPower}
            loadPower={m.loadPower}
            battPower={m.battPower}
            gridPower={m.gridPower}
            battSoc={m.battSoc}
            genPower={m.genPower}
            sysBits={bits}
          />
        </ProCard>
      </div>
    </Spin>
  )
}

export default EnergyCenterTab
