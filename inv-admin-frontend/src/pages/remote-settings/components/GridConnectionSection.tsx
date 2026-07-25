import React, { useState } from 'react'
import { Row, Select, InputNumber, App } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import { FieldRow, SwitchField, SettingButton, SubGroupHelp, buildDefaults } from './shared-styles'

interface Props {
  deviceInfo: any
}

// ==================== 字段元数据（单一数据源） ====================

/** 并网字段定义 */
const GRID_FIELDS: { key: string; labelKey: string; unit?: string; range?: string; min?: number; max?: number; default: number }[] = [
  { key: 'gridWaitTime', labelKey: 'remote.gridWaitTime', unit: 's', range: '30~600', min: 30, max: 600, default: 300 },
  { key: 'reGridWaitTime', labelKey: 'remote.gridReconnectWait', unit: 's', range: '0~600', min: 0, max: 600, default: 60 },
  { key: 'gridVoltageUpper', labelKey: 'remote.gridVoltageUpper', unit: 'V', default: 264 },
  { key: 'gridVoltageLower', labelKey: 'remote.gridVoltageLower', unit: 'V', default: 176 },
  { key: 'gridFreqUpper', labelKey: 'remote.gridFreqUpper', unit: 'Hz', default: 55 },
  { key: 'gridFreqLower', labelKey: 'remote.gridFreqLower', unit: 'Hz', default: 45 },
]

/** 功率控制字段定义 */
const POWER_CONTROL_FIELDS: { key: string; labelKey: string; unit?: string; type: 'switch' | 'select' | 'input'; range?: string; min?: number; max?: number; default: number | boolean; tooltipKey?: string; helpValueKey?: string }[] = [
  { key: 'freqDeratingEnable', labelKey: 'remote.overFreqDerating', type: 'switch', default: false, helpValueKey: 'remote.freqDeratingHelp' },
  { key: 'reactivePowerMode', labelKey: 'remote.reactiveOutputMode', type: 'select', default: 0, helpValueKey: 'remote.reactiveModeHelp' },
  { key: 'reactivePowerPercent', labelKey: 'remote.reactivePct', unit: '%', type: 'input', range: '0~60', min: 0, max: 60, default: 0 },
  { key: 'pfValue', labelKey: 'remote.pfSetting', type: 'input', range: '750~2000', min: 750, max: 2000, default: 1000, tooltipKey: 'remote.pfSettingTooltip' },
  { key: 'activePowerPercent', labelKey: 'remote.activePowerPct', unit: '%', type: 'input', range: '0~100', min: 0, max: 100, default: 100 },
  { key: 'gridSoftStart', labelKey: 'remote.gridSoftStart', type: 'switch', default: false, helpValueKey: 'remote.gridSoftStartHelp' },
]

/** 无功输出模式下拉选项 */
const REACTIVE_POWER_OPTIONS = [
  { value: 0, labelKey: 'remote.unityPfOutput' },
  { value: 1, labelKey: 'remote.fixedPfOutput' },
  { value: 2, labelKey: 'remote.defaultReactiveCurve' },
  { value: 4, labelKey: 'remote.capacitiveReactivePct' },
  { value: 5, labelKey: 'remote.inductiveReactivePct' },
  { value: 6, labelKey: 'remote.qvCurve' },
]

