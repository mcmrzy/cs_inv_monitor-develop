import React, { useState } from 'react'
import { Row, Select, InputNumber, App } from 'antd'
import { FieldRow, SwitchField, SettingButton, SubGroupHelp, displayLabel, buildLabelMap, buildDefaults } from './shared-styles'

interface Props {
  deviceInfo: any
}

// ==================== 字段元数据（单一数据源） ====================

/** 并网字段定义 */
const GRID_FIELDS: { key: string; label: string; unit?: string; range?: string; min?: number; max?: number; default: number }[] = [
  { key: 'gridWaitTime', label: '并网等待时间', unit: 's', range: '30~600', min: 30, max: 600, default: 300 },
  { key: 'reGridWaitTime', label: '重新并网等待时间', unit: 's', range: '0~600', min: 0, max: 600, default: 60 },
  { key: 'gridVoltageUpper', label: '并网市电电压上限', unit: 'V', default: 264 },
  { key: 'gridVoltageLower', label: '并网市电电压下限', unit: 'V', default: 176 },
  { key: 'gridFreqUpper', label: '并网市电频率上限', unit: 'Hz', default: 55 },
  { key: 'gridFreqLower', label: '并网市电频率下限', unit: 'Hz', default: 45 },
]

/** 功率控制字段定义 */
const POWER_CONTROL_FIELDS: { key: string; label: string; unit?: string; type: 'switch' | 'select' | 'input'; range?: string; min?: number; max?: number; default: number | boolean; tooltip?: string; helpValue?: string }[] = [
  { key: 'freqDeratingEnable', label: '过频降载使能', type: 'switch', default: false, helpValue: '电网频率超过阈值时自动降低有功输出' },
  { key: 'reactivePowerMode', label: '无功输出模式', type: 'select', default: 0, helpValue: '支持单位功率因数/固定PF/默认无功曲线/容性无功百分比/感性无功百分比/Q(V)曲线共6种模式' },
  { key: 'reactivePowerPercent', label: '无功百分比设定值', unit: '%', type: 'input', range: '0~60', min: 0, max: 60, default: 0 },
  { key: 'pfValue', label: 'PF设定值', type: 'input', range: '750~2000', min: 750, max: 2000, default: 1000, tooltip: '你可以设置750-1000达到超前，1750-2000达到滞后' },
  { key: 'activePowerPercent', label: '有功百分比设定值', unit: '%', type: 'input', range: '0~100', min: 0, max: 100, default: 100 },
  { key: 'gridSoftStart', label: '电网软启动', type: 'switch', default: false, helpValue: '并网时功率从零逐步上升至额定值，避免对电网产生冲击' },
]

/** 无功输出模式下拉选项 */
const REACTIVE_POWER_OPTIONS = [
  { value: 0, label: '单位功率因数输出' },
  { value: 1, label: '固定PF输出' },
  { value: 2, label: '默认无功曲线输出' },
  { value: 4, label: '容性无功百分比输出' },
  { value: 5, label: '感性无功百分比输出' },
  { value: 6, label: 'Q(V)曲线' },
]

/** 市电保护等级字段定义 */
const PROTECTION_FIELDS: { key: string; label: string; unit?: string; range?: string; min?: number; max?: number; default: number }[] = [
  { key: 'v1UnderVoltage', label: '电网电压1级欠压保护点', unit: 'V', default: 176 },
  { key: 'v1OverVoltage', label: '电网电压1级过压保护点', unit: 'V', default: 264 },
  { key: 'f1UnderFreq', label: '电网频率1级欠频保护点', unit: 'Hz', default: 45 },
  { key: 'f1OverFreq', label: '电网频率1级过频保护点', unit: 'Hz', default: 55 },
  { key: 'vMovingAvgOverVoltage', label: '电网电压滑动平均过压保护点', unit: 'V', default: 264 },
  { key: 'v2UnderVoltage', label: '电网电压2级欠压保护点', unit: 'V', default: 176 },
  { key: 'v2OverVoltage', label: '电网电压2级过压保护点', unit: 'V', default: 264 },
  { key: 'f2UnderFreq', label: '电网频率2级欠频保护点', unit: 'Hz', default: 45 },
  { key: 'f2OverFreq', label: '电网频率2级过频保护点', unit: 'Hz', default: 55 },
  { key: 'rampRate', label: '加载速率', unit: '%/min', range: '1~100', min: 1, max: 100, default: 50 },
  { key: 'v3UnderVoltage', label: '电网电压3级欠压保护点', unit: 'V', default: 176 },
  { key: 'v3OverVoltage', label: '电网电压3级过压保护点', unit: 'V', default: 264 },
  { key: 'f3UnderFreq', label: '电网频率3级欠频保护点', unit: 'Hz', default: 45 },
  { key: 'f3OverFreq', label: '电网频率3级过频保护点', unit: 'Hz', default: 55 },
]

