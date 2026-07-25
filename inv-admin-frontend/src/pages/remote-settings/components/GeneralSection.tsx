import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, DatePicker, App, Typography, Modal, Button, Tooltip } from 'antd'
import { ExclamationCircleOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import { FieldRow, SwitchField, SettingButton, SubGroupTitle, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography

interface Props {
  deviceInfo: any
}

const GeneralSection: React.FC<Props> = ({ deviceInfo }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()

  /* ── 下拉选项常量 (移到组件内以使用 t()) ── */
  const METER_TYPE_OPTIONS = [
    { value: 0, label: t('remote.meterSinglePhase') },
    { value: 1, label: t('remote.meterThreePhase') },
  ]

  const DETECTION_METHOD_OPTIONS = [
    { value: 0, label: t('remote.noUse') },
    { value: 1, label: 'CT' },
    { value: 2, label: t('remote.meterDetection') },
  ]

  const REGULATION_OPTIONS = [
    { value: 0, label: 'VDE0126' },
    { value: 1, label: 'AS4777' },
    { value: 2, label: 'G99' },
    { value: 3, label: 'CQC' },
    { value: 4, label: 'EN50549' },
    { value: 5, label: 'IEC61727' },
    { value: 6, label: t('remote.southAfrica') },
    { value: 7, label: t('remote.brazil') },
    { value: 8, label: t('remote.thailand') },
    { value: 9, label: t('remote.philippines') },
  ]

  const PV_WIRING_OPTIONS = [
    { value: 0, label: t('remote.dcSourceMode') },
    { value: 3, label: t('remote.twoMpptSame') },
    { value: 4, label: t('remote.twoMpptDifferent') },
  ]

  const BATTERY_TYPE_OPTIONS = [
    { value: 0, label: t('remote.noBattery') },
    { value: 1, label: t('remote.leadAcidBattery') },
    { value: 2, label: t('remote.lithiumBattery') },
  ]

  // 铅酸电池容量: 0=50Ah … 30=1550Ah, 31=自定义
  const LEAD_ACID_OPTIONS = Array.from({ length: 31 }, (_, i) => ({
    value: i,
    label: `${(i + 1) * 50}Ah`,
  })).concat([{ value: 31, label: t('remote.customCapacitySet') }])

  const LITHIUM_TYPE_OPTIONS = [
    { value: 0, label: t('remote.standardBattery') },
    { value: 1, label: 'HINA' },
    { value: 2, label: 'Pylon/' + t('remote.lithiumBrands') },
    { value: 3, label: 'Enopte' },
    { value: 4, label: 'MSUN' },
    { value: 5, label: 'GSL1' },
    { value: 6, label: 'Luxpower' },
    { value: 7, label: 'Aobo' },
    { value: 8, label: 'Rsvd' },
    { value: 9, label: 'Stealth' },
    { value: 10, label: 'TeLongMei' },
    { value: 11, label: 'Merit' },
    { value: 14, label: 'WECO' },
    { value: 15, label: t('remote.murata') },
    { value: 16, label: 'BITEK' },
    { value: 17, label: 'OKSolar' },
    { value: 18, label: t('remote.gwBattery') },
    { value: 19, label: 'CROWN' },
    { value: 20, label: 'Revov' },
    { value: 21, label: 'Beebeejump' },
  ]

  const CT_RATIO_OPTIONS = [
    { value: 0, label: '100:100A' },
    { value: 1, label: '200:200A' },
    { value: 2, label: '400:400A' },
    { value: 3, label: '600:600A' },
    { value: 4, label: '1000:1000A' },
  ]

  /* ── Tooltip 常量 (移到组件内以使用 t()) ── */
  const TIPS = {
    time: t('remote.tipTime'),
    pvWiring: t('remote.tipPvWiring'),
    batteryType: t('remote.tipBatteryType'),
    leadAcidType: t('remote.tipLeadAcidType'),
    customCapacity: t('remote.tipCustomCapacity'),
    lithiumType: t('remote.tipLithiumType'),
    ecoMode: t('remote.tipEcoMode'),
    standby: t('remote.tipStandby'),
    batteryEco: t('remote.tipBatteryEco'),
    restart: t('remote.tipRestart'),
    buzzer: t('remote.tipBuzzer'),
    ctRatio: t('remote.tipCtRatio'),
    ctReverse: t('remote.tipCtReverse'),
    isoEnable: t('remote.tipIsoEnable'),
  }

  const [time, setTime] = useState<any>(null)
  const [pvWiring, setPvWiring] = useState<number>(0)
  const [batteryType, setBatteryType] = useState<number>(0)
  const [leadAcidType, setLeadAcidType] = useState<number>(0)
  const [lithiumType, setLithiumType] = useState<number>(0)
  const [customCapacity, setCustomCapacity] = useState<number>(100)
  const [ctRatio, setCtRatio] = useState<number>(0)
  const [ctReverse, setCtReverse] = useState(false)
  const [isoEnable, setIsoEnable] = useState(false)
  const [ecoMode, setEcoMode] = useState(false)
  const [standby, setStandby] = useState(true)
  const [batteryEco, setBatteryEco] = useState(false)
  const [buzzer, setBuzzer] = useState(true)

  /* ── 型号信息字段状态 ── */
  const [commAddress, setCommAddress] = useState<number>(1)
  const [startPvVoltage, setStartPvVoltage] = useState<number>(100)
  const [meterType, setMeterType] = useState<number>(0)
  const [detectionMethod, setDetectionMethod] = useState<number>(1)
  const [regulation, setRegulation] = useState<number>(0)
  const [zeroGroundDetect, setZeroGroundDetect] = useState(false)
  const [totalLoadCompensation, setTotalLoadCompensation] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(t('remote.executeSuccess', { title: fieldName }))
  }

  const isLeadAcid = batteryType === 1
  const isLithium = batteryType === 2
  const isCustomCapacity = leadAcidType === 31


  return (
    <Row gutter={[16, 8]}>
      {/* ── 型号信息子分组 ── */}
      <SubGroupTitle title={t('remote.modelInfo')} color="#4f6ef7" />

      {/* 通讯地址 */}
      <FieldRow label={t('remote.commAddress')}>
        <InputNumber value={commAddress} onChange={(v) => setCommAddress(v ?? 1)} min={1} max={255} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.commAddress'))} />
      </FieldRow>

      {/* 开始光伏电压 */}
      <FieldRow label={`${t('remote.startPvVoltage')}(V)`}>
        <InputNumber value={startPvVoltage} onChange={(v) => setStartPvVoltage(v ?? 100)} min={0} max={600} style={{ width: 140 }} />
        <SettingButton onClick={() => handleSet(t('remote.startPvVoltage'))} />
      </FieldRow>

      {/* 检测方式 */}
      <FieldRow label={t('remote.detectionMethod')}>
        <Select value={detectionMethod} onChange={setDetectionMethod} style={{ width: 160 }} options={DETECTION_METHOD_OPTIONS} />
        <SettingButton onClick={() => handleSet(t('remote.detectionMethod'))} />
      </FieldRow>

      {/* 电表类型 - 仅检测方式为电表时显示 */}
      {detectionMethod === 2 && (
        <FieldRow label={t('remote.meterType')}>
          <Select value={meterType} onChange={setMeterType} style={{ width: 160 }} options={METER_TYPE_OPTIONS} />
          <SettingButton onClick={() => handleSet(t('remote.meterType'))} />
        </FieldRow>
      )}

      {/* 法规 */}
      <FieldRow label={t('remote.regulation')}>
        <Select value={regulation} onChange={setRegulation} style={{ width: 160 }} options={REGULATION_OPTIONS} />
        <SettingButton onClick={() => handleSet(t('remote.regulation'))} />
      </FieldRow>

      {/* 零地检测使能 */}
      <SwitchField label={t('remote.zeroGroundDetectEnable')} checked={zeroGroundDetect} onChange={(v) => { setZeroGroundDetect(v); handleSet(t('remote.zeroGroundDetectEnable')) }} />

      {/* 总负载补偿 */}
      <SwitchField label={t('remote.loadCompensation')} checked={totalLoadCompensation} onChange={(v) => { setTotalLoadCompensation(v); handleSet(t('remote.loadCompensation')) }} tooltip={t('remote.loadCompensationTip')} />

      {/* 型号（只读） */}
      <FieldRow label={t('remote.model')}>
        <Text strong>{deviceInfo?.model || deviceInfo?.device_type || '-'}</Text>
      </FieldRow>

      {/* 时间 */}
      <FieldRow label={t('remote.time')} tooltip={TIPS.time}>
        <DatePicker showTime value={time} onChange={setTime} style={{ width: 200 }} />
        <SettingButton onClick={() => handleSet(t('remote.time'))} />
      </FieldRow>

      {/* PV接线方式 */}
      <FieldRow label={t('remote.pvWiringMode')} tooltip={TIPS.pvWiring}>
        <Select value={pvWiring} onChange={setPvWiring} style={{ width: 260 }} options={PV_WIRING_OPTIONS} />
        <SettingButton onClick={() => handleSet(t('remote.pvWiringMode'))} />
      </FieldRow>

      {/* 电池类型 */}
      <FieldRow label={t('remote.batteryType')} tooltip={TIPS.batteryType}>
        <Select value={batteryType} onChange={setBatteryType} style={{ width: 160 }} options={BATTERY_TYPE_OPTIONS} />
        <SettingButton onClick={() => handleSet(t('remote.batteryType'))} />
      </FieldRow>

      {/* 铅酸电池类型 - 仅铅酸时显示 */}
      {isLeadAcid && (
        <FieldRow label={t('remote.leadAcidType')} tooltip={TIPS.leadAcidType}>
          <Select value={leadAcidType} onChange={setLeadAcidType} style={{ width: 160 }} options={LEAD_ACID_OPTIONS} />
          <SettingButton onClick={() => handleSet(t('remote.leadAcidType'))} />
        </FieldRow>
      )}

      {/* 自定义容量 - 仅铅酸且自定义时显示 */}
      {isLeadAcid && isCustomCapacity && (
        <FieldRow label={`${t('remote.customCapacity')}(Ah)`} tooltip={TIPS.customCapacity}>
          <InputNumber
            value={customCapacity}
            onChange={(v) => setCustomCapacity(v ?? 100)}
            min={1}
            max={65535}
            style={{ width: 140 }}
          />
          <SettingButton onClick={() => handleSet(t('remote.customCapacity'))} />
        </FieldRow>
      )}

      {/* 锂电池类型 - 仅锂电时显示 */}
      {isLithium && (
        <FieldRow label={t('remote.lithiumType')} tooltip={TIPS.lithiumType}>
          <Select value={lithiumType} onChange={setLithiumType} style={{ width: 300 }} options={LITHIUM_TYPE_OPTIONS} />
          <SettingButton onClick={() => handleSet(t('remote.lithiumType'))} />
        </FieldRow>
      )}

      {/* 没有电池时的灰色提示 */}
      {batteryType === 0 && (
        <Col span={24}>
          <div style={{ padding: '12px 0', color: '#bbb', fontSize: 13 }}>
            {t('remote.selectBatteryTypeHint')}
          </div>
        </Col>
      )}

      {/* CT采样比 */}
      <FieldRow label={t('remote.ctRatio')} tooltip={TIPS.ctRatio}>
        <Select value={ctRatio} onChange={setCtRatio} style={{ width: 160 }} options={CT_RATIO_OPTIONS} />
        <SettingButton onClick={() => handleSet(t('remote.ctRatio'))} />
      </FieldRow>

      {/* 开关类字段 */}
      <SwitchField label={t('remote.ctDirectionReverse')} checked={ctReverse} onChange={(v) => { setCtReverse(v); handleSet(t('remote.ctDirectionReverse')) }} tooltip={TIPS.ctReverse} />
      <SwitchField label={t('remote.isoEnable')} checked={isoEnable} onChange={(v) => { setIsoEnable(v); handleSet(t('remote.isoEnable')) }} tooltip={TIPS.isoEnable} />
      <SwitchField label={t('remote.ecoMode')} checked={ecoMode} onChange={(v) => { setEcoMode(v); handleSet(t('remote.ecoMode')) }} tooltip={TIPS.ecoMode} />
      <SwitchField label={t('remote.standby')} checked={standby} onChange={(v) => { setStandby(v); handleSet(t('remote.standby')) }} enableText={t('remote.powerOn')} disableText={t('remote.standbyMode')} tooltip={TIPS.standby} />
      <SwitchField label={t('remote.batteryEcoMode')} checked={batteryEco} onChange={(v) => { setBatteryEco(v); handleSet(t('remote.batteryEcoMode')) }} tooltip={TIPS.batteryEco} />
      <SwitchField label={t('remote.buzzerEnable')} checked={buzzer} onChange={(v) => { setBuzzer(v); handleSet(t('remote.buzzerEnable')) }} tooltip={TIPS.buzzer} />

      {/* 重启逆变器 */}
      <Col span={24}>
        <div style={{ ...fieldRowStyle, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Text style={{ ...labelStyle, marginBottom: 0, flexShrink: 0, marginRight: 12 }}>
            {t('remote.restartInverter')}
            <Tooltip title={TIPS.restart} overlayStyle={{ maxWidth: 360 }}>
              <ExclamationCircleOutlined style={{ marginLeft: 4, color: '#faad14', cursor: 'help', fontSize: 13 }} />
            </Tooltip>
          </Text>
          <Button
            danger
            size="small"
            onClick={() => {
              Modal.confirm({
                title: t('remote.confirmRestartInverter'),
                icon: <ExclamationCircleOutlined />,
                content: t('remote.restartConfirmContent'),
                okText: t('remote.confirmExecute'),
                okType: 'danger',
                cancelText: t('remote.cancel'),
                onOk: () => message.success(t('remote.executeSuccess', { title: t('remote.restartInverter') })),
              })
            }}
          >
            {t('remote.restart')}
          </Button>
        </div>
      </Col>
    </Row>
  )
}

export default GeneralSection
