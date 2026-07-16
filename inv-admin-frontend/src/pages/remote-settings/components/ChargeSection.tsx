import React, { useState } from 'react'
import { Card, Button, Space, Select, Switch, InputNumber, Divider, App, Typography } from 'antd'
import { ArrowUpOutlined } from '@ant-design/icons'

const { Text } = Typography
const { Option } = Select

const cardStyle = { borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }
const labelStyle: React.CSSProperties = { fontSize: 13, color: '#666', marginBottom: 4, display: 'block' }
const fieldRowStyle = { marginBottom: 12 }
const settingBtnStyle = { background: '#4f6ef7', borderColor: '#4f6ef7' }
const subTitleStyle: React.CSSProperties = { fontSize: 14, fontWeight: 600, color: '#333', marginBottom: 12 }

interface TimeRangeFieldProps {
  label: string
  h: number
  m: number
  onHChange: (v: number | null) => void
  onMChange: (v: number | null) => void
  onSet: () => void
}

const TimeRangeField: React.FC<TimeRangeFieldProps> = ({ label, h, m, onHChange, onMChange, onSet }) => (
  <div style={fieldRowStyle}>
    <Text style={labelStyle}>{label}</Text>
    <Space>
      <InputNumber min={0} max={23} value={h} onChange={onHChange} style={{ width: 70 }} addonAfter="时" />
      <Text>:</Text>
      <InputNumber min={0} max={59} value={m} onChange={onMChange} style={{ width: 70 }} addonAfter="分" />
      <Button type="primary" size="small" style={settingBtnStyle} onClick={onSet}>设置</Button>
    </Space>
  </div>
)

