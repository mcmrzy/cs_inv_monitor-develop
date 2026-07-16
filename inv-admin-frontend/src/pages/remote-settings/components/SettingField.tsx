import React, { useState, useEffect } from 'react'
import { Switch, InputNumber, Button, Select, Space, Tooltip, Typography } from 'antd'
import { QuestionCircleOutlined } from '@ant-design/icons'

const { Text } = Typography

const PRIMARY = '#4f6ef7'

interface SettingFieldProps {
  label: string
  fieldKey: string
  type: 'switch' | 'number' | 'select' | 'time-range'
  min?: number
  max?: number
  step?: number
  unit?: string
  options?: { label: string; value: string | number }[]
  reportedValue?: unknown
  disabled?: boolean
  onSend: (value: any) => void
  tooltip?: string
  pending?: boolean
  // time-range 专用
  hourKey?: string
  minuteKey?: string
}

const SettingField: React.FC<SettingFieldProps> = ({
  label,
  fieldKey,
  type,
  min,
  max,
  step,
  unit,
  options,
  reportedValue,
  disabled,
  onSend,
  tooltip,
  pending,
  hourKey,
  minuteKey,
}) => {
  // ── 本地 state（number / select / time-range）──
  const [localNumber, setLocalNumber] = useState<number>(0)
  const [localSelect, setLocalSelect] = useState<string | number>('')
  const [localHour, setLocalHour] = useState<number>(0)
  const [localMinute, setLocalMinute] = useState<number>(0)

  // 当 reportedValue 变化时同步初始值
  useEffect(() => {
    if (reportedValue === undefined) return
    if (type === 'number') {
      setLocalNumber(Number(reportedValue))
    } else if (type === 'select') {
      setLocalSelect(reportedValue as string | number)
    }
  }, [reportedValue, type])

  // time-range：用 reported 对象中的 hourKey / minuteKey 同步（由父组件传入 reportedValue 作为 [hour, minute] 元组）
  useEffect(() => {
    if (type !== 'time-range') return
    if (Array.isArray(reportedValue) && reportedValue.length === 2) {
      setLocalHour(Number(reportedValue[0]))
      setLocalMinute(Number(reportedValue[1]))
    }
  }, [reportedValue, type])

  // ── 当前值回显文本 ──
  const currentText = (() => {
    if (reportedValue === undefined || reportedValue === null) return null
    if (type === 'switch') return reportedValue ? '开启' : '关闭'
    if (type === 'number') return unit ? `${String(reportedValue)}${unit}` : String(reportedValue)
    if (type === 'select') {
      const match = options?.find((o) => o.value === reportedValue)
      return match ? match.label : String(reportedValue)
    }
    if (type === 'time-range' && Array.isArray(reportedValue) && reportedValue.length === 2) {
      return `${String(reportedValue[0]).padStart(2, '0')}:${String(reportedValue[1]).padStart(2, '0')}`
    }
    return String(reportedValue)
  })()

  return (
    <div style={{ marginBottom: 12 }}>
      {/* 标签行 */}
      <Text type="secondary" style={{ fontSize: 12, display: 'block', marginBottom: 6 }}>
        {label}
        {tooltip && (
          <Tooltip title={tooltip}>
            <QuestionCircleOutlined style={{ marginLeft: 4, cursor: 'pointer' }} />
          </Tooltip>
        )}
        {currentText !== null && (
          <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
            当前: {currentText}
          </Text>
        )}
      </Text>

      {/* 控件行 */}
      {type === 'switch' && (
        <Switch
          checked={Boolean(reportedValue)}
          onChange={(v) => onSend(v)}
          disabled={disabled}
          loading={pending}
        />
      )}

      {type === 'number' && (
        <Space>
          <InputNumber
            min={min}
            max={max}
            step={step}
            addonAfter={unit}
            value={localNumber}
            onChange={(v) => setLocalNumber(v ?? 0)}
            disabled={disabled}
            style={{ width: 180 }}
          />
          <Button
            type="primary"
            size="small"
            loading={pending}
            disabled={disabled}
            onClick={() => onSend(localNumber)}
            style={{ background: PRIMARY, borderColor: PRIMARY }}
          >
            下发
          </Button>
        </Space>
      )}

      {type === 'select' && (
        <Space>
          <Select
            value={localSelect}
            onChange={setLocalSelect}
            options={options}
            disabled={disabled}
            style={{ width: 180 }}
          />
          <Button
            type="primary"
            size="small"
            loading={pending}
            disabled={disabled}
            onClick={() => onSend(localSelect)}
            style={{ background: PRIMARY, borderColor: PRIMARY }}
          >
            下发
          </Button>
        </Space>
      )}

      {type === 'time-range' && (
        <Space>
          <InputNumber
            min={0}
            max={23}
            value={localHour}
            onChange={(v) => setLocalHour(v ?? 0)}
            disabled={disabled}
            style={{ width: 72 }}
            addonAfter="时"
          />
          <Text type="secondary" style={{ lineHeight: '32px' }}>:</Text>
          <InputNumber
            min={0}
            max={59}
            value={localMinute}
            onChange={(v) => setLocalMinute(v ?? 0)}
            disabled={disabled}
            style={{ width: 72 }}
            addonAfter="分"
          />
          <Button
            type="primary"
            size="small"
            loading={pending}
            disabled={disabled}
            onClick={() => onSend({ hour: localHour, minute: localMinute })}
            style={{ background: PRIMARY, borderColor: PRIMARY }}
          >
            下发
          </Button>
        </Space>
      )}
    </div>
  )
}

export default SettingField
