import React, { useState } from 'react'
import { Card, Button, Space, Select, Switch, App, DatePicker, Modal, Typography } from 'antd'
import { SettingOutlined, ExclamationCircleOutlined } from '@ant-design/icons'
import dayjs from 'dayjs'

const { Text } = Typography
const { Option } = Select

const cardStyle = { borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }
const labelStyle: React.CSSProperties = { fontSize: 13, color: '#666', marginBottom: 4, display: 'block' }
const fieldRowStyle = { marginBottom: 12 }
const settingBtnStyle = { background: '#4f6ef7', borderColor: '#4f6ef7' }

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
    message.success(`${fieldName} 设置已发送`)
  }

  return (
    <Card
      bordered={false}
      style={cardStyle}
      title={
        <Space>
          <SettingOutlined />
          <span style={{ fontSize: 16, fontWeight: 'bold' }}>通用设置</span>
        </Space>
      }
    >
      <div style={fieldRowStyle}>
        <Text style={labelStyle}>时间</Text>
        <Space>
          <DatePicker showTime value={time} onChange={setTime} style={{ width: 220 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('时间')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>PV接线方式</Text>
        <Space>
          <Select value={pvWiring} onChange={setPvWiring} style={{ width: 150 }}>
            <Option value="independent">独立</Option>
            <Option value="parallel">并联</Option>
            <Option value="series">串联</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('PV接线方式')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>型号</Text>
        <Text strong>{deviceInfo?.model || deviceInfo?.device_type || '-'}</Text>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>电池类型</Text>
        <Space>
          <Select value={batteryType} onChange={setBatteryType} style={{ width: 150 }}>
            <Option value="lifepo4">磷酸铁锂</Option>
            <Option value="ncm">三元锂</Option>
            <Option value="lead_acid">铅酸</Option>
            <Option value="other">其他</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('电池类型')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>铅酸电池类型</Text>
        <Space>
          <Select value={leadAcidType} onChange={setLeadAcidType} style={{ width: 150 }}>
            <Option value="flooded">flooded</Option>
            <Option value="AGM">AGM</Option>
            <Option value="Gel">Gel</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('铅酸电池类型')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>锂电池类型</Text>
        <Space>
          <Select value={lithiumType} onChange={setLithiumType} style={{ width: 150 }}>
            <Option value="lifepo4">磷酸铁锂</Option>
            <Option value="ncm">三元锂</Option>
            <Option value="lto">钛酸锂</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('锂电池类型')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>法规</Text>
        <Space>
          <Select value={regulation} onChange={setRegulation} style={{ width: 150 }}>
            <Option value="china">中国</Option>
            <Option value="europe">欧洲</Option>
            <Option value="australia">澳大利亚</Option>
            <Option value="usa">美国</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('法规')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>节能模式</Text>
        <Switch checked={ecoMode} onChange={(v) => { setEcoMode(v); handleSet('节能模式') }} />
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>开机/待机</Text>
        <Switch checked={standby} onChange={(v) => { setStandby(v); handleSet('开机/待机') }} />
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>电池节能模式</Text>
        <Switch checked={batteryEco} onChange={(v) => { setBatteryEco(v); handleSet('电池节能模式') }} />
      </div>

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

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>蜂鸣器启用</Text>
        <Switch checked={buzzer} onChange={(v) => { setBuzzer(v); handleSet('蜂鸣器启用') }} />
      </div>
    </Card>
  )
}

export default GeneralSection