const ChargeSection: React.FC = () => {
  const { message } = App.useApp()

  // 主充电参数
  const [chargeCurrent, setChargeCurrent] = useState<number>(60)

  // 铅酸充电参数
  const [chargeVoltage, setChargeVoltage] = useState<number>(54)
  const [floatVoltage, setFloatVoltage] = useState<number>(54)
  const [equalVoltage, setEqualVoltage] = useState<number>(56)
  const [equalCycle, setEqualCycle] = useState<number>(30)
  const [equalTime, setEqualTime] = useState<number>(2)

  // 交流充电
  const [acChargeControl, setAcChargeControl] = useState('voltage')
  const [acChargeCurrent, setAcChargeCurrent] = useState<number>(60)
  const [acStart1H, setAcStart1H] = useState(0)
  const [acStart1M, setAcStart1M] = useState(0)
  const [acEnd1H, setAcEnd1H] = useState(0)
  const [acEnd1M, setAcEnd1M] = useState(0)
  const [acStart2H, setAcStart2H] = useState(0)
  const [acStart2M, setAcStart2M] = useState(0)
  const [acEnd2H, setAcEnd2H] = useState(0)
  const [acEnd2M, setAcEnd2M] = useState(0)
  const [acStart3H, setAcStart3H] = useState(0)
  const [acStart3M, setAcStart3M] = useState(0)
  const [acEnd3H, setAcEnd3H] = useState(0)
  const [acEnd3M, setAcEnd3M] = useState(0)
  const [acChargeStartVoltage, setAcChargeStartVoltage] = useState<number>(46)
  const [acChargeEndVoltage, setAcChargeEndVoltage] = useState<number>(54)
  const [acChargeStartSoc, setAcChargeStartSoc] = useState<number>(20)
  const [acChargeEndSoc, setAcChargeEndSoc] = useState<number>(90)

  // 发电机充电
  const [genChargeType, setGenChargeType] = useState('manual')
  const [genChargeCurrent, setGenChargeCurrent] = useState<number>(60)
  const [genChargeStartVoltage, setGenChargeStartVoltage] = useState<number>(46)
  const [genChargeEndVoltage, setGenChargeEndVoltage] = useState<number>(54)
  const [genChargeStartSoc, setGenChargeStartSoc] = useState<number>(20)
  const [genChargeEndSoc, setGenChargeEndSoc] = useState<number>(90)
  const [genRatedPower, setGenRatedPower] = useState<number>(3000)
  const [genBoost, setGenBoost] = useState(false)

  const handleSet = (fieldName: string) => {
    message.success(`${fieldName} 设置已发送`)
  }

  return (
    <Card
      bordered={false}
      style={cardStyle}
      title={
        <Space>
          <ArrowUpOutlined />
          <span style={{ fontSize: 16, fontWeight: 'bold' }}>充电设置</span>
        </Space>
      }
    >
      {/* 主充电参数 */}
      <Text style={subTitleStyle}>主充电参数</Text>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>充电电流限制(A)</Text>
        <Space>
          <InputNumber min={0} max={110} step={0.1} value={chargeCurrent} onChange={(v) => setChargeCurrent(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('充电电流限制')}>设置</Button>
        </Space>
      </div>

      <Divider />

      {/* 铅酸充电参数 */}
      <Text style={subTitleStyle}>铅酸</Text>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>充电电压(V)</Text>
        <Space>
          <InputNumber min={50} max={58} step={0.1} value={chargeVoltage} onChange={(v) => setChargeVoltage(v ?? 50)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('充电电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>浮动电压(V)</Text>
        <Space>
          <InputNumber min={50} max={58} step={0.1} value={floatVoltage} onChange={(v) => setFloatVoltage(v ?? 50)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('浮动电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>均衡电压(V)</Text>
        <Space>
          <InputNumber min={50} max={59} step={0.1} value={equalVoltage} onChange={(v) => setEqualVoltage(v ?? 50)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('均衡电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>均衡周期(天)</Text>
        <Space>
          <InputNumber min={0} max={365} value={equalCycle} onChange={(v) => setEqualCycle(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('均衡周期')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>均衡时间(小时)</Text>
        <Space>
          <InputNumber min={0} max={24} value={equalTime} onChange={(v) => setEqualTime(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('均衡时间')}>设置</Button>
        </Space>
      </div>

      <Divider />

      {/* 交流充电 */}
      <Text style={subTitleStyle}>交流充电</Text>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>AC充电控制依据</Text>
        <Space>
          <Select value={acChargeControl} onChange={setAcChargeControl} style={{ width: 150 }}>
            <Option value="voltage">电池电压</Option>
            <Option value="soc">SOC</Option>
            <Option value="voltage_soc">电压+SOC</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('AC充电控制依据')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>交流充电电池电流(A)</Text>
        <Space>
          <InputNumber min={0} max={150} step={0.1} value={acChargeCurrent} onChange={(v) => setAcChargeCurrent(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('交流充电电池电流')}>设置</Button>
        </Space>
      </div>

      <TimeRangeField label="AC充电起始时间1" h={acStart1H} m={acStart1M} onHChange={(v) => setAcStart1H(v ?? 0)} onMChange={(v) => setAcStart1M(v ?? 0)} onSet={() => handleSet('AC充电起始时间1')} />
      <TimeRangeField label="AC充电结束时间1" h={acEnd1H} m={acEnd1M} onHChange={(v) => setAcEnd1H(v ?? 0)} onMChange={(v) => setAcEnd1M(v ?? 0)} onSet={() => handleSet('AC充电结束时间1')} />
      <TimeRangeField label="AC充电起始时间2" h={acStart2H} m={acStart2M} onHChange={(v) => setAcStart2H(v ?? 0)} onMChange={(v) => setAcStart2M(v ?? 0)} onSet={() => handleSet('AC充电起始时间2')} />
      <TimeRangeField label="AC充电结束时间2" h={acEnd2H} m={acEnd2M} onHChange={(v) => setAcEnd2H(v ?? 0)} onMChange={(v) => setAcEnd2M(v ?? 0)} onSet={() => handleSet('AC充电结束时间2')} />
      <TimeRangeField label="AC充电起始时间3" h={acStart3H} m={acStart3M} onHChange={(v) => setAcStart3H(v ?? 0)} onMChange={(v) => setAcStart3M(v ?? 0)} onSet={() => handleSet('AC充电起始时间3')} />
      <TimeRangeField label="AC充电结束时间3" h={acEnd3H} m={acEnd3M} onHChange={(v) => setAcEnd3H(v ?? 0)} onMChange={(v) => setAcEnd3M(v ?? 0)} onSet={() => handleSet('AC充电结束时间3')} />

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>交流充电开始电池电压(V)</Text>
        <Space>
          <InputNumber min={38.4} max={52} step={0.1} value={acChargeStartVoltage} onChange={(v) => setAcChargeStartVoltage(v ?? 38.4)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('交流充电开始电池电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>交流充电结束电池电压(V)</Text>
        <Space>
          <InputNumber min={48} max={59} step={0.1} value={acChargeEndVoltage} onChange={(v) => setAcChargeEndVoltage(v ?? 48)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('交流充电结束电池电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>交流充电开始电池SOC(%)</Text>
        <Space>
          <InputNumber min={0} max={90} value={acChargeStartSoc} onChange={(v) => setAcChargeStartSoc(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('交流充电开始电池SOC')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>交流充电结束电池SOC(%)</Text>
        <Space>
          <InputNumber min={20} max={100} value={acChargeEndSoc} onChange={(v) => setAcChargeEndSoc(v ?? 20)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('交流充电结束电池SOC')}>设置</Button>
        </Space>
      </div>

      <Divider />

      {/* 发电机充电 */}
      <Text style={subTitleStyle}>发电机充电</Text>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机充电类型</Text>
        <Space>
          <Select value={genChargeType} onChange={setGenChargeType} style={{ width: 150 }}>
            <Option value="manual">手动</Option>
            <Option value="auto">自动</Option>
          </Select>
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机充电类型')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机充电电池电流(A)</Text>
        <Space>
          <InputNumber min={0} max={110} step={0.1} value={genChargeCurrent} onChange={(v) => setGenChargeCurrent(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机充电电池电流')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机充电开始电池电压(V)</Text>
        <Space>
          <InputNumber min={38.4} max={52} step={0.1} value={genChargeStartVoltage} onChange={(v) => setGenChargeStartVoltage(v ?? 38.4)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机充电开始电池电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机充电结束电池电压(V)</Text>
        <Space>
          <InputNumber min={48} max={59} step={0.1} value={genChargeEndVoltage} onChange={(v) => setGenChargeEndVoltage(v ?? 48)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机充电结束电池电压')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机充电开始电池SOC(%)</Text>
        <Space>
          <InputNumber min={0} max={90} value={genChargeStartSoc} onChange={(v) => setGenChargeStartSoc(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机充电开始电池SOC')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机充电结束电池SOC(%)</Text>
        <Space>
          <InputNumber min={20} max={100} value={genChargeEndSoc} onChange={(v) => setGenChargeEndSoc(v ?? 20)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机充电结束电池SOC')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机额定功率(W)</Text>
        <Space>
          <InputNumber min={0} max={7370} value={genRatedPower} onChange={(v) => setGenRatedPower(v ?? 0)} style={{ width: 150 }} />
          <Button type="primary" size="small" style={settingBtnStyle} onClick={() => handleSet('发电机额定功率')}>设置</Button>
        </Space>
      </div>

      <div style={fieldRowStyle}>
        <Text style={labelStyle}>发电机提升</Text>
        <Switch checked={genBoost} onChange={(v) => { setGenBoost(v); handleSet('发电机提升') }} />
      </div>
    </Card>
  )
}

export default ChargeSection