// ==================== 静态映射 ====================

const LABEL_MAP = buildLabelMap(GRID_FIELDS, POWER_CONTROL_FIELDS, PROTECTION_FIELDS)
const GRID_DEFAULTS = buildDefaults(GRID_FIELDS)
const POWER_DEFAULTS = buildDefaults(POWER_CONTROL_FIELDS)
const PROTECTION_DEFAULTS = buildDefaults(PROTECTION_FIELDS)

// ==================== 组件 ====================

const GridConnectionSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()

  // 并网 state
  const [gridState, setGridState] = useState<Record<string, number>>(GRID_DEFAULTS)
  // 功率控制 state
  const [powerState, setPowerState] = useState<Record<string, number | boolean>>(POWER_DEFAULTS)
  // 市电保护等级 state
  const [protectionState, setProtectionState] = useState<Record<string, number>>(PROTECTION_DEFAULTS)

  const handleSet = (fieldKey: string) => {
    const label = LABEL_MAP[fieldKey]
    message.success(`${label} 指令已下发`)
  }

  const updateGrid = (key: string, val: number, fallback: number) => {
    setGridState((prev) => ({ ...prev, [key]: val ?? fallback }))
  }

  const updatePower = (key: string, val: number | boolean, fallback: number | boolean) => {
    setPowerState((prev) => ({ ...prev, [key]: val ?? fallback }))
  }

  const updateProtection = (key: string, val: number, fallback: number) => {
    setProtectionState((prev) => ({ ...prev, [key]: val ?? fallback }))
  }

  return (
    <Row gutter={[16, 8]}>
      {/* 并网 */}
      <SubGroupHelp title="并网" color="#3b82f6" hint="设置并网等待时间、重新并网等待时间、并网市电电压/频率上下限" />
      {GRID_FIELDS.map((f) => (
        <FieldRow key={f.key} label={displayLabel(f)} range={f.range}>
          <InputNumber
            min={f.min}
            max={f.max}
            value={gridState[f.key] as number}
            onChange={(v) => updateGrid(f.key, v as number, f.default)}
            style={{ width: 140 }}
          />
          <SettingButton onClick={() => handleSet(f.key)} />
        </FieldRow>
      ))}

      {/* 功率控制 */}
      <SubGroupHelp title="功率控制" color="#3b82f6" hint="设置过频降载使能、无功输出模式（6种）、无功百分比、PF设定值、有功百分比、电网软启动" />
      {POWER_CONTROL_FIELDS.map((f) => {
        if (f.type === 'switch') {
          return (
            <SwitchField
              key={f.key}
              label={displayLabel(f)}
              checked={powerState[f.key] as boolean}
              onChange={(v) => { updatePower(f.key, v, f.default); handleSet(f.key) }}
            />
          )
        }
        if (f.type === 'select') {
          return (
            <FieldRow key={f.key} label={displayLabel(f)}>
              <Select
                value={powerState[f.key] as number}
                onChange={(v: number) => updatePower(f.key, v, f.default)}
                style={{ width: 140 }}
              >
                {REACTIVE_POWER_OPTIONS.map((opt) => (
                  <Select.Option key={opt.value} value={opt.value}>{opt.label}</Select.Option>
                ))}
              </Select>
              <SettingButton onClick={() => handleSet(f.key)} />
            </FieldRow>
          )
        }
        // input
        return (
          <FieldRow key={f.key} label={displayLabel(f)} range={f.range} tooltip={f.tooltip}>
            <InputNumber
              min={f.min}
              max={f.max}
              value={powerState[f.key] as number}
              onChange={(v) => updatePower(f.key, v as number, f.default)}
              style={{ width: 140 }}
            />
            <SettingButton onClick={() => handleSet(f.key)} />
          </FieldRow>
        )
      })}

      {/* 市电保护等级 */}
      <SubGroupHelp title="市电保护等级" color="#3b82f6" hint="设置1/2/3级电网电压欠压/过压保护点、频率欠频/过频保护点、滑动平均过压保护点、加载速率" />
      {PROTECTION_FIELDS.map((f) => (
        <FieldRow key={f.key} label={displayLabel(f)} range={f.range}>
          <InputNumber
            min={f.min}
            max={f.max}
            value={protectionState[f.key] as number}
            onChange={(v) => updateProtection(f.key, v as number, f.default)}
            style={{ width: 140 }}
          />
          <SettingButton onClick={() => handleSet(f.key)} />
        </FieldRow>
      ))}
    </Row>
  )
}

export default GridConnectionSection