/** 市电保护等级字段定义 */
const PROTECTION_FIELDS: { key: string; labelKey: string; unit?: string; range?: string; min?: number; max?: number; default: number }[] = [
  { key: 'v1UnderVoltage', labelKey: 'remote.gridVoltL1Under', unit: 'V', default: 176 },
  { key: 'v1OverVoltage', labelKey: 'remote.gridVoltL1Over', unit: 'V', default: 264 },
  { key: 'f1UnderFreq', labelKey: 'remote.gridFreqL1Under', unit: 'Hz', default: 45 },
  { key: 'f1OverFreq', labelKey: 'remote.gridFreqL1Over', unit: 'Hz', default: 55 },
  { key: 'vMovingAvgOverVoltage', labelKey: 'remote.gridVoltSlideAvgOver', unit: 'V', default: 264 },
  { key: 'v2UnderVoltage', labelKey: 'remote.gridVoltL2Under', unit: 'V', default: 176 },
  { key: 'v2OverVoltage', labelKey: 'remote.gridVoltL2Over', unit: 'V', default: 264 },
  { key: 'f2UnderFreq', labelKey: 'remote.gridFreqL2Under', unit: 'Hz', default: 45 },
  { key: 'f2OverFreq', labelKey: 'remote.gridFreqL2Over', unit: 'Hz', default: 55 },
  { key: 'rampRate', labelKey: 'remote.rampRate', unit: '%/min', range: '1~100', min: 1, max: 100, default: 50 },
  { key: 'v3UnderVoltage', labelKey: 'remote.gridVoltL3Under', unit: 'V', default: 176 },
  { key: 'v3OverVoltage', labelKey: 'remote.gridVoltL3Over', unit: 'V', default: 264 },
  { key: 'f3UnderFreq', labelKey: 'remote.gridFreqL3Under', unit: 'Hz', default: 45 },
  { key: 'f3OverFreq', labelKey: 'remote.gridFreqL3Over', unit: 'Hz', default: 55 },
]

// ==================== 静态映射 ====================

const GRID_DEFAULTS = buildDefaults(GRID_FIELDS)
const POWER_DEFAULTS = buildDefaults(POWER_CONTROL_FIELDS)
const PROTECTION_DEFAULTS = buildDefaults(PROTECTION_FIELDS)

// ==================== 组件 ====================

const GridConnectionSection: React.FC<Props> = ({ deviceInfo }) => {
  const { message } = App.useApp()
  const { t } = useTranslation()

  // 并网 state
  const [gridState, setGridState] = useState<Record<string, number>>(GRID_DEFAULTS)
  // 功率控制 state
  const [powerState, setPowerState] = useState<Record<string, number | boolean>>(POWER_DEFAULTS)
  // 市电保护等级 state
  const [protectionState, setProtectionState] = useState<Record<string, number>>(PROTECTION_DEFAULTS)

  const handleSet = (fieldKey: string) => {
    const allFields = [...GRID_FIELDS, ...POWER_CONTROL_FIELDS, ...PROTECTION_FIELDS]
    const field = allFields.find((f) => f.key === fieldKey)
    const label = field ? t(field.labelKey) : fieldKey
    message.success(t('remote.executeSuccess', { title: label }))
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
      <SubGroupHelp title={t('remote.gridSettings')} color="#3b82f6" hint={t('remote.gridSectionHint')} />
      {GRID_FIELDS.map((f) => (
        <FieldRow key={f.key} label={f.unit ? `${t(f.labelKey)}(${f.unit})` : t(f.labelKey)} range={f.range}>
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
      <SubGroupHelp title={t('remoteSettings.tabPower')} color="#3b82f6" hint={t('remote.powerSectionHint')} />
      {POWER_CONTROL_FIELDS.map((f) => {
        if (f.type === 'switch') {
          return (
            <SwitchField
              key={f.key}
              label={t(f.labelKey)}
              checked={powerState[f.key] as boolean}
              onChange={(v) => { updatePower(f.key, v, f.default); handleSet(f.key) }}
            />
          )
        }
        if (f.type === 'select') {
          return (
            <FieldRow key={f.key} label={t(f.labelKey)}>
              <Select
                value={powerState[f.key] as number}
                onChange={(v: number) => updatePower(f.key, v, f.default)}
                style={{ width: 140 }}
              >
                {REACTIVE_POWER_OPTIONS.map((opt) => (
                  <Select.Option key={opt.value} value={opt.value}>{t(opt.labelKey)}</Select.Option>
                ))}
              </Select>
              <SettingButton onClick={() => handleSet(f.key)} />
            </FieldRow>
          )
        }
        // input
        return (
          <FieldRow key={f.key} label={f.unit ? `${t(f.labelKey)}(${f.unit})` : t(f.labelKey)} range={f.range} tooltip={f.tooltipKey ? t(f.tooltipKey) : undefined}>
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
      <SubGroupHelp title={t('remote.gridProtectionLevel')} color="#3b82f6" hint={t('remote.protectionSectionHint')} />
      {PROTECTION_FIELDS.map((f) => (
        <FieldRow key={f.key} label={f.unit ? `${t(f.labelKey)}(${f.unit})` : t(f.labelKey)} range={f.range}>
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
