import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, DatePicker, App, Typography, Modal, Button, Tooltip } from 'antd'
import { ExclamationCircleOutlined } from '@ant-design/icons'
import { FieldRow, SwitchField, SettingButton, SubGroupTitle, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography

interface Props {
  deviceInfo: any
}

/* ── 下拉选项常量 ── */
const PV_WIRING_OPTIONS = [
  { value: 0, label: '直流源模式' },
  { value: 3, label: '两个MPPT连接到同一串' },
  { value: 4, label: '两个MPPT连接到不同串' },
]

const BATTERY_TYPE_OPTIONS = [
  { value: 0, label: '没有电池' },
  { value: 1, label: '铅酸电池' },
  { value: 2, label: '锂电池' },
]

// 铅酸电池容量: 0=50Ah … 30=1550Ah, 31=自定义
const LEAD_ACID_OPTIONS = Array.from({ length: 31 }, (_, i) => ({
  value: i,
  label: `${(i + 1) * 50}Ah`,
})).concat([{ value: 31, label: '自定义容量设置' }])

const LITHIUM_TYPE_OPTIONS = [
  { value: 0, label: '标准电池' },
  { value: 1, label: 'HINA' },
  { value: 2, label: 'Pylon/自由胜利/太阳MD/哈勃/蓝色新星' },
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
  { value: 15, label: '村田' },
  { value: 16, label: 'BITEK' },
  { value: 17, label: 'OKSolar' },
  { value: 18, label: 'GW电池' },
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

/* ── Tooltip 常量 ── */
const TIPS = {
  time: '当逆变器在线时，时间基于设定的时区。请前往配置/站点/站点管理/编辑页面设置时区和夏令时。yyyy-MM-dd HH:mm:ss',
  pvWiring: '这使用户能够选择逆变器的光伏来源。这可以是：0：直流源模式，3：两个MPPT连接到同一串，或4：两个MPPT连接到不同的串。',
  batteryType: '逆变器支持铅酸和锂电池选项，使用前请查询逆变器与锂电池之间的兼容性。',
  leadAcidType: '为铅酸电池组选择您的总电池容量。',
  customCapacity: '定制铅酸电池容量设置(1-65535)',
  lithiumType: '此设置允许用户从兼容电池列表中选择用于闭环通信的电池。',
  ecoMode: '当绿色功能启用时，如果EPS负载读数在10分钟内低于60W，则EPS输出将被切断。',
  standby: '设置为正常：逆变器正常工作。设置为待机：逆变器将停止电源输入和输出并进入待机模式。设置为正常或重启逆变器将恢复为\'设置为标准\'。',
  batteryEco: '如果启用：1：当电池达到并网EOD值且交流充电被禁用时，逆变器将切换到旁路模式，直到电池再次充电。2：切换时间可以达到15毫秒。',
  restart: '这将重启逆变器。',
  buzzer: '启用/禁用警报蜂鸣器。',
  ctRatio: '正在使用的CT的采样比率。',
  ctReverse: '用于反转CT的方向，以防它们安装错误。',
  isoEnable: '启用/禁用光伏接地故障断路器。',
}

const GeneralSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()

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

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  const isLeadAcid = batteryType === 1
  const isLithium = batteryType === 2
  const isCustomCapacity = leadAcidType === 31

  return (
    <Row gutter={[16, 8]}>
      {/* 型号（只读） */}
      <FieldRow label="型号">
        <Text strong>{deviceInfo?.model || deviceInfo?.device_type || '-'}</Text>
      </FieldRow>

      {/* 时间 */}
      <FieldRow label="时间" tooltip={TIPS.time}>
        <DatePicker showTime value={time} onChange={setTime} style={{ width: 200 }} />
        <SettingButton onClick={() => handleSet('时间')} />
      </FieldRow>

      {/* PV接线方式 */}
      <FieldRow label="PV接线方式" tooltip={TIPS.pvWiring}>
        <Select value={pvWiring} onChange={setPvWiring} style={{ width: 260 }} options={PV_WIRING_OPTIONS} />
        <SettingButton onClick={() => handleSet('PV接线方式')} />
      </FieldRow>

      {/* 电池类型 */}
      <FieldRow label="电池类型" tooltip={TIPS.batteryType}>
        <Select value={batteryType} onChange={setBatteryType} style={{ width: 160 }} options={BATTERY_TYPE_OPTIONS} />
        <SettingButton onClick={() => handleSet('电池类型')} />
      </FieldRow>

      {/* 铅酸电池类型 - batteryType=1 时显示 */}
      {isLeadAcid && (
        <>
          <FieldRow label="铅酸电池类型" tooltip={TIPS.leadAcidType}>
            <Select value={leadAcidType} onChange={setLeadAcidType} style={{ width: 160 }} options={LEAD_ACID_OPTIONS} />
            <SettingButton onClick={() => handleSet('铅酸电池类型')} />
          </FieldRow>
          {isCustomCapacity && (
            <FieldRow label="自定义容量(Ah)" tooltip={TIPS.customCapacity}>
              <InputNumber
                value={customCapacity}
                onChange={(v) => setCustomCapacity(v ?? 100)}
                min={1}
                max={65535}
                style={{ width: 140 }}
              />
              <SettingButton onClick={() => handleSet('自定义容量')} />
            </FieldRow>
          )}
        </>
      )}

      {/* 锂电池类型 - batteryType=2 时显示 */}
      {isLithium && (
        <FieldRow label="锂电池类型" tooltip={TIPS.lithiumType}>
          <Select value={lithiumType} onChange={setLithiumType} style={{ width: 300 }} options={LITHIUM_TYPE_OPTIONS} />
          <SettingButton onClick={() => handleSet('锂电池类型')} />
        </FieldRow>
      )}

      {/* CT采样比 */}
      <FieldRow label="CT采样比" tooltip={TIPS.ctRatio}>
        <Select value={ctRatio} onChange={setCtRatio} style={{ width: 160 }} options={CT_RATIO_OPTIONS} />
        <SettingButton onClick={() => handleSet('CT采样比')} />
      </FieldRow>

      {/* 开关类字段 */}
      <SwitchField label="反转CT方向" checked={ctReverse} onChange={(v) => { setCtReverse(v); handleSet('反转CT方向') }} tooltip={TIPS.ctReverse} />
      <SwitchField label="ISO使能" checked={isoEnable} onChange={(v) => { setIsoEnable(v); handleSet('ISO使能') }} tooltip={TIPS.isoEnable} />
      <SwitchField label="节能模式" checked={ecoMode} onChange={(v) => { setEcoMode(v); handleSet('节能模式') }} tooltip={TIPS.ecoMode} />
      <SwitchField label="开机/待机" checked={standby} onChange={(v) => { setStandby(v); handleSet('开机/待机') }} enableText="开机" disableText="待机" tooltip={TIPS.standby} />
      <SwitchField label="电池节能模式" checked={batteryEco} onChange={(v) => { setBatteryEco(v); handleSet('电池节能模式') }} tooltip={TIPS.batteryEco} />
      <SwitchField label="蜂鸣器启用" checked={buzzer} onChange={(v) => { setBuzzer(v); handleSet('蜂鸣器启用') }} tooltip={TIPS.buzzer} />

      {/* 重启逆变器 */}
      <Col span={12}>
        <div style={fieldRowStyle}>
          <Text style={labelStyle}>
            重启逆变器
            <Tooltip title={TIPS.restart} overlayStyle={{ maxWidth: 360 }}>
              <ExclamationCircleOutlined style={{ marginLeft: 4, color: '#faad14', cursor: 'help', fontSize: 13 }} />
            </Tooltip>
          </Text>
          <Button
            danger
            size="small"
            onClick={() => {
              Modal.confirm({
                title: '确认重启逆变器',
                icon: <ExclamationCircleOutlined />,
                content: '确定要重启逆变器吗？重启期间设备将停止工作。',
                okText: '确认执行',
                okType: 'danger',
                cancelText: '取消',
                onOk: () => message.success('重启逆变器命令已发送'),
              })
            }}
          >
            重启
          </Button>
        </div>
      </Col>
    </Row>
  )
}

export default GeneralSection
