import React from 'react'
import { Row, Col, Typography } from 'antd'
import { safeNum } from '@/utils/format'

const { Text } = Typography

interface EnergyFlowDiagramProps {
  pvPower: number
  loadPower: number
  battPower: number
  gridPower: number
  battSoc: number
}

const formatPower = (w: number): string => {
  const abs = Math.abs(w)
  if (abs >= 1000) return `${(w / 1000).toFixed(1)} kW`
  return `${w.toFixed(0)} W`
}

const NodeBox: React.FC<{
  icon: string
  label: string
  power: number
  color: string
  extra?: string
}> = ({ icon, label, power, color, extra }) => (
  <div style={{
    textAlign: 'center',
    padding: '12px 8px',
    borderRadius: 12,
    background: `${color}10`,
    border: `1px solid ${color}30`,
    minWidth: 100,
  }}>
    <div style={{ fontSize: 28 }}>{icon}</div>
    <div style={{ fontSize: 12, color: '#64748b', marginBottom: 4 }}>{label}</div>
    <div style={{ fontSize: 15, fontWeight: 700, color }}>{formatPower(power)}</div>
    {extra && <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{extra}</div>}
  </div>
)

const Arrow: React.FC<{
  active: boolean
  direction?: 'right' | 'left' | 'down' | 'up'
  color?: string
}> = ({ active, direction = 'right', color = '#94a3b8' }) => {
  const arrows: Record<string, string> = {
    right: '→', left: '←', down: '↓', up: '↑',
  }
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontSize: 22,
      color: active ? color : '#d1d5db',
      fontWeight: active ? 700 : 400,
      transition: 'all 0.3s',
      padding: '0 4px',
    }}>
      {arrows[direction]}
    </div>
  )
}

const EnergyFlowDiagram: React.FC<EnergyFlowDiagramProps> = ({
  pvPower, loadPower, battPower, gridPower, battSoc,
}) => {
  const pv = safeNum(pvPower)
  const load = safeNum(loadPower)
  const batt = safeNum(battPower)
  const grid = safeNum(gridPower)
  const soc = safeNum(battSoc)

  return (
    <div style={{ padding: '16px 0' }}>
      {/* Row 1: PV → Inverter → Grid */}
      <Row align="middle" justify="center" gutter={[0, 0]}>
        <Col>
          <NodeBox icon="☀️" label="PV" power={pv} color="#f59e0b" />
        </Col>
        <Col flex="60px">
          <Arrow active={pv > 0} direction="right" color="#f59e0b" />
        </Col>
        <Col>
          <NodeBox
            icon="⚡"
            label="Inverter"
            power={pv + Math.max(0, batt) + Math.max(0, grid)}
            color="#6366f1"
          />
        </Col>
        <Col flex="60px">
          <Arrow active={grid !== 0} direction={grid > 0 ? 'right' : 'left'} color="#3b82f6" />
        </Col>
        <Col>
          <NodeBox
            icon="🔌"
            label="Grid"
            power={Math.abs(grid)}
            color="#3b82f6"
            extra={grid > 0 ? '卖电' : grid < 0 ? '买电' : undefined}
          />
        </Col>
      </Row>

      {/* Row 2: Battery + Load */}
      <Row align="middle" justify="center" style={{ marginTop: 16 }} gutter={[0, 0]}>
        <Col offset={2}>
          <NodeBox
            icon="🔋"
            label="Battery"
            power={Math.abs(batt)}
            color="#22c55e"
            extra={`SOC ${soc.toFixed(0)}%`}
          />
        </Col>
        <Col flex="60px" />
        <Col>
          <div style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: 4,
          }}>
            <Arrow active={batt !== 0} direction={batt > 0 ? 'up' : 'down'} color="#22c55e" />
          </div>
        </Col>
        <Col flex="60px" />
        <Col>
          <NodeBox icon="💡" label="Load" power={load} color="#ef4444" />
        </Col>
      </Row>
    </div>
  )
}

export default EnergyFlowDiagram
