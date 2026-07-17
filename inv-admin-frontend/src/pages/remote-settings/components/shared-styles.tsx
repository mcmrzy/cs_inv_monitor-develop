import React from 'react'
import { Button, Space, Typography, Col, Tooltip } from 'antd'
import { QuestionCircleOutlined, InfoCircleOutlined, LockOutlined } from '@ant-design/icons'

const { Text } = Typography

// 主题色
export const PRIMARY = '#4f6ef7'

// 每个分组颜色
export const SECTION_COLORS: Record<string, string> = {
  general: '#4f6ef7',
  application: '#7c3aed',
  gridConnection: '#3b82f6',
  charge: '#10b981',
  discharge: '#f59e0b',
  other: '#6b7280',
  reset: '#ef4444',
}

// 设置按钮样式
export const settingBtnStyle: React.CSSProperties = { background: PRIMARY, borderColor: PRIMARY }

// 禁用状态灰色按钮样式
const disabledBtnStyle: React.CSSProperties = { background: '#d9d9d9', borderColor: '#d9d9d9', color: '#fff' }

// 禁用字段灰色背景样式（供 InputNumber / Select 使用）
export const disabledInputStyle: React.CSSProperties = { backgroundColor: '#f5f5f5' }

// 字段行容器
export const fieldRowStyle: React.CSSProperties = { marginBottom: 10 }

// 字段标签
export const labelStyle: React.CSSProperties = { fontSize: 12, color: '#888', marginBottom: 3, display: 'block' }

// 范围提示文字
export const rangeStyle: React.CSSProperties = { fontSize: 11, color: '#bbb', marginTop: 2 }

// FieldRow 组件 - 统一的字段渲染
interface FieldRowProps {
  label: string
  range?: string
  children: React.ReactNode
  full?: boolean
  tooltip?: string
}

export const FieldRow: React.FC<FieldRowProps> = ({ label, range, children, full, tooltip }) => (
  <Col span={full ? 24 : 12}>
    <div style={fieldRowStyle}>
      <Text style={labelStyle}>
        {label}
        {tooltip && (
          <Tooltip title={tooltip} overlayStyle={{ maxWidth: 360 }}>
            <QuestionCircleOutlined style={{ marginLeft: 4, color: '#bbb', cursor: 'help', fontSize: 13 }} />
          </Tooltip>
        )}
      </Text>
      <Space size={8} wrap>
        {children}
      </Space>
      {range && <div style={rangeStyle}>{range}</div>}
    </div>
  </Col>
)

// SwitchField - 用 "启用/禁用" 按钮对代替 Switch
interface SwitchFieldProps {
  label: string
  checked: boolean
  onChange: (v: boolean) => void
  enableText?: string
  disableText?: string
  tooltip?: string
  disabled?: boolean
}

export const SwitchField: React.FC<SwitchFieldProps> = ({
  label, checked, onChange, enableText = '启用', disableText = '禁用', tooltip, disabled,
}) => (
  <Col span={12}>
    <div style={fieldRowStyle}>
      <Text style={labelStyle}>
        {label}
        {tooltip && (
          <Tooltip title={tooltip} overlayStyle={{ maxWidth: 360 }}>
            <QuestionCircleOutlined style={{ marginLeft: 4, color: '#bbb', cursor: 'help', fontSize: 13 }} />
          </Tooltip>
        )}
      </Text>
      <Space size={4}>
        <Button
          type={checked ? 'primary' : 'default'}
          size="small"
          onClick={() => onChange(true)}
          disabled={disabled}
          style={checked ? { background: PRIMARY, borderColor: PRIMARY } : {}}
        >
          {enableText}
        </Button>
        <Button
          type={!checked ? 'primary' : 'default'}
          size="small"
          onClick={() => onChange(false)}
          disabled={disabled}
          style={!checked ? { background: '#999', borderColor: '#999' } : {}}
        >
          {disableText}
        </Button>
      </Space>
    </div>
  </Col>
)

// SubGroupTitle - 简单子分组标题（无帮助内容）
export const SubGroupTitle: React.FC<{ title: string; color?: string }> = ({ title, color = '#3b82f6' }) => (
  <Col span={24}>
    <div style={{ marginTop: 16, marginBottom: 8, paddingBottom: 4, borderBottom: `1px solid ${color}` }}>
      <Text strong style={{ fontSize: 13, color }}>
        {title}
      </Text>
    </div>
  </Col>
)

// SettingButton - 统一的蓝色设置按钮（disabled 时显示锁定图标 + 灰色）
export const SettingButton: React.FC<{ onClick: () => void; loading?: boolean; disabled?: boolean }> = ({ onClick, loading, disabled }) => (
  <Button
    type="primary"
    size="small"
    style={disabled ? disabledBtnStyle : settingBtnStyle}
    onClick={onClick}
    loading={loading}
    disabled={disabled}
    icon={disabled ? <LockOutlined /> : undefined}
  >
    {disabled ? '已锁定' : '设置'}
  </Button>
)

// buildLabelMap - 从字段数组构建 fieldKey → 中文标签 映射
export function buildLabelMap(...fieldArrays: { key: string; label: string }[][]) {
  const map: Record<string, string> = {}
  for (const arr of fieldArrays) {
    for (const f of arr) {
      map[f.key] = f.label
    }
  }
  return map
}

// buildDefaults - 从字段数组构建 fieldKey → 默认值 映射
export function buildDefaults(...fieldArrays: { key: string; default: any }[][]) {
  const map: Record<string, any> = {}
  for (const arr of fieldArrays) {
    for (const f of arr) {
      map[f.key] = f.default
    }
  }
  return map
}

// displayLabel - 拼接 label + unit 作为展示标签
export function displayLabel(f: { label: string; unit?: string }) {
  return f.unit ? `${f.label}(${f.unit})` : f.label
}

// SubGroupHelp - 子分组标题 + 帮助图标（悬浮显示说明）
// hint: 简短提示文案（推荐）；helpItems: 字段级详细说明（向后兼容）
export const SubGroupHelp: React.FC<{
  title: string
  color: string
  hint?: string
  helpItems?: { label: string; value: string }[]
}> = ({ title, color, hint, helpItems }) => {
  const tooltipContent = hint
    ? <span style={{ fontSize: 12 }}>{hint}</span>
    : helpItems
      ? (
        <div style={{ fontSize: 12, lineHeight: 1.8 }}>
          {helpItems.map((item, idx) => (
            <div key={idx}>
              <span style={{ color: '#93c5fd' }}>{item.label}</span>：{item.value}
            </div>
          ))}
        </div>
      )
      : null

  return (
    <Col span={24}>
      <div style={{ marginTop: 16, marginBottom: 8, paddingBottom: 4, borderBottom: `1px solid ${color}` }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontWeight: 600, fontSize: 13, color }}>{title}</span>
          {tooltipContent && (
            <Tooltip overlayStyle={{ maxWidth: 400 }} title={tooltipContent}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color, cursor: 'pointer' }}>
                <InfoCircleOutlined /> 说明
              </span>
            </Tooltip>
          )}
        </div>
      </div>
    </Col>
  )
}
