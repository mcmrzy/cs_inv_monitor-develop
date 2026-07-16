import React, { useState } from 'react'
import { Row, Col, Select, InputNumber, DatePicker, App, Typography, Modal, Button } from 'antd'
import { ExclamationCircleOutlined } from '@ant-design/icons'
import { FieldRow, SwitchField, SettingButton, PRIMARY, labelStyle, fieldRowStyle } from './shared-styles'

const { Text } = Typography
const { Option } = Select

interface Props {
  deviceInfo: any
}

const GeneralSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()

  const [time, setTime] = useState<any>(null)
  const [pvWiring, setPvWiring] = useState('independent')
  const [batteryType, setBatteryType] = useState('lifepo4')
  const [leadAcidType, setLeadAcidType] = useState('flooded')
  const [lithiumType, setLithiumType] = useState('lifepo4')
  const [regulation, setRegulation] = useState('china')
  const [ecoMode, setEcoMode] = useState(false)
  const [standby, setStandby] = useState(true)
  const [batteryEco, setBatteryEco] = useState(false)
  const [buzzer, setBuzzer] = useState(true)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 指令已下发`)
  }

  const isLeadAcid = batteryType === 'lead_acid'
  const isLithium = batteryType === 'lifepo4' || batteryType === 'ncm' || batteryType === 'other'

  return (
    <Row gutter={[16, 8]}>
      {/* 型号（只读） */}
      <FieldRow label="型号">
        <Text strong>{deviceInfo?.model || deviceInfo?.device_type || '-'}</Text>
      </FieldRow>

      {/* 时间 */}
      <FieldRow label="时间">
        <DatePicker showTime value={time} onChange={setTime} style={{ width: 200 }} />
        <SettingButton onClick={() => handleSet('时间')} />
      </FieldRow>

      {/* PV接线方式 */}
      <FieldRow label="PV接线方式">
        <Select value={pvWiring} onChange={setPvWiring} style={{ width: 140 }}>
          <Option value="independent">独立</Option>
          <Option value="parallel">并联</Option>
          <Option value="series">串联</Option>
        </Select>
        <SettingButton onClick={() => handleSet('PV接线方式')} />
      </FieldRow>

      {/* 电池类型 */}
      <FieldRow label="电池类型">
        <Select value={batteryType} onChange={setBatteryType} style={{ width: 140 }}>
          <Option value="lifepo4">磷酸铁锂</Option>
          <Option value="ncm">三元锂</Option>
          <Option value="lead_acid">铅酸</Option>
          <Option value="other">其他</Option>
        </Select>
        <SettingButton onClick={() => handleSet('电池类型')} />
      </FieldRow>

      {/* 铅酸电池类型 - 仅铅酸时显示 */}
      {isLeadAcid && (
        <FieldRow label="铅酸电池类型">
          <Select value={leadAcidType} onChange={setLeadAcidType} style={{ width: 140 }}>
            <Option value="flooded">flooded</Option>
            <Option value="AGM">AGM</Option>
            <Option value="Gel">Gel</Option>
          </Select>
          <SettingButton onClick={() => handleSet('铅酸电池类型')} />
        </FieldRow>
      )}

      {/* 锂电池类型 - 非铅酸时显示 */}
      {isLithium && (
        <FieldRow label="锂电池类型">
          <Select value={lithiumType} onChange={setLithiumType} style={{ width: 140 }}>
            <Option value="lifepo4">磷酸铁锂</Option>
            <Option value="ncm">三元锂</Option>
            <Option value="lto">钛酸锂</Option>
          </Select>
          <SettingButton onClick={() => handleSet('锂电池类型')} />
        </FieldRow>
      )}

      {/* 法规 */}
      <FieldRow label="法规">
        <Select value={regulation} onChange={setRegulation} style={{ width: 140 }}>
          <Option value="china">中国</Option>
          <Option value="europe">欧洲</Option>
          <Option value="australia">澳大利亚</Option>
          <Option value="usa">美国</Option>
        </Select>
        <SettingButton onClick={() => handleSet('法规')} />
      </FieldRow>

      {/* 开关类字段 */}
      <SwitchField label="节能模式" checked={ecoMode} onChange={(v) => { setEcoMode(v); handleSet('节能模式') }} />
      <SwitchField label="开机/待机" checked={standby} onChange={(v) => { setStandby(v); handleSet('开机/待机') }} enableText="开机" disableText="待机" />
      <SwitchField label="电池节能模式" checked={batteryEco} onChange={(v) => { setBatteryEco(v); handleSet('电池节能模式') }} />
      <SwitchField label="蜂鸣器启用" checked={buzzer} onChange={(v) => { setBuzzer(v); handleSet('蜂鸣器启用') }} />

      {/* 重启逆变器 */}
      <Col span={12}>
        <div style={fieldRowStyle}>
          <Text style={labelStyle}>重启逆变器</Text>
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
