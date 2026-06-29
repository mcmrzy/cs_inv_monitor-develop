import React, { useState, useMemo, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Card, Tabs, Form, InputNumber, Switch, Select, Slider, Button, Modal,
  message, Tag, Space, Row, Col, Typography, Spin, Empty, Tooltip,
} from 'antd'
import {
  SettingOutlined, SearchOutlined, SyncOutlined, ThunderboltOutlined,
  SafetyCertificateOutlined, SwapOutlined,
  ReloadOutlined, ExclamationCircleOutlined, UndoOutlined,
} from '@ant-design/icons'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import useTranslation from '@/hooks/useTranslation'

const { Title, Text } = Typography

/* ==================== 类型定义 ==================== */

interface DeviceItem {
  id: string
  sn: string
  model: string
  status: number
  last_online_at?: string
  [key: string]: any
}

/* ==================== 主组件 ==================== */

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const [form] = Form.useForm()
  const [selectedSn, setSelectedSn] = useState<string>('')
  const [activeTab, setActiveTab] = useState('general')
  const [searchKeyword, setSearchKeyword] = useState('')
  const [applying, setApplying] = useState(false)
  const [reading, setReading] = useState(false)

  /* ---------- 设备列表 ---------- */
  const { data: devicesData, isLoading: devicesLoading } = useQuery({
    queryKey: ['remote-settings', 'devices'],
    queryFn: () => deviceApi.getDevices({ pageSize: 9999 }).then((r) => {
      const d = r.data?.data ?? r.data
      return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
    }),
    staleTime: 30000,
  })

  const deviceList = useMemo(() => devicesData ?? [], [devicesData])

  const filteredDevices = useMemo(() => {
    if (!searchKeyword) return deviceList
    const kw = searchKeyword.toLowerCase()
    return deviceList.filter(
      (d) => d.sn?.toLowerCase().includes(kw) || d.model?.toLowerCase().includes(kw),
    )
  }, [deviceList, searchKeyword])

  const selectedDevice = deviceList.find((d) => d.sn === selectedSn)

  /* ---------- 读取当前值 ---------- */
  const handleReadParams = useCallback(async () => {
    if (!selectedSn) {
      message.warning(t('remote.pleaseSelectDeviceFirst'))
      return
    }
    setReading(true)
    try {
      const res = await deviceApi.sendCommand(selectedSn, { command: 'get_params' })
      const params = res.data?.data ?? res.data?.params ?? res.data ?? {}
      if (params && typeof params === 'object') {
        form.setFieldsValue(params)
        message.success(t('remote.readSuccess'))
      } else {
        message.info(t('remote.noValidParams'))
      }
    } catch {
      message.error(t('remote.readFailed'))
    } finally {
      setReading(false)
    }
  }, [selectedSn, form, t])

  /* ---------- 应用修改 ---------- */
  const handleApplyParams = useCallback(async () => {
    if (!selectedSn) {
      message.warning(t('remote.pleaseSelectDeviceFirst'))
      return
    }
    try {
      const values = await form.validateFields()
      setApplying(true)
      await deviceApi.sendCommand(selectedSn, { command: 'set_params', params: values })
      message.success(t('remote.setSuccess'))
    } catch (err: any) {
      if (err?.errorFields) {
        message.warning(t('remote.pleaseCheckForm'))
      } else {
        message.error(t('remote.setFailed'))
      }
    } finally {
      setApplying(false)
    }
  }, [selectedSn, form, t])

  /* ---------- 重置操作 ---------- */
  const showResetConfirm = useCallback((type: string, titleKey: string) => {
    if (!selectedSn) {
      message.warning(t('remote.pleaseSelectDeviceFirst'))
      return
    }
    const title = t(titleKey)
    Modal.confirm({
      title: t('remote.confirmTitle', { title }),
      icon: <ExclamationCircleOutlined />,
      content: t('remote.confirmContent', { sn: selectedSn, title }),
      okText: t('remote.confirmExecute'),
      cancelText: t('remote.cancel'),
      okType: 'danger',
      onOk: async () => {
        try {
          await deviceApi.sendCommand(selectedSn, { command: 'reset', params: { type } })
          message.success(t('remote.executeSuccess', { title }))
        } catch {
          message.error(t('remote.executeFailed', { title }))
        }
      },
    })
  }, [selectedSn, t])

  const sliderMarks = { 0: '0%', 25: '25%', 50: '50%', 75: '75%', 100: '100%' }
  const socSliderMarks = { 0: '0%', 10: '10%', 20: '20%', 50: '50%', 100: '100%' }

  /* ==================== Tab 1: 通用设置 ==================== */
  const renderGeneralSettings = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      <Row gutter={[24, 0]}>
        <Col xs={24} md={12}>
          <Form.Item name="time_sync" label={t('remote.timeSync')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="comm_address" label={t('remote.commAddress')}>
            <InputNumber style={{ width: '100%' }} min={1} max={247} placeholder={t('remote.placeholderCommAddress')} />
          </Form.Item>
          <Form.Item name="pv_wiring_mode" label={t('remote.pvWiringMode')}>
            <Select placeholder={t('remote.placeholderWiringMode')}>
              <Select.Option value="single_phase">{t('remote.singlePhase')}</Select.Option>
              <Select.Option value="two_phase">{t('remote.twoPhase')}</Select.Option>
              <Select.Option value="three_phase">{t('remote.threePhase')}</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="startup_pv_voltage" label={t('remote.startupPvVoltage')}>
            <InputNumber style={{ width: '100%' }} min={0} max={1000} step={0.1} suffix="V" placeholder={t('remote.placeholderStartupPvVoltage')} />
          </Form.Item>
          <Form.Item name="meter_type" label={t('remote.meterType')}>
            <Select placeholder={t('remote.placeholderMeterType')}>
              <Select.Option value="wireless">{t('remote.wireless')}</Select.Option>
              <Select.Option value="ct">{t('remote.ct')}</Select.Option>
            </Select>
          </Form.Item>
        </Col>
        <Col xs={24} md={12}>
          <Form.Item name="battery_type" label={t('remote.batteryType')}>
            <Select placeholder={t('remote.placeholderBatteryType')}>
              <Select.Option value="lead_acid">{t('remote.leadAcid')}</Select.Option>
              <Select.Option value="lithium_iron">{t('remote.lithiumIron')}</Select.Option>
              <Select.Option value="lithium_ternary">{t('remote.lithiumTernary')}</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="grid_standard" label={t('remote.gridStandard')}>
            <Select placeholder={t('remote.placeholderGridStandard')}>
              <Select.Option value="china">{t('remote.china')}</Select.Option>
              <Select.Option value="europe">{t('remote.europe')}</Select.Option>
              <Select.Option value="australia">{t('remote.australia')}</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="zero_ground_detection" label={t('remote.zeroGroundDetection')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="ct_ratio" label={t('remote.ctRatio')}>
            <InputNumber style={{ width: '100%' }} min={1} max={10000} placeholder={t('remote.placeholderCtRatio')} />
          </Form.Item>
          <Form.Item name="load_compensation" label={t('remote.loadCompensation')}>
            <InputNumber style={{ width: '100%' }} min={0} max={100000} suffix="W" placeholder={t('remote.placeholderLoadCompensation')} />
          </Form.Item>
        </Col>
      </Row>
    </Card>
  )

  /* ==================== Tab 2: 应用设置 ==================== */
  const renderAppSettings = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      <Row gutter={[24, 0]}>
        <Col xs={24} md={12}>
          <Form.Item name="offgrid_frequency" label={t('remote.offgridFrequency')}>
            <Select placeholder={t('remote.placeholderOffgridFrequency')}>
              <Select.Option value={50}>50 Hz</Select.Option>
              <Select.Option value={60}>60 Hz</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="offgrid_mode" label={t('remote.offgridMode')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="seamless_switching" label={t('remote.seamlessSwitching')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="microgrid" label={t('remote.microgrid')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="pv_offgrid_pct" label={t('remote.pvOffgridPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
        </Col>
        <Col xs={24} md={12}>
          <Form.Item name="gridtied_pct" label={t('remote.gridtiedPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="anti_backflow" label={t('remote.antiBackflow')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="system_type" label={t('remote.systemType')}>
            <Select placeholder={t('remote.placeholderSystemType')}>
              <Select.Option value="grid_tied">{t('remote.gridTied')}</Select.Option>
              <Select.Option value="off_grid">{t('remote.offGrid')}</Select.Option>
              <Select.Option value="hybrid">{t('remote.hybrid')}</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="ct_direction_reverse" label={t('remote.ctDirectionReverse')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="grid_max_input_power" label={t('remote.gridMaxInputPower')}>
            <InputNumber style={{ width: '100%' }} min={0} max={100000} suffix="W" placeholder={t('remote.placeholderGridMaxInputPower')} />
          </Form.Item>
        </Col>
      </Row>
    </Card>
  )

  /* ==================== Tab 3: 并网设置 ==================== */
  const renderGridSettings = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      <Row gutter={[24, 0]}>
        <Col xs={24} md={12}>
          <Form.Item name="connection_time" label={t('remote.connectionTime')}>
            <InputNumber style={{ width: '100%' }} min={0} max={600} suffix="s" placeholder={t('remote.placeholderConnectionTime')} />
          </Form.Item>
          <Form.Item label={t('remote.voltageLimit')}>
            <Space>
              <Form.Item name="voltage_upper_limit" noStyle>
                <InputNumber min={0} max={500} step={0.1} suffix="V" placeholder={t('common.up')} style={{ width: 140 }} />
              </Form.Item>
              <Text type="secondary">/</Text>
              <Form.Item name="voltage_lower_limit" noStyle>
                <InputNumber min={0} max={500} step={0.1} suffix="V" placeholder={t('common.down')} style={{ width: 140 }} />
              </Form.Item>
            </Space>
          </Form.Item>
          <Form.Item label={t('remote.freqLimit')}>
            <Space>
              <Form.Item name="freq_upper_limit" noStyle>
                <InputNumber min={40} max={70} step={0.01} suffix="Hz" placeholder={t('common.up')} style={{ width: 140 }} />
              </Form.Item>
              <Text type="secondary">/</Text>
              <Form.Item name="freq_lower_limit" noStyle>
                <InputNumber min={40} max={70} step={0.01} suffix="Hz" placeholder={t('common.down')} style={{ width: 140 }} />
              </Form.Item>
            </Space>
          </Form.Item>
          <Form.Item name="over_freq_load_reduction" label={t('remote.overFreqLoadReduction')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
        </Col>
        <Col xs={24} md={12}>
          <Form.Item name="reactive_power_mode" label={t('remote.reactivePowerMode')}>
            <Select placeholder={t('remote.placeholderReactivePowerMode')}>
              <Select.Option value="constant_pf">{t('remote.constantPf')}</Select.Option>
              <Select.Option value="constant_q">{t('remote.constantQ')}</Select.Option>
              <Select.Option value="cosphi_p">CosPhi(P)</Select.Option>
              <Select.Option value="q_u">Q(U)</Select.Option>
            </Select>
          </Form.Item>
          <Form.Item name="pf_setting" label={t('remote.pfSetting')}>
            <InputNumber style={{ width: '100%' }} min={-1} max={1} step={0.01} placeholder={t('remote.placeholderPfSetting')} />
          </Form.Item>
          <Form.Item name="active_power_pct" label={t('remote.activePowerPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="protection_level" label={t('remote.protectionLevel')}>
            <Select placeholder={t('remote.placeholderProtectionLevel')}>
              <Select.Option value={1}>{t('remote.level')} 1</Select.Option>
              <Select.Option value={2}>{t('remote.level')} 2</Select.Option>
              <Select.Option value={3}>{t('remote.level')} 3</Select.Option>
            </Select>
          </Form.Item>
        </Col>
      </Row>
    </Card>
  )

  /* ==================== Tab 4: 充电设置 ==================== */
  const renderChargeSettings = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      <Row gutter={[24, 0]}>
        <Col xs={24} md={12}>
          <Form.Item name="charge_control" label={t('remote.chargeControl')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="charge_power_pct" label={t('remote.chargePowerPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="balanced_charge_voltage" label={t('remote.balancedChargeVoltage')}>
            <InputNumber style={{ width: '100%' }} min={0} max={100} step={0.1} suffix="V" placeholder={t('remote.placeholderBalancedChargeVoltage')} />
          </Form.Item>
          <Form.Item name="charge_current_limit" label={t('remote.chargeCurrentLimit')}>
            <InputNumber style={{ width: '100%' }} min={0} max={500} step={0.1} suffix="A" placeholder={t('remote.placeholderChargeCurrentLimit')} />
          </Form.Item>
        </Col>
        <Col xs={24} md={12}>
          <Form.Item name="soc_limit" label={t('remote.socLimit')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="ac_charge_enable" label={t('remote.acChargeEnable')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="ac_charge_power_pct" label={t('remote.acChargePowerPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="battery_priority" label={t('remote.batteryPriority')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
        </Col>
      </Row>
    </Card>
  )

  /* ==================== Tab 5: 放电设置 ==================== */
  const renderDischargeSettings = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      <Row gutter={[24, 0]}>
        <Col xs={24} md={12}>
          <Form.Item name="discharge_power_pct" label={t('remote.dischargePowerPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="gridtied_cutoff_soc" label={t('remote.gridtiedCutoffSoc')}>
            <Slider min={0} max={100} marks={socSliderMarks} />
          </Form.Item>
          <Form.Item name="offgrid_cutoff_soc" label={t('remote.offgridCutoffSoc')}>
            <Slider min={0} max={100} marks={socSliderMarks} />
          </Form.Item>
        </Col>
        <Col xs={24} md={12}>
          <Form.Item name="forced_discharge" label={t('remote.forcedDischarge')} valuePropName="checked">
            <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
          </Form.Item>
          <Form.Item name="forced_discharge_power_pct" label={t('remote.forcedDischargePowerPct')}>
            <Slider min={0} max={100} marks={sliderMarks} />
          </Form.Item>
          <Form.Item name="discharge_current_limit" label={t('remote.dischargeCurrentLimit')}>
            <InputNumber style={{ width: '100%' }} min={0} max={500} step={0.1} suffix="A" placeholder={t('remote.placeholderDischargeCurrentLimit')} />
          </Form.Item>
        </Col>
      </Row>
    </Card>
  )

  /* ==================== Tab 6: 重置操作 ==================== */
  const renderResetOperations = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      <div style={{ textAlign: 'center', padding: '24px 0' }}>
        <Row gutter={[24, 24]} justify="center">
          <Col xs={24} sm={8}>
            <Card
              hoverable
              style={{ borderRadius: 12, textAlign: 'center' }}
              styles={{ body: { padding: '32px 16px' } }}
            >
              <UndoOutlined style={{ fontSize: 36, color: '#ff4d4f', marginBottom: 16 }} />
              <Title level={5}>{t('remote.resetAll')}</Title>
              <Text type="secondary" style={{ display: 'block', marginBottom: 16 }}>
                {t('remote.resetAllDesc')}
              </Text>
              <Button
                danger
                type="primary"
                block
                onClick={() => showResetConfirm('all', 'remote.resetAll')}
                disabled={!selectedSn}
              >
                {t('remote.executeResetAll')}
              </Button>
            </Card>
          </Col>
          <Col xs={24} sm={8}>
            <Card
              hoverable
              style={{ borderRadius: 12, textAlign: 'center' }}
              styles={{ body: { padding: '32px 16px' } }}
            >
              <SwapOutlined style={{ fontSize: 36, color: '#fa8c16', marginBottom: 16 }} />
              <Title level={5}>{t('remote.resetCharge')}</Title>
              <Text type="secondary" style={{ display: 'block', marginBottom: 16 }}>
                {t('remote.resetChargeDesc')}
              </Text>
              <Button
                danger
                block
                onClick={() => showResetConfirm('charge', 'remote.resetCharge')}
                disabled={!selectedSn}
              >
                {t('remote.executeResetCharge')}
              </Button>
            </Card>
          </Col>
          <Col xs={24} sm={8}>
            <Card
              hoverable
              style={{ borderRadius: 12, textAlign: 'center' }}
              styles={{ body: { padding: '32px 16px' } }}
            >
              <ThunderboltOutlined style={{ fontSize: 36, color: '#722ed1', marginBottom: 16 }} />
              <Title level={5}>{t('remote.resetDischarge')}</Title>
              <Text type="secondary" style={{ display: 'block', marginBottom: 16 }}>
                {t('remote.resetDischargeDesc')}
              </Text>
              <Button
                danger
                block
                onClick={() => showResetConfirm('discharge', 'remote.resetDischarge')}
                disabled={!selectedSn}
              >
                {t('remote.executeResetDischarge')}
              </Button>
            </Card>
          </Col>
        </Row>
      </div>
    </Card>
  )

  /* ==================== Tab 配置 ==================== */

  const tabItems = [
    { key: 'general', label: <span><SettingOutlined /> {t('remote.generalSettings')}</span>, children: renderGeneralSettings() },
    { key: 'app', label: <span><ThunderboltOutlined /> {t('remote.appSettings')}</span>, children: renderAppSettings() },
    { key: 'grid', label: <span><SyncOutlined /> {t('remote.gridSettings')}</span>, children: renderGridSettings() },
    { key: 'charge', label: <span><SwapOutlined /> {t('remote.chargeSettings')}</span>, children: renderChargeSettings() },
    { key: 'discharge', label: <span><ThunderboltOutlined /> {t('remote.dischargeSettings')}</span>, children: renderDischargeSettings() },
    { key: 'reset', label: <span><ExclamationCircleOutlined /> {t('remote.resetOps')}</span>, children: renderResetOperations() },
  ]

  /* ==================== 渲染 ==================== */

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Col>
          <Title level={4} style={{ margin: 0 }}>
            <SafetyCertificateOutlined style={{ marginRight: 8 }} />
            {t('remote.title')}
          </Title>
        </Col>
      </Row>

      {/* 设备选择器 */}
      <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
        <Row gutter={[16, 12]} align="middle">
          <Col xs={24} sm={12} md={8} lg={6}>
            <Text strong style={{ display: 'block', marginBottom: 4 }}>{t('remote.selectDevice')}:</Text>
            <Select
              showSearch
              optionFilterProp="label"
              placeholder={t('remote.searchDevice')}
              style={{ width: '100%' }}
              value={selectedSn || undefined}
              onChange={(v) => setSelectedSn(v)}
              allowClear
              onSearch={setSearchKeyword}
              filterOption={false}
              loading={devicesLoading}
              notFoundContent={devicesLoading ? <Spin size="small" /> : <Empty description={t('common.noMatch')} />}
              options={filteredDevices.map((d) => {
                const statusCfg = DEVICE_STATUS_MAP[d.status] ?? DEVICE_STATUS_MAP[0]
                return {
                  label: (
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <span>{d.sn} {d.model ? `(${d.model})` : ''}</span>
                      <span style={{ fontSize: 12, color: statusCfg.color }}>{statusCfg.label}</span>
                    </div>
                  ),
                  value: d.sn,
                }
              })}
            />
          </Col>
          {selectedDevice && (
            <Col>
              <Space split={<span style={{ color: '#d9d9d9' }}>|</span>}>
                <Text strong>SN: {selectedDevice.sn}</Text>
                {selectedDevice.model && <Text type="secondary">{t('remote.model')}: {selectedDevice.model}</Text>}
                <Tag
                  color={DEVICE_STATUS_MAP[selectedDevice.status]?.color ?? '#d9d9d9'}
                >
                  {DEVICE_STATUS_MAP[selectedDevice.status]?.label ?? t('remote.unknown')}
                </Tag>
                {selectedDevice.last_online_at && (
                  <Tooltip title={t('remote.lastCommunication')}>
                    <Text type="secondary" style={{ fontSize: 12 }}>
                      {t('remote.lastOnline')}: {selectedDevice.last_online_at}
                    </Text>
                  </Tooltip>
                )}
              </Space>
            </Col>
          )}
        </Row>
      </Card>

      {!selectedSn ? (
        <Card bordered={false} style={{ borderRadius: 12, padding: 60 }}>
          <Empty description={t('remote.pleaseSelectDevice')} />
        </Card>
      ) : (
        <>
          <Form form={form} layout="vertical">
            <Tabs
              activeKey={activeTab}
              onChange={setActiveTab}
              items={tabItems}
              size="large"
            />
          </Form>

          {/* 底部操作栏 */}
          <Card
            bordered={false}
            style={{
              borderRadius: 12,
              position: 'sticky',
              bottom: 0,
              zIndex: 10,
              boxShadow: '0 -4px 12px rgba(0,0,0,0.08)',
            }}
          >
            <Row justify="end">
              <Space size="middle">
                <Button
                  icon={<ReloadOutlined />}
                  loading={reading}
                  onClick={handleReadParams}
                  size="large"
                >
                  {t('remote.readCurrent')}
                </Button>
                <Button
                  type="primary"
                  loading={applying}
                  onClick={handleApplyParams}
                  size="large"
                >
                  {t('remote.applyModify')}
                </Button>
              </Space>
            </Row>
          </Card>
        </>
      )}
    </div>
  )
}

export default RemoteSettingsPage
