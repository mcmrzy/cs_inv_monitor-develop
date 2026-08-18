// 设置项渲染组件族（控件渲染沿用 v1：number = Slider + InputNumber 草稿态；boolean = Switch 即时下发；
// enum = Segmented/Radio 即时下发；priority = 上移/下移排序列表）：
// - FieldControlWidget（内部共用）：按 meta.kind 渲染设置控件
// - FieldCardHeader（命名导出）：标题 + 当前值摘要 + 同步徽标 + 只读锁标（Collapse header 用）
// - FieldCardBody（命名导出）：业务说明（i18n remote3.desc.*）+ 控件（折叠卡片 body 用）
// - FieldRow（命名导出）：v1 平铺字段行 —— 左侧「标签 + 徽标」、右侧控件，行间分隔线（模块展开区用）
// - FieldControl（默认导出）：单条 Collapse 包装（AdvancedPanel 工程师模式沿用）

import React, { useEffect, useState } from 'react'
import {
  Collapse,
  Slider,
  InputNumber,
  Switch,
  Segmented,
  Radio,
  Button,
  Tag,
  Tooltip,
  Typography,
  Space,
} from 'antd'
import {
  ArrowUpOutlined,
  ArrowDownOutlined,
  SendOutlined,
  CheckCircleFilled,
  ClockCircleFilled,
  LockOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { decimalsFor, displayUnit, type ResolvedFieldMeta } from '../config/conversion'
import { priorityEnumToOrder, priorityOrderToEnum, type PrioritySource } from '../config/fields'

const { Text } = Typography

const ACCENT = '#00D4FF'
const GREEN = '#00E676'

interface FieldCardProps {
  cfg: DeviceConfigApi
  paramKey: string
}

const PRIORITY_LABEL_KEY: Record<PrioritySource, string> = {
  solar: 'remote3.priority.solar',
  battery: 'remote3.priority.battery',
  utility: 'remote3.priority.utility',
}

// ── 当前值摘要（收起态可见，一眼读出配置现状） ──
const ValueSummary: React.FC<FieldCardProps> = ({ cfg, paramKey }) => {
  const { t, lang } = useTranslation()
  const current = cfg.getEditValue(paramKey)
  const meta = cfg.getMeta(paramKey)

  if (current === undefined) return <Text type="secondary">--</Text>

  if (meta.kind === 'enum' && meta.enumOptions) {
    const semanticKey = meta.enumOptions.find((o) => o.value === current)?.semanticKey
    const label = semanticKey ? cfg.enumLabel(semanticKey) : ''
    return <Text>{label || '--'}</Text>
  }

  if (meta.kind === 'boolean') {
    return <Text>{current !== 0 ? t('remote3.enabled') : t('remote3.disabled')}</Text>
  }

  if (meta.kind === 'number') {
    const unit = displayUnit(meta.unit, lang)
    const decimals = decimalsFor(meta)
    return <Text>{`${parseFloat(current.toFixed(decimals))}${unit ? ` ${unit}` : ''}`}</Text>
  }

  if (meta.kind === 'priority') {
    const order = priorityEnumToOrder(Number(current))
    const first = order[0] as PrioritySource
    return <Text>{t(PRIORITY_LABEL_KEY[first])}</Text>
  }

  return <Text>--</Text>
}

// ── number 控件（独立组件：草稿态 Hooks 必须无条件调用） ──
const NumberField: React.FC<{ cfg: DeviceConfigApi; meta: ResolvedFieldMeta }> = ({ cfg, meta }) => {
  const { t, lang } = useTranslation()
  const paramKey = meta.paramKey
  const current = cfg.getEditValue(paramKey)
  const sending = cfg.sendingKey === paramKey
  const editable = cfg.canEdit(paramKey)
  const hasRange = meta.min !== undefined && meta.max !== undefined
  const decimals = decimalsFor(meta)
  const unit = displayUnit(meta.unit, lang)

  const [draft, setDraft] = useState<number | undefined>(current)
  useEffect(() => {
    setDraft(current)
  }, [current])
  const dirty =
    (draft !== undefined && current !== undefined && draft !== current) ||
    (draft !== undefined && current === undefined)

  const apply = () => {
    if (draft !== undefined) cfg.sendValue(meta, draft)
  }

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
      {hasRange && (
        <Slider
          style={{ flex: 1, minWidth: 140, maxWidth: 320 }}
          min={meta.min}
          max={meta.max}
          step={meta.step ?? 1}
          value={draft}
          disabled={!editable || sending}
          onChange={(v) => setDraft(v as number)}
          tooltip={{
            formatter: (v) => (v === undefined ? '' : `${v.toFixed(decimals)}${unit ? ` ${unit}` : ''}`),
          }}
          trackStyle={{ backgroundColor: ACCENT }}
          handleStyle={{ borderColor: ACCENT, boxShadow: '0 0 0 4px rgba(0,212,255,0.12)' }}
        />
      )}
      <InputNumber
        style={{ width: 128 }}
        min={meta.min}
        max={meta.max}
        step={meta.step ?? 1}
        precision={decimals}
        value={draft}
        disabled={!editable || sending}
        addonAfter={unit || undefined}
        onChange={(v) => setDraft(v ?? undefined)}
        onPressEnter={apply}
      />
      <Button
        type="primary"
        size="small"
        icon={<SendOutlined />}
        loading={sending}
        disabled={!editable || !dirty}
        onClick={apply}
        style={dirty ? { background: ACCENT, borderColor: ACCENT, color: '#111827', fontWeight: 600 } : undefined}
      >
        {t('remote.set')}
      </Button>
    </div>
  )
}

