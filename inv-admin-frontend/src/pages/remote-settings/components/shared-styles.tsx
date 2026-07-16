import React from 'react'
import { Button, Space, Typography, Col } from 'antd'

const { Text } = Typography

// 主题色
export const PRIMARY = '#4f6ef7'

// 每个分组颜色
export const SECTION_COLORS: Record<string, string> = {
  general: '#4f6ef7',
  application: '#7c3aed',
  parallel: '#06b6d4',
  gridConnection: '#3b82f6',
  powerControl: '#8b5cf6',
  charge: '#10b981',
  discharge: '#f59e0b',
  other: '#6b7280',
  reset: '#ef4444',
}

// 设置按钮样式
export const settingBtnStyle = { background: PRIMARY, borderColor: PRIMARY }

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
}

export const FieldRow: React.FC<FieldRowProps> = ({ label, range, children, full }) => (
  <Col span={full ? 24 : 12}>
    <div style={fieldRowStyle}>
      <Text style={labelStyle}>{label}</Text>
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
}

export const SwitchField: React.FC<SwitchFieldProps> = ({
  label, checked, onChange, enableText = '启用', disableText = '禁用',
}) => (
  <Col span={12}>
    <div style={fieldRowStyle}>
      <Text style={labelStyle}>{label}</Text>
      <Space size={4}>
        <Button
          type={checked ? 'primary' : 'default'}
          size="small"
          onClick={() => onChange(true)}
          style={checked ? { background: PRIMARY, borderColor: PRIMARY } : {}}
        >
          {enableText}
        </Button>
        <Button
          type={!checked ? 'primary' : 'default'}
          size="small"
          onClick={() => onChange(false)}
          style={!checked ? { background: '#999', borderColor: '#999' } : {}}
        >
          {disableText}
        </Button>
      </Space>
    </div>
  </Col>
)

// SettingButton - 统一的蓝色设置按钮
export const SettingButton: React.FC<{ onClick: () => void; loading?: boolean }> = ({ onClick, loading }) => (
  <Button type="primary" size="small" style={settingBtnStyle} onClick={onClick} loading={loading}>
    设置
  </Button>
)
