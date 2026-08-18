// 通用字段行：标签 + 同步徽标 + 按类型渲染的控件
// number → Slider + InputNumber 联动（草稿态，点击「设置」下发）
// boolean → Switch 即时下发；enum → Segmented 即时下发；priority → 上移/下移排序列表

import React, { useEffect, useState } from 'react'
import { Slider, InputNumber, Switch, Segmented, Radio, Button, Tag, Tooltip, Typography, Space } from 'antd'
import { ArrowUpOutlined, ArrowDownOutlined, SendOutlined, CheckCircleFilled, ClockCircleFilled } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { decimalsFor, displayUnit } from '../config/conversion'
import { priorityEnumToOrder, priorityOrderToEnum, type PrioritySource } from '../config/fields'

const { Text } = Typography

const ACCENT = '#00D4FF'
const GREEN = '#00E676'

interface FieldControlProps {
  cfg: DeviceConfigApi
  paramKey: string
}

const PRIORITY_LABEL_KEY: Record<PrioritySource, string> = {
  solar: 'remote3.priority.solar',
  battery: 'remote3.priority.battery',
  utility: 'remote3.priority.utility',
}

const FieldControl: React.FC<FieldControlProps> = ({ cfg, paramKey }) => {
  const { t, lang } = useTranslation()
  const meta = cfg.getMeta(paramKey)
  const current = cfg.getEditValue(paramKey)
  const sending = cfg.sendingKey === paramKey
  const editable = cfg.canEdit(paramKey)
  const sync = cfg.isSynced(paramKey)

  const [draft, setDraft] = useState<number | undefined>(current)
  useEffect(() => {
    setDraft(current)
  }, [current])
  const dirty = draft !== undefined && current !== undefined && draft !== current
    || (draft !== undefined && current === undefined)

  const label = cfg.fieldLabel(paramKey)
  const unit = displayUnit(meta.unit, lang)

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
  } else {
    // number：Slider + InputNumber 联动（有量程才显示滑块）
    const hasRange = meta.min !== undefined && meta.max !== undefined
    const decimals = decimalsFor(meta)
    const apply = () => {
      if (draft !== undefined) cfg.sendValue(meta, draft)
    }
    control = (
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 300 }}>
        {hasRange && (
          <Slider
            style={{ flex: 1, minWidth: 140 }}
            min={meta.min}
            max={meta.max}
            step={meta.step ?? 1}
            value={draft}
            disabled={!editable || sending}
            onChange={(v) => setDraft(v as number)}
            tooltip={{ formatter: (v) => (v === undefined ? '' : `${v.toFixed(decimals)}${unit ? ` ${unit}` : ''}`) }}
            trackStyle={{ backgroundColor: ACCENT }}
            handleStyle={{ borderColor: ACCENT, boxShadow: `0 0 0 4px rgba(0,212,255,0.12)` }}
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

  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 16,
        padding: '14px 4px', borderBottom: '1px solid #f0f3f8',
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        <Space size={8} wrap>
          <Text strong style={{ fontSize: 14, color: '#111827' }}>{label}</Text>
          {syncTag}
        </Space>
        <div>
          <Text code style={{ fontSize: 11, color: '#b3bcc9' }}>{paramKey}</Text>
        </div>
      </div>
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>{control}</div>
    </div>
  )
}

export default FieldControl
