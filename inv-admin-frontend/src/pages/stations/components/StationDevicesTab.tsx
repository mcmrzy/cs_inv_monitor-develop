import React, { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Row, Col, Input, Select, Button, Tag, Space, Spin, Empty, Typography, Badge } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import { SearchOutlined, ReloadOutlined, DesktopOutlined, ThunderboltOutlined, RightOutlined } from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import { safeNum } from '@/utils/format'
import { formatInTimezone } from '@/utils/timezone'
import useTranslation from '@/hooks/useTranslation'
import DeviceRealtimeModal from './DeviceRealtimeModal'

const { Text } = Typography

interface StationDevicesTabProps {
  stationId: number
  timezone: string
}

interface DeviceItem {
  id: string
  sn: string
  model: string
  model_id?: number
  model_category?: string
  rated_power?: number
  status: number | string
  last_online_at?: string
  firmware_version?: string
  firmware_dsp?: string
  firmware_bms?: string
  stationId?: string
  [key: string]: any
}

const StationDevicesTab: React.FC<StationDevicesTabProps> = ({ stationId, timezone }) => {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<string | undefined>(undefined)
  const [modalSn, setModalSn] = useState<string | null>(null)

  const { data: devices, isLoading, refetch } = useQuery({
    queryKey: ['station-devices-list', stationId],
    queryFn: () => deviceApi.getDevices({ station_id: stationId, page_size: 200 }).then(r => {
      const d = r.data?.data ?? r.data
      return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
    }),
    enabled: !!stationId,
  })

  const { data: realtimeData } = useQuery({
    queryKey: ['station-devices-rt', stationId],
    queryFn: async () => {
      const results: Record<string, any> = {}
      await Promise.allSettled(
        (devices ?? []).map(async (dev) => {
          try {
            const res = await deviceApi.getRealtime(dev.sn)
            results[dev.sn] = res.data?.data ?? res.data ?? {}
          } catch { /* ignore */ }
        }),
      )
      return results
    },
    enabled: !!devices?.length,
    refetchInterval: 15000,
  })

  const filteredDevices = useMemo(() => {
    if (!devices) return []
    return devices.filter(dev => {
      const matchSearch = !search
        || dev.sn.toLowerCase().includes(search.toLowerCase())
        || (dev.model ?? '').toLowerCase().includes(search.toLowerCase())
      const matchStatus = statusFilter === undefined
        || String(dev.status) === statusFilter
      return matchSearch && matchStatus
    })
  }, [devices, search, statusFilter])

  const getRealtimePower = (sn: string): number | null => {
    const env = realtimeData?.[sn]
    // 设备离线时 Redis 会回退到陈旧缓存，不得作为实时功率展示
    if (!env || env.online !== true) return null
    const rt = env?.realtime ?? env
    // 尝试多种字段路径（V2 使用 output_power，V1 使用 ac_power）
    const acPower = rt?.ac?.data?.power ?? rt?.output_power ?? rt?.ac_power ?? rt?.power
    const pvPower = rt?.pv?.data?.pv_total_power ?? rt?.pv_total_power
    return safeNum(acPower || pvPower) || null
  }

  const getDailyEnergy = (sn: string): number | null => {
    const env = realtimeData?.[sn]
    if (!env || env.online !== true) return null
    const rt = env?.realtime ?? env
    // V2 使用 daily_pv_energy，V1 使用 daily_pv / daily_energy / today_energy
    const dailyPV = safeNum(rt?.daily_pv_energy ?? rt?.daily_pv ?? rt?.daily_energy ?? rt?.today_energy ?? 0)
    return dailyPV > 0 ? dailyPV : null
  }

  const getCategoryType = (category: string): 'inv' | 'collector' | 'battery' => {
    if (category === 'battery') return 'battery'
    if (category === 'meter') return 'collector'
    return 'inv'
  }

  const deviceTypeConfig = {
    inv: { label: t('station.deviceTypeInverter'), color: 'purple' },
    collector: { label: t('station.deviceTypeCollector'), color: 'cyan' },
    battery: { label: t('station.deviceTypeStorage'), color: 'green' },
  }

  const getStatusCfg = (status: number | string) => {
    const key = String(status)
    return DEVICE_STATUS_MAP[key] ?? DEVICE_STATUS_MAP['0']
  }

  return (
    <>
      {/* 工具栏 */}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Space>
            <Input
              placeholder={t('station.searchSN')}
              prefix={<SearchOutlined />}
              allowClear
              value={search}
              onChange={e => setSearch(e.target.value)}
              style={{ width: 220 }}
              size="small"
            />
            <Select
              placeholder={t('station.deviceStatus')}
              allowClear
              style={{ width: 120 }}
              size="small"
              value={statusFilter}
              onChange={v => setStatusFilter(v)}
              options={[
                { label: t('station.onlineCount'), value: '1' },
                { label: t('station.offline'), value: '0' },
                { label: t('station.deviceFault'), value: '2' },
              ]}
            />
          </Space>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} size="small" onClick={() => refetch()}>{t('station.refresh')}</Button>
        </Col>
      </Row>

      <Spin spinning={isLoading}>
        {filteredDevices.length === 0 && !isLoading ? (
          <ProCard bordered={false} style={{ borderRadius: 12, textAlign: 'center', padding: '48px 24px' }}>
            <Empty description={t('station.noRelatedDevice')} />
          </ProCard>
        ) : (
          <Row gutter={[12, 12]}>
            {filteredDevices.map(dev => {
              const statusCfg = getStatusCfg(dev.status)
              const rtPower = getRealtimePower(dev.sn)
              const dailyEnergy = getDailyEnergy(dev.sn)
              const devType = getCategoryType(dev.model_category ?? '')
              const typeCfg = deviceTypeConfig[devType]
              const isOnline = dev.status === 1 || dev.status === 'online'
              const fw = dev.firmware_version || dev.firmware_dsp || '-'
              return (
                <Col xs={24} sm={12} md={8} key={dev.sn}>
                  <ProCard
                    hoverable
                    style={{ borderRadius: 12, cursor: 'pointer', height: '100%', border: '1px solid #e8e8e8' }}
                    bodyStyle={{ padding: '16px' }}
                    onClick={() => setModalSn(dev.sn)}
                  >
                    <Row justify="space-between" align="middle" style={{ marginBottom: 8 }}>
                      <Col>
                        <Text strong style={{ fontFamily: 'monospace', fontSize: 14 }}>{dev.sn}</Text>
                      </Col>
                      <Col>
                        <Badge
                          status={dev.status === 1 || dev.status === 'online' ? 'processing' : dev.status === 2 || dev.status === 'fault' ? 'error' : 'default'}
                        />
                        <Tag color={statusCfg.color} style={{ marginLeft: 4 }}>{statusCfg.label}</Tag>
                      </Col>
                    </Row>
                    <div style={{ marginBottom: 6 }}>
                      {!dev.model_id || dev.model_id === 0 ? (
                        <Tag color="orange">未绑定型号</Tag>
                      ) : (
                        <Tag color={typeCfg.color}>{typeCfg.label}</Tag>
                      )}
                      <Tag>{dev.model || '-'}</Tag>
                    </div>
                    <div style={{ fontSize: 12, color: '#999', marginBottom: 4 }}>
                      <DesktopOutlined /> {t('station.firmwareLabel')}: {fw}
                    </div>
                    <div style={{ fontSize: 12, color: '#999', marginBottom: 4 }}>
                      {t('station.lastOnline')}: {formatInTimezone(dev.last_online_at, timezone, 'MM-DD HH:mm:ss')}
                    </div>
                    <div style={{ marginTop: 8, borderTop: '1px solid #f0f0f0', paddingTop: 8 }}>
                      <Row gutter={8}>
                        <Col span={12}>
                          <div style={{ fontSize: 11, color: '#999' }}>{t('station.realtimePower')}</div>
                          <div style={{ fontSize: 14, fontWeight: 600, color: isOnline ? '#1677ff' : '#bbb' }}>
                            <ThunderboltOutlined style={{ marginRight: 4, fontSize: 12 }} />
                            {isOnline ? (rtPower !== null ? `${rtPower.toFixed(0)} W` : '0 W') : '--'}
                          </div>
                        </Col>
                        {devType === 'inv' && (
                          <Col span={12}>
                            <div style={{ fontSize: 11, color: '#999' }}>{t('station.dailyGeneration')}</div>
                            <div style={{ fontSize: 14, fontWeight: 600, color: dailyEnergy !== null ? '#f59e0b' : '#bbb' }}>
                              {dailyEnergy !== null ? `${dailyEnergy.toFixed(2)} kWh` : '--'}
                            </div>
                          </Col>
                        )}
                      </Row>
                    </div>
                    {/* 设备详情入口：跳转完整设备详情页（卡片其余区域点击弹实时数据 Modal） */}
                    <div style={{ marginTop: 8, textAlign: 'right', borderTop: '1px solid #f0f0f0', paddingTop: 8 }}>
                      <Button
                        type="link"
                        size="small"
                        icon={<RightOutlined />}
                        onClick={(e) => {
                          e.stopPropagation()
                          navigate(`/devices/${dev.sn}/detail`)
                        }}
                      >
                        {t('station.viewDeviceDetail')}
                      </Button>
                    </div>
                  </ProCard>
                </Col>
              )
            })}
          </Row>
        )}
      </Spin>

      <DeviceRealtimeModal
        open={!!modalSn}
        deviceSn={modalSn}
        onClose={() => setModalSn(null)}
      />
    </>
  )
}

export default StationDevicesTab