// ── Header：Collapse 的 label（收起态 + 展开态共用） ──
export const FieldCardHeader: React.FC<FieldCardProps> = ({ cfg, paramKey }) => {
  const { t } = useTranslation()
  const label = cfg.fieldLabel(paramKey)
  const sync = cfg.isSynced(paramKey)
  const readOnly = !cfg.canEdit(paramKey)

  const syncTag =
    sync === 'synced' ? (
      <Tooltip title="desired = reported">
        <Tag icon={<CheckCircleFilled />} color="success" style={{ marginInlineEnd: 0 }}>synced</Tag>
      </Tooltip>
    ) : sync === 'pending' ? (
      <Tooltip title={t('remote3.pendingTooltip')}>
        <Tag icon={<ClockCircleFilled />} color="processing" style={{ marginInlineEnd: 0 }}>pending</Tag>
      </Tooltip>
    ) : null

  return (
    <div style={{ flex: 1, minWidth: 0, paddingBlock: 2 }}>
      <Space size={8} wrap>
        <Text strong style={{ fontSize: 14, color: '#111827' }}>{label}</Text>
        <ValueSummary cfg={cfg} paramKey={paramKey} />
        {syncTag}
        {readOnly && (
          <Tooltip title={t('remote3.readOnly')}>
            <LockOutlined style={{ fontSize: 12, color: '#9ca3af' }} />
          </Tooltip>
        )}
      </Space>
    </div>
  )
}

// ── 控件渲染（FieldCardBody / FieldRow 共用）：按 meta.kind 分发 ──
const FieldControlWidget: React.FC<FieldCardProps> = ({ cfg, paramKey }) => {
  const { t } = useTranslation()
  const meta = cfg.getMeta(paramKey)
  const current = cfg.getEditValue(paramKey)
  const sending = cfg.sendingKey === paramKey
  const editable = cfg.canEdit(paramKey)

  let control: React.ReactNode

  if (meta.kind === 'boolean') {
    control = (
      <Switch
        checked={current !== undefined && current !== 0}
        disabled={!editable || sending}
        loading={sending}
        onChange={(v) => cfg.sendValue(meta, v ? 1 : 0)}
        style={{ backgroundColor: current ? GREEN : undefined }}
      />
    )
  } else if (meta.kind === 'enum' && meta.enumOptions) {
    const options = meta.enumOptions.map((o) => ({ label: cfg.enumLabel(o.semanticKey), value: o.value }))
    control =
      options.length <= 4 ? (
        <Segmented
          options={options}
          value={current}
          disabled={!editable || sending}
          onChange={(v) => cfg.sendValue(meta, Number(v))}
        />
      ) : (
        <Radio.Group
          optionType="button"
          buttonStyle="solid"
          options={options}
          value={current}
          disabled={!editable || sending}
          onChange={(e) => cfg.sendValue(meta, Number(e.target.value))}
        />
      )
  } else if (meta.kind === 'priority') {
    const order = priorityEnumToOrder(current ?? 0)
    const move = (idx: number, dir: -1 | 1) => {
      const next = [...order]
      const target = idx + dir
      if (target < 0 || target >= next.length) return
      ;[next[idx], next[target]] = [next[target], next[idx]]
      const enumValue = priorityOrderToEnum(next)
      if (enumValue !== null) cfg.sendValue(meta, enumValue)
    }
    control = (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 220 }}>
        {order.map((src, idx) => (
          <div
            key={src}
            style={{
              display: 'flex', alignItems: 'center', gap: 8,
              padding: '4px 10px', borderRadius: 8,
              background: idx === 0 ? 'rgba(0,212,255,0.08)' : '#f6f8fb',
              border: idx === 0 ? `1px solid ${ACCENT}` : '1px solid #eef1f6',
            }}
          >
            <Text strong style={{ fontSize: 12, color: idx === 0 ? '#0891b2' : '#9ca3af', width: 14 }}>{idx + 1}</Text>
            <Text style={{ fontSize: 13, flex: 1 }}>{t(PRIORITY_LABEL_KEY[src])}</Text>
            <Button
              type="text" size="small" icon={<ArrowUpOutlined />}
              disabled={!editable || sending || idx === 0}
              onClick={() => move(idx, -1)}
            />
            <Button
              type="text" size="small" icon={<ArrowDownOutlined />}
              disabled={!editable || sending || idx === order.length - 1}
              onClick={() => move(idx, 1)}
            />
          </div>
        ))}
        <Text type="secondary" style={{ fontSize: 11 }}>{t('remote3.priorityHint')}</Text>
      </div>
    )
  } else if (meta.kind === 'number') {
    control = <NumberField cfg={cfg} meta={meta} />
  } else {
    control = null
  }

  return <>{control}</>
}

