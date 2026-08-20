// 第一层：设置首页 —— 模块级折叠卡片
// 每个模块（工作模式/电池设置/…）一张可展开卡片：收起显示模块头（accent 图标 + 名称 + 描述），
// 点击展开该模块全部设置项（v1 平铺字段行：左侧标签、右侧控件，行间分隔线，无需再逐项展开）。

import React, { useState } from 'react'
import { Typography, Spin, Collapse, Empty, Alert } from 'antd'
import {
  ControlOutlined, ExperimentOutlined, ThunderboltOutlined,
  ExportOutlined, PoweroffOutlined, BulbOutlined, ToolOutlined, AlertOutlined,
  CodeOutlined, RightOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { MODULES } from '../config/fields'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { FieldRow } from './FieldControl'
import './modulePage.css'

const { Text } = Typography

const MODULE_ICONS: Record<string, React.ReactNode> = {
  mode: <ControlOutlined />,
  battery: <ExperimentOutlined />,
  charge: <ThunderboltOutlined />,
  discharge: <ExportOutlined />,
  output: <PoweroffOutlined />,
  solar: <BulbOutlined />,
  generator: <ToolOutlined />,
  alarm: <AlertOutlined />,
}

interface SettingsHomeProps {
  cfg: DeviceConfigApi
  loading: boolean
  onOpenAdvanced: () => void
}

const SettingsHome: React.FC<SettingsHomeProps> = ({ cfg, loading, onOpenAdvanced }) => {
  const { t } = useTranslation()
  // 模块级展开状态（key = 模块 id），默认全部收起
  const [activeKeys, setActiveKeys] = useState<string[]>([])

  const sections = MODULES.map((m) => {
    const visibleKeys = m.paramKeys.filter((key) => cfg.isVisible(cfg.getMeta(key)))
    // 字段完全不在 schema 且无上报值时隐藏（扩展参数固件未实现），避免整页全是无法读取的项
    const availableKeys = visibleKeys.filter(
      (key) => cfg.schemaMap.has(key) || cfg.getSummaryValue(key) !== undefined,
    )
    return { module: m, keys: availableKeys }
  }).filter((s) => s.keys.length > 0)

  return (
    <Spin spinning={loading}>
      {(cfg.schemaError || cfg.stateError) && (
        <div style={{ marginBottom: 12 }}>
          <QueryErrorAlert error={cfg.schemaError ?? cfg.stateError} onRetry={cfg.refetchAll} />
        </div>
      )}

      {/* 设备从未上报配置：值不可信，避免被误当成真实参数 */}
      {!cfg.schemaError && !cfg.stateError && cfg.controlState && !cfg.hasReportedConfig && (
        <Alert
          type="warning"
          showIcon
          style={{ marginBottom: 12 }}
          message={t('remote.homeNotReported')}
        />
      )}

      {sections.length > 0 ? (
        <Collapse
          ghost
          className="rs-module-collapse"
          expandIconPosition="end"
          activeKey={activeKeys}
          onChange={(keys) => setActiveKeys(Array.isArray(keys) ? (keys as string[]) : [keys])}
          items={sections.map(({ module: m, keys }) => ({
            key: m.id,
            label: (
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                <div
                  style={{
                    width: 30, height: 30, borderRadius: 9, flexShrink: 0,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontSize: 15, color: m.accent,
                    background: `linear-gradient(135deg, ${m.accent}26, ${m.accent}0d)`,
                    border: `1px solid ${m.accent}40`,
                  }}
                >
                  {MODULE_ICONS[m.id]}
                </div>
                <Text strong style={{ fontSize: 15, color: '#111827' }}>{t(m.nameKey)}</Text>
                <Text type="secondary" style={{ fontSize: 12 }}>{t(m.descKey)}</Text>
              </div>
            ),
            children: keys.map((key) => <FieldRow key={key} cfg={cfg} paramKey={key} />),
          }))}
        />
      ) : (
        !loading && (
          <Empty
            description={t('remote3.moduleEmpty')}
            image={Empty.PRESENTED_IMAGE_SIMPLE}
            style={{ padding: '40px 0', background: '#fff', borderRadius: 12, border: '1px solid #edf0f5' }}
          />
        )
      )}

      {/* 高级参数入口（工程师模式） */}
      <div
        role="button"
        tabIndex={0}
        onClick={onOpenAdvanced}
        onKeyDown={(e) => e.key === 'Enter' && onOpenAdvanced()}
        style={{
          display: 'flex', alignItems: 'center', gap: 12,
          background: 'linear-gradient(135deg, #111827, #1f2937)', borderRadius: 12, padding: '14px 18px',
          cursor: 'pointer', boxShadow: '0 1px 4px rgba(17,24,39,0.2)', transition: 'all 0.2s ease',
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'translateY(-2px)'
          e.currentTarget.style.boxShadow = '0 8px 24px rgba(17,24,39,0.3)'
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'none'
          e.currentTarget.style.boxShadow = '0 1px 4px rgba(17,24,39,0.2)'
        }}
      >
        <div
          style={{
            width: 36, height: 36, borderRadius: 10, flexShrink: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 17, color: '#00D4FF', background: 'rgba(0,212,255,0.1)',
            border: '1px solid rgba(0,212,255,0.25)',
          }}
        >
          <CodeOutlined />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <Text strong style={{ fontSize: 14, color: '#fff', display: 'block' }}>{t('remote3.advancedEntry')}</Text>
          <Text style={{ fontSize: 12, color: 'rgba(255,255,255,0.55)' }}>{t('remote3.advancedEntryHint')}</Text>
        </div>
        <RightOutlined style={{ color: 'rgba(255,255,255,0.4)', fontSize: 12 }} />
      </div>
    </Spin>
  )
}

export default SettingsHome
