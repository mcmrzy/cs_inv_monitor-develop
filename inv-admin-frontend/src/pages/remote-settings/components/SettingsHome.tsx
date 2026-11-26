// 第一层：设置首页 —— 模块级折叠卡片
// 每个模块（工作模式/电池设置/…）一张可展开卡片：收起显示模块头（accent 图标 + 名称 + 描述），
// 点击展开该模块全部设置项（v1 平铺字段行：左侧标签、右侧控件，行间分隔线，无需再逐项展开）。

import React, { useState } from 'react'
import { Typography, Spin, Collapse, Empty, Alert, Input } from 'antd'
import {
  ControlOutlined, ExperimentOutlined, ThunderboltOutlined,
  ExportOutlined, PoweroffOutlined, BulbOutlined, ToolOutlined, AlertOutlined,
  ClockCircleOutlined, CodeOutlined, RightOutlined, SearchOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { MODULES, type SettingsModule } from '../config/fields'
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
  other: <CodeOutlined />,
  bms: <ExperimentOutlined />,
  parallel: <ControlOutlined />,
  output2: <PoweroffOutlined />,
  socket: <PoweroffOutlined />,
  schedule: <ClockCircleOutlined />,
}

const OTHER_MODULE: SettingsModule = {
  id: 'other', nameKey: 'remote3.otherSettings', descKey: '', accent: '#64748b',
  paramKeys: [], summaryKeys: [],
}

const EXTRA_MODULES: SettingsModule[] = [
  ...['bms', 'parallel', 'output2', 'socket', 'schedule'].map((id) => ({
    id, nameKey: `remote3.module.${id}`, descKey: '', accent: '#64748b',
    paramKeys: [], summaryKeys: [],
  })),
  OTHER_MODULE,
]

const MODULE_FOR_GROUP: Record<string, string> = {
  general: 'mode', application: 'output', charge: 'charge', equalize: 'charge',
  discharge: 'discharge', soc: 'discharge', gen: 'generator', battery: 'battery',
  system: 'alarm', parallel: 'parallel', bms: 'bms', output2: 'output2',
  socket: 'socket', schedule: 'schedule',
}

interface SettingsHomeProps {
  cfg: DeviceConfigApi
  loading: boolean
  onOpenAdvanced: () => void
}

const SettingsHome: React.FC<SettingsHomeProps> = ({ cfg, loading, onOpenAdvanced }) => {
  const { t } = useTranslation()
  // 模块级展开状态（key = 模块 id），默认全部收起
  const [activeKeys, setActiveKeys] = useState<string[] | null>(null)
  const [search, setSearch] = useState('')
  const query = search.trim().toLowerCase()
  const available = new Set(cfg.schemaItems
    .filter(({ param_key, catalog_access }) => catalog_access || cfg.isVisible(cfg.getMeta(param_key)))
    .sort((a, b) => a.sort_order - b.sort_order || a.param_key.localeCompare(b.param_key))
    .map(({ param_key }) => param_key))
  for (const [key, value] of Object.entries(cfg.reported)) {
    if (!cfg.schemaMap.has(key) && ['number', 'boolean', 'string'].includes(typeof value)) available.add(key)
  }
  const sections = [...MODULES, ...EXTRA_MODULES].map((module) => ({
    module,
    keys: module.paramKeys.filter((key) => available.delete(key)),
  }))
  for (const key of available) {
    const field = cfg.schemaMap.get(key)
    const id = MODULE_FOR_GROUP[field?.sub_group ?? ''] ?? MODULE_FOR_GROUP[field?.group_code ?? ''] ?? 'other'
    sections.find(({ module }) => module.id === id)?.keys.push(key)
  }
  const matches = sections.map(({ module, keys }) => ({
    module,
    keys: !query || t(module.nameKey).toLowerCase().includes(query)
      ? keys
      : keys.filter((key) => `${cfg.fieldLabel(key)} ${key}`.toLowerCase().includes(query)),
  })).filter(({ keys }) => keys.length > 0)

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

      {sections.some(({ keys }) => keys.length > 0) && (
        <Input
          type="search"
          aria-label={t('remote3.searchSettings')}
          placeholder={t('remote3.searchSettings')}
          prefix={<SearchOutlined />}
          allowClear
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          style={{ maxWidth: 420, marginBottom: 12 }}
        />
      )}
      {matches.length > 0 ? (
        <Collapse
          ghost
          className="rs-module-collapse"
          expandIconPosition="end"
          activeKey={query ? matches.map(({ module }) => module.id) : (activeKeys ?? [matches[0].module.id])}
          onChange={(keys) => setActiveKeys(Array.isArray(keys) ? (keys as string[]) : [keys])}
          items={matches.map(({ module: m, keys }) => ({
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
                {m.descKey && <Text type="secondary" style={{ fontSize: 12 }}>{t(m.descKey)}</Text>}
              </div>
            ),
            children: keys.map((key) => <FieldRow key={key} cfg={cfg} paramKey={key} reportedOnly={!cfg.schemaMap.has(key) || Boolean(cfg.schemaMap.get(key)?.catalog_access)} />),
          }))}
        />
      ) : (
        !loading && (
          <Empty
            description={
              query ? t('remote3.noMatchingSettings') : cfg.modelCommandsMissing
                ? t('remote.schema.emptyModelCommands')
                : t('remote3.moduleEmpty')
            }
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