// ── Body：Collapse 的 children（业务说明 + 控件） ──
export const FieldCardBody: React.FC<FieldCardProps> = ({ cfg, paramKey }) => {
  const { t, hasTranslation } = useTranslation()
  const descKey = `remote3.desc.${paramKey}`

  return (
    <div style={{ padding: '4px 4px 16px' }}>
      {hasTranslation(descKey) && (
        <Text type="secondary" style={{ display: 'block', marginBottom: 12, lineHeight: 1.7, maxWidth: 620 }}>
          {t(descKey)}
        </Text>
      )}
      <div style={{ marginTop: 4 }}>
        <FieldControlWidget cfg={cfg} paramKey={paramKey} />
      </div>
    </div>
  )
}

// ── Row：v1 平铺字段行（模块展开区用）—— 左侧「标签 + 徽标 + 锁标」，右侧控件，行间分隔线 ──
export const FieldRow: React.FC<FieldCardProps> = ({ cfg, paramKey }) => {
  const { t } = useTranslation()
  const label = cfg.fieldLabel(paramKey)
  const sync = cfg.isSynced(paramKey)
  const readOnly = !cfg.canEdit(paramKey)

  const syncTag =
    sync === 'synced' ? (
      <Tooltip title="desired = reported">
        <Tag icon={<CheckCircleFilled />} color="success" style={{ marginInlineEnd: 0 }}>synced</Tag>
      </Tooltip>
    ) : sync === 'pending' ? (
      <Tooltip title={t('remote3.pendingTooltip')}>
        <Tag icon={<ClockCircleFilled />} color="processing" style={{ marginInlineEnd: 0 }}>pending</Tag>
      </Tooltip>
    ) : null

  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap',
        padding: '14px 4px', borderBottom: '1px solid #f0f3f8',
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        <Space size={8} wrap>
          <Text strong style={{ fontSize: 14, color: '#111827' }}>{label}</Text>
          {syncTag}
          {readOnly && (
            <Tooltip title={t('remote3.readOnly')}>
              <LockOutlined style={{ fontSize: 12, color: '#9ca3af' }} />
            </Tooltip>
          )}
        </Space>
      </div>
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <FieldControlWidget cfg={cfg} paramKey={paramKey} />
      </div>
    </div>
  )
}

// ── 默认导出：单条 Collapse（AdvancedPanel 工程师模式沿用，默认收起） ──
const FieldControl: React.FC<FieldCardProps> = ({ cfg, paramKey }) => {
  const [activeKeys, setActiveKeys] = useState<string[]>([])
  return (
    <Collapse
      ghost
      activeKey={activeKeys}
      onChange={(keys) => setActiveKeys(Array.isArray(keys) ? keys : [keys])}
      items={[
        {
          key: paramKey,
          label: <FieldCardHeader cfg={cfg} paramKey={paramKey} />,
          children: <FieldCardBody cfg={cfg} paramKey={paramKey} />,
        },
      ]}
    />
  )
}

export default FieldControl
