/**
 * 采样明细表：曲线之外的第二只眼睛。
 *
 * 为什么要有表：曲线看趋势，但调试/售后时常要「报数」——某个时刻的准确值、
 * 电池是充电还是放电、哪个点被固件脏值污染。曲线把越界点剔了，表格必须原样留着
 * 并标红，否则就是拿掉证据。表格还带窗口内最小/最大汇总行与 CSV 导出，便于留档。
 *
 * 表格用后台默认 antd 主题（白底），只对数值列做等宽字体与越界标红。
 */
import React, { useMemo } from 'react'
import { Table, Tag, Tooltip, Typography } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { WarningOutlined } from '@ant-design/icons'

import { formatInTimezone } from '@/utils/timezone'
import type { DebugSample } from '@/services/deviceApi'
import useTranslation from '@/hooks/useTranslation'
import {
  SERIES_DEFS,
  formatSeriesValue,
  isDerived,
  isOutOfRange,
  rangeText,
  readSeries,
  type SeriesKey,
} from './debugMetrics'
import { computeSeriesStat, qualityFlagsOf, qualitySeverity } from './debugAnalysis'
import { DEBUG_TEXT, DEBUG_TITLE } from './debugTheme'

const { Text } = Typography

interface DebugTableProps {
  /** 升序样本（与曲线同一份数据） */
  samples: readonly DebugSample[]
  keys: readonly SeriesKey[]
  /** 已翻译的曲线名（含「（计算）」后缀） */
  labels: Record<string, string>
  /** 不带后缀的短名（列头第一行） */
  shortLabels: Record<string, string>
  timezone: string
}

interface TableRow {
  key: string
  time: string
  quality: number | null | undefined
  /** 是否为最新一行 */
  latest: boolean
  values: Record<string, number | null>
}

const DebugTable: React.FC<DebugTableProps> = ({ samples, keys, labels, shortLabels, timezone }) => {
  const { t } = useTranslation()

  const rows = useMemo<TableRow[]>(() => {
    const out: TableRow[] = []
    for (let i = samples.length - 1; i >= 0; i -= 1) {
      const sample = samples[i]
      const values: Record<string, number | null> = {}
      for (const key of keys) values[key] = readSeries(sample, key)
      out.push({
        key: `${sample.time}-${i}`,
        time: sample.time,
        quality: sample.quality_flags,
        latest: i === samples.length - 1,
        values,
      })
    }
    return out
  }, [samples, keys])

  /** 窗口内最小/最大（有效点）：汇总行用，越界脏值不参与 */
  const stats = useMemo(() => keys.map((key) => computeSeriesStat(samples, key)), [samples, keys])

  const columns = useMemo<ColumnsType<TableRow>>(() => {
    const cols: ColumnsType<TableRow> = [
      {
        title: t('deviceDetail.debug.table.time'),
        dataIndex: 'time',
        width: 104,
        fixed: 'left',
        render: (value: string, row) => (
          <Tooltip title={formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss')}>
            <span style={{ fontFamily: 'monospace', color: DEBUG_TITLE }}>{formatInTimezone(value, timezone, 'HH:mm:ss')}</span>
            {row.latest && (
              <Tag color="success" style={{ marginInlineStart: 6, marginInlineEnd: 0, transform: 'scale(0.85)' }}>
                {t('deviceDetail.debug.table.latest')}
              </Tag>
            )}
          </Tooltip>
        ),
      },
      {
        title: t('deviceDetail.debug.table.quality'),
        dataIndex: 'quality',
        width: 78,
        align: 'center',
        render: (flags: number) => {
          const severity = qualitySeverity(flags)
          if (!severity) return <Text style={{ color: '#bfbfbf' }}>—</Text>
          const detail = qualityFlagsOf(flags)
            .map((f) => t(f.labelKey))
            .join('、')
          return (
            <Tooltip title={detail}>
              <Tag color={severity === 'error' ? 'error' : 'warning'} style={{ marginInlineEnd: 0 }}>
                {t('deviceDetail.debug.table.qualityBad')}
              </Tag>
            </Tooltip>
          )
        },
      },
    ]

    for (const key of keys) {
      const def = SERIES_DEFS[key]
      const derived = isDerived(key)
      // 两行表头：短名 + 「计算 · 单位」副行。中文长名 + 后缀挤在一行会断字，
      // 副行小字反而把「实测 / 计算」和量纲标得更清楚。
      cols.push({
        title: (
          <div>
            <div style={{ color: DEBUG_TITLE }}>{shortLabels[key] ?? labels[key] ?? key}</div>
            <div style={{ fontSize: 11, fontWeight: 400, color: DEBUG_TEXT }}>
              {derived ? `${t('deviceDetail.debug.table.derivedTag')} · ` : ''}
              {def?.unit}
            </div>
          </div>
        ),
        dataIndex: ['values', key],
        width: 116,
        align: 'right',
        render: (_: unknown, row) => {
          const value = row.values[key]
          if (value == null) return <Text style={{ color: '#bfbfbf' }}>—</Text>
          const bad = isOutOfRange(key, value)
          const text = (
            <span
              style={{
                fontFamily: 'monospace',
                color: bad ? '#cf1322' : DEBUG_TITLE,
                fontWeight: bad ? 600 : 400,
              }}
            >
              {formatSeriesValue(key, value)}
              {bad && <WarningOutlined style={{ marginInlineStart: 4 }} />}
            </span>
          )
          return bad
            ? <Tooltip title={t('deviceDetail.debug.table.outOfRange', { range: rangeText(key) })}>{text}</Tooltip>
            : text
        },
      })
    }
    return cols
  }, [keys, labels, shortLabels, t, timezone])

  if (rows.length === 0) {
    return (
      <div style={{ padding: '24px 0', textAlign: 'center', color: DEBUG_TEXT, fontSize: 13 }}>
        {t('deviceDetail.debug.table.empty')}
      </div>
    )
  }

  return (
    <Table<TableRow>
      size="small"
      rowKey="key"
      columns={columns}
      dataSource={rows}
      scroll={{ x: 'max-content' }}
      pagination={{
        size: 'small',
        defaultPageSize: 20,
        pageSizeOptions: [20, 50, 100],
        showSizeChanger: true,
        showTotal: (total) => t('deviceDetail.debug.table.total', { total }),
        style: { marginBottom: 0 },
      }}
      summary={() => (
        <>
          {(['min', 'max'] as const).map((kind) => (
            <Table.Summary.Row key={kind} style={{ background: '#fafafa' }}>
              <Table.Summary.Cell index={0} colSpan={2}>
                <span style={{ color: DEBUG_TEXT, fontSize: 12 }}>
                  {t(kind === 'min' ? 'deviceDetail.debug.table.summaryMin' : 'deviceDetail.debug.table.summaryMax')}
                </span>
              </Table.Summary.Cell>
              {stats.map((stat, colIdx) => (
                <Table.Summary.Cell key={stat.key} index={colIdx + 2} align="right">
                  <span style={{ fontFamily: 'monospace', color: DEBUG_TEXT, fontSize: 12 }}>
                    {stat[kind] == null ? '—' : formatSeriesValue(stat.key, stat[kind])}
                  </span>
                </Table.Summary.Cell>
              ))}
            </Table.Summary.Row>
          ))}
        </>
      )}
    />
  )
}

export default DebugTable
