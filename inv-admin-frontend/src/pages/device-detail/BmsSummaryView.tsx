import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { Alert, Button, Spin, Tooltip } from 'antd'
import { CheckCircleOutlined, DisconnectOutlined, ReloadOutlined, DownloadOutlined,
  InfoCircleOutlined, WarningOutlined, DashboardOutlined, AppstoreOutlined, SafetyOutlined } from '@ant-design/icons'
import ReactECharts from '@/lib/echarts'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import { bmsAvailability, cellExtrema, summaryFlags, summaryNumber, summaryTimestamp,
  summaryWord, SUMMARY_FIELDS, type BmsSummary, type SummaryFlag } from './bmsSummary'
import './bmsSummary.css'

interface Props { summary: BmsSummary; loading?: boolean; error?: unknown; onRefresh: () => void }
type View = 'overview' | 'cells' | 'diagnostics'
const cellName = (index: number) => `C${String(index + 1).padStart(2, '0')}`
const hex = (value: number | null) => value === null ? '--' : `0x${value.toString(16).padStart(4, '0').toUpperCase()}`

function Metric({ label, value, unit, subtle }: { label: ReactNode; value: string; unit?: string; subtle?: string }) {
  return <div className="cmd08-metric"><div className="cmd08-muted cmd08-label">{label}</div>
    <div className="cmd08-number">{value}{value !== '--' && unit && <span>{unit}</span>}</div>
    {subtle && <div className="cmd08-muted cmd08-subtle">{subtle}</div>}</div>
}
function Heading({ title, right }: { title: string; right?: ReactNode }) {
  return <div className="cmd08-heading"><h3>{title}</h3>{right}</div>
}

export function BmsSummaryEmpty({ loading, error, onRefresh }: Omit<Props, 'summary'>) {
  const { t } = useTranslation()
  const s = (key: string) => t(`deviceDetail.summary.${key}`)
  return <div className="cmd08-bms" data-testid="cmd08-bms" data-availability="absent">
    <header className="cmd08-header"><h2>{s('title')}</h2><Tooltip title={s('refresh')}><Button aria-label={s('refresh')}
      icon={<ReloadOutlined spin={loading} />} onClick={onRefresh} disabled={loading} /></Tooltip></header>
    {error != null && <Alert type="warning" showIcon message={s('refreshError')} />}
    <Spin spinning={loading}><div className="cmd08-absent"><DisconnectOutlined /><h3>{s(loading ? 'loading' : 'absent')}</h3>
      {!loading && <p>{s('absentDescription')}</p>}</div></Spin>
  </div>
}

export default function BmsSummaryView({ summary, loading = false, error, onRefresh }: Props) {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const s = (key: string, params?: Record<string, string | number>) => t(`deviceDetail.summary.${key}`, params)
  const b = (key: string) => t(`deviceDetail.bms.${key}`)
  const [now, setNow] = useState(Date.now)
  const [view, setView] = useState<View>('overview')
  const [selected, setSelected] = useState(0)
  // Fetching can fail or pause in a background tab; expiration must still mask the snapshot.
  useEffect(() => {
    const tick = () => setNow(Date.now())
    const timer = window.setInterval(tick, 1_000)
    document.addEventListener('visibilitychange', tick)
    window.addEventListener('focus', tick)
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', tick); window.removeEventListener('focus', tick) }
  }, [])
  const availability = bmsAvailability(summary, now)
  const live = availability === 'live'
  const v = summary.values
  const flags = summaryFlags(summary)
  const cells = live ? summary.cells : Array<number | null>(16).fill(null)
  const extremes = cellExtrema(cells)
  const balance = live ? summaryWord(v.balance_status) : null
  const n = (key: keyof typeof v) => live ? summaryNumber(v[key]) : null
  const display = (value: number | null, precision = 0) => value === null ? '--' : value.toFixed(precision)
  const percentage = (key: 'soc' | 'soh') => {
    const value = n(key)
    return value !== null && value >= 0 && value <= 100 ? value : null
  }
  const soc = percentage('soc')
  const date = (value: unknown) => summaryTimestamp(value) === null ? '--' : formatInTimezone(String(value), timezone, 'YYYY-MM-DD HH:mm:ss')
  const historical = !live ? `${s('historical')} · ` : ''
  const bitName = (flag: SummaryFlag) => {
    if (['chargerOv', 'cellFault', 'chargeMosOn', 'dischargeMosOn', 'chargeLimiter', 'chargeReversed', 'heater'].includes(flag.key)) return s(flag.key)
    if (['chgMosFault', 'dsgMosFault', 'ntcBreak', 'afeComm', 'sc'].includes(flag.key)) return b(`fault.${flag.key}`)
    if (flag.key === 'charging' || flag.key === 'discharging') return b(flag.key)
    return b(`alarm.${flag.key}`)
  }
  const operationLabel = flags.operations.value === null ? s('unknown') : flags.operations.active.map(bitName).join(' · ') || s('noState')
  const stateLabel = live ? b('bmsOnline') : s(availability)
  const chartOption = useMemo(() => {
    const extent = cellExtrema(live ? summary.cells : Array(16).fill(null))
    const spread = extent.spread ?? 0
    const padding = Math.max(5, Math.ceil(spread * .2))
    const balanceWord = live ? summaryWord(summary.values.balance_status) : null
    return {
      animation: false,
      grid: { top: 12, bottom: 28, left: 48, right: 10 },
      tooltip: { trigger: 'axis', valueFormatter: (value: unknown) => typeof value === 'number' ? `${value} mV` : '--' },
      xAxis: { type: 'category', data: summary.cells.map((_, i) => i + 1), axisTick: { show: false }, axisLine: { lineStyle: { color: '#dce3e6' } }, axisLabel: { interval: 0, fontSize: 10, color: '#5d7079' } },
      yAxis: { type: 'value', min: extent.min === null ? undefined : Math.max(0, extent.min - padding),
        max: extent.max === null ? undefined : extent.max + padding, axisLabel: { fontSize: 10, color: '#5d7079' }, splitLine: { lineStyle: { color: '#edf0f2' } } },
      series: [{ type: 'bar', barMaxWidth: 23, data: summary.cells.map((value, i) => ({ value,
        itemStyle: { color: value === extent.max ? '#dca342' : value === extent.min ? '#5c90c8' : '#88b6aa',
          borderColor: balanceWord !== null && (balanceWord & (1 << i)) ? '#16795b' : 'transparent',
          borderWidth: balanceWord !== null && (balanceWord & (1 << i)) ? 2 : 0, borderRadius: [2, 2, 0, 0] } })) }],
    }
  }, [summary, live])
  const exportSnapshot = () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify({ availability, bms_summary: v }, null, 2)], { type: 'application/json' }))
    const anchor = document.createElement('a')
    anchor.href = url; anchor.download = 'bms-cmd08-snapshot.json'; anchor.click()
    window.setTimeout(() => URL.revokeObjectURL(url), 1_000)
  }
  const temperature = <section className="cmd08-temperatures">
    <Heading title={b('temperatures')} />
    <div className="cmd08-three"><Metric label="MOS" value={display(n('mos_temp'), 1)} unit="°C" />
      <Metric label="PCB" value={display(n('pcb_temp'), 1)} unit="°C" />
      <Metric label={b('tempEnv')} value={display(n('env_temp'), 1)} unit="°C" /></div>
    <div className="cmd08-unavailable"><span>{s('cellTemps')}</span><span>{s('unavailable')}</span></div>
    <div className="cmd08-unavailable"><span>{s('extremeTemps')}</span><span>{s('unavailable')}</span></div>
  </section>
  const status = <section className="cmd08-flags">
    <Heading title={`${historical}${s('flags')}`} right={<span className={live && flags.allKnown && !flags.activeCount ? 'cmd08-good' : 'cmd08-muted'}>
      {flags.allKnown ? s(flags.activeCount ? 'activeCount' : 'noActive', { count: flags.activeCount }) : s('unknownFlags')}</span>} />
    {(['warning', 'protection', 'fault'] as const).map(group => <div className="cmd08-flag-row" key={group}>
      <span className="cmd08-muted">{s(group)}</span><div className={flags[group].active.length ? group === 'warning' ? 'cmd08-warning' : 'cmd08-danger' : ''}>
        {flags[group].value === null ? s('unknown') : <>{flags[group].active.map(flag => <Tooltip title={`bit ${flag.bit}`} key={flag.bit}><span className="cmd08-flag-name">{bitName(flag)}</span></Tooltip>)}
          {flags[group].reserved.map(bit => <span className="cmd08-flag-name cmd08-muted" key={bit}>{s('reserved', { bit })}</span>)}
          {!flags[group].active.length && !flags[group].reserved.length && s('notReported')}</>}</div>
      {view === 'diagnostics' && <code>{hex(flags[group].value)}</code>}
    </div>)}
    <div className="cmd08-operation"><span className="cmd08-muted">{s('operations')}</span><span>{historical}{operationLabel}</span></div>
  </section>
  const cellSection = <section>
    <Heading title={s('consistency')} right={<span className="cmd08-muted">{live ? s('validCells', { count: extremes.count }) : '-- / 16'}</span>} />
    <div className="cmd08-three cmd08-cell-stats"><Metric label={s('maxVoltage')} value={display(extremes.max)} unit="mV" subtle={extremes.maxIndex === null ? undefined : cellName(extremes.maxIndex)} />
      <Metric label={s('minVoltage')} value={display(extremes.min)} unit="mV" subtle={extremes.minIndex === null ? undefined : cellName(extremes.minIndex)} />
      <Metric label={s('spread')} value={display(extremes.spread)} unit="mV" /></div>
    <div className="cmd08-legend"><span><i className="cmd08-highest" />{b('max')}</span><span><i className="cmd08-lowest" />{b('min')}</span><span><i className="cmd08-balanced" />{b('balancing')}</span><span>mV</span></div>
    {live && extremes.count ? <ReactECharts option={chartOption} notMerge style={{ height: 215 }} onChartReady={chart => chart.on('click', params => {
      if (params.componentType === 'series' && typeof params.dataIndex === 'number' && params.dataIndex >= 0 && params.dataIndex < 16) setSelected(params.dataIndex)
    })} /> : <div className="cmd08-chart-empty"><DisconnectOutlined />{s('cellsUnavailable')}</div>}
    <div className="cmd08-cell-grid" role="group" aria-label={b('cellVoltages')}>
      {cells.map((value, i) => <button key={i} aria-label={cellName(i)} aria-pressed={selected === i}
        className={`cmd08-cell ${selected === i ? 'selected' : ''}`} onClick={() => setSelected(i)}>
        <span>{cellName(i)}{balance !== null && !!(balance & (1 << i)) && <i className="cmd08-balance-dot" />}</span><strong>{display(value)}</strong></button>)}
    </div>
    <div className="cmd08-selection" data-testid="cmd08-selected-cell"><strong>{cellName(selected)}</strong><span>{display(cells[selected])}{cells[selected] !== null && ' mV'}</span>
      <span className="cmd08-muted">{balance === null ? s('unknown') : s(balance & (1 << selected) ? 'balancing' : 'notBalancing')}</span></div>
  </section>
  const capacities = <section className="cmd08-capacities"><Heading title={s('capacity')} right={<span className="cmd08-muted">Ah</span>} />
    <div className="cmd08-three"><Metric label={s('remainCapacity')} value={display(n('capacity_remain'), 3)} />
      <Metric label={s('fullCapacity')} value={display(n('capacity_full'), 3)} />
      <Metric label={s('designCapacity')} value={display(n('capacity_design'), 3)} /></div></section>
  const reportedMismatch = live && ((summaryNumber(v.max_cell_voltage) !== null && extremes.max !== summaryNumber(v.max_cell_voltage)) ||
    (summaryNumber(v.min_cell_voltage) !== null && extremes.min !== summaryNumber(v.min_cell_voltage)))
  const diagnosticValue = (key: typeof SUMMARY_FIELDS[number]) => {
    const value = v[key]
    if (v.layout === 0 && ['cell_temperatures', 'max_cell_temp', 'min_cell_temp', 'charging_voltage'].includes(key)) return key === 'cell_temperatures' ? '[null,null,null,null]' : '--'
    if (['updated_at', 'reported_at', 'expires_at'].includes(key)) return date(value)
    if (value === null || value === undefined) return '--'
    if (typeof value === 'number') {
      const units: Record<string, string> = { voltage: 'V', current: 'A', soc: '%', soh: '%', capacity_remain: 'Ah', capacity_full: 'Ah', capacity_design: 'Ah', max_cell_voltage: 'mV', min_cell_voltage: 'mV', mos_temp: '°C', pcb_temp: '°C', env_temp: '°C', age_ms: 'ms' }
      return `${value}${units[key] ? ` ${units[key]}` : ''}`
    }
    return JSON.stringify(value)
  }
  const details = <section className="cmd08-diagnostics"><Heading title={s('diagnostics')} right={<span className="cmd08-muted">ARM CMD 0x08</span>} />
    {!live && <div className="cmd08-historical">{s('historicalOnly')}</div>}
    <details><summary>{s('sampling')}<span>Layout {summaryNumber(v.layout) ?? '--'}</span></summary>
      <dl>{(['updated_at', 'reported_at', 'expires_at', 'age_ms', 'battery_count', 'bms_online'] as const).map(key => <div key={key}><dt>{s(key)}</dt><dd>{diagnosticValue(key)}</dd></div>)}</dl>
    </details>
    <details><summary>{s('reportedValues')}<span>{s('snapshot')}</span></summary>
      {reportedMismatch && <div className="cmd08-historical">{s('extremaMismatch')}</div>}
      <dl>{SUMMARY_FIELDS.filter(key => !['raw_bytes', 'updated_at', 'reported_at', 'expires_at', 'age_ms', 'battery_count', 'bms_online'].includes(key)).map(key =>
        <div key={key}><dt>{s(`field.${key}`)}<code>{key}</code></dt><dd>{diagnosticValue(key)}{key.endsWith('_raw') && key !== 'soc_raw' && key !== 'soh_raw' && <small>{s('unitUnconfirmed')}</small>}</dd></div>)}</dl>
    </details>
    <details><summary>{s('rawPayload')}<span>{summary.rawBytes ? '100 bytes' : s('unavailable')}</span></summary>
      <pre className="cmd08-raw">{summary.rawBytes ? summary.rawBytes.map(value => value.toString(16).padStart(2, '0').toUpperCase()).join(' ') : s('invalidPayload')}</pre>
    </details>
  </section>

  return <div className="cmd08-bms" data-testid="cmd08-bms" data-availability={availability}>
    <header className="cmd08-header"><h2>{s('title')}</h2><div className="cmd08-status-actions">
      <span role="status" className={live ? 'cmd08-good' : 'cmd08-muted'}>{live ? <CheckCircleOutlined /> : <DisconnectOutlined />}{stateLabel}</span>
      <span className="cmd08-muted cmd08-updated">{s('updated_at')}: {date(v.updated_at)}</span>
      <Tooltip title={s('refresh')}><Button aria-label={s('refresh')} icon={<ReloadOutlined spin={loading} />} onClick={onRefresh} disabled={loading} /></Tooltip>
      <Tooltip title={s('export')}><Button aria-label={s('export')} icon={<DownloadOutlined />} onClick={exportSnapshot} /></Tooltip>
    </div></header>
    {error != null && <Alert className="cmd08-fetch-error" type="warning" showIcon message={s('refreshError')} action={<Button size="small" onClick={onRefresh}>{s('retry')}</Button>} />}
    <nav className="cmd08-navigation" aria-label={s('title')}>
      {([{ key: 'overview', icon: <DashboardOutlined /> }, { key: 'cells', icon: <AppstoreOutlined /> }, { key: 'diagnostics', icon: <SafetyOutlined /> }] as const).map(item =>
        <button key={item.key} aria-label={s(item.key)} aria-pressed={view === item.key} className={view === item.key ? 'active' : ''} onClick={() => setView(item.key)}>{item.icon}{s(item.key)}</button>)}
    </nav>
    {!live && <div className="cmd08-notice"><DisconnectOutlined /><div><strong>{stateLabel}</strong><span>{s('historicalOnly')}</span></div></div>}
    {live && flags.activeCount > 0 && <div className={`cmd08-notice ${flags.protection.active.length || flags.fault.active.length ? 'danger' : 'warning'}`}><WarningOutlined /><div>
      <strong>{s('activeCount', { count: flags.activeCount })}</strong><span>{s('bmsReported')}: {[...flags.protection.active, ...flags.fault.active, ...flags.warning.active].map(bitName).join(' · ')}</span></div></div>}
    <Spin spinning={loading}>
      {view === 'overview' && <section className="cmd08-summary">
        <div className="cmd08-soc"><div className="cmd08-muted cmd08-label">{s('soc')} <Tooltip title={s('provisional')}><InfoCircleOutlined tabIndex={0} aria-label={s('provisional')} /></Tooltip></div>
          <div className="cmd08-soc-number">{display(soc, 1)}{soc !== null && <span>%</span>}</div>
          <div className="cmd08-meter" role="meter" aria-label="SOC" aria-valuemin={0} aria-valuemax={100} aria-valuenow={soc ?? undefined} aria-valuetext={soc === null ? s('unavailable') : `${soc}%`}><div style={{ width: `${soc ?? 0}%` }} /></div>
          <div className="cmd08-soc-footer"><span>{live ? flags.operations.active.filter(flag => flag.bit === 8 || flag.bit === 9).map(bitName).join(' · ') || s('noState') : stateLabel}</span>
            <span className="cmd08-muted">{live ? s('packCount', { count: summaryNumber(v.battery_count) ?? 0 }) : '--'}</span></div>
        </div><div className="cmd08-summary-metrics"><Metric label={b('packVoltage')} value={display(n('voltage'), 2)} unit="V" />
          <Metric label={b('current')} value={display(n('current'), 2)} unit="A" subtle={live ? b('chgPositive') : undefined} />
          <Metric label={<>{s('soh')} <Tooltip title={s('provisional')}><InfoCircleOutlined tabIndex={0} /></Tooltip></>} value={display(percentage('soh'), 1)} unit="%" />
          <Metric label={b('cycleCount')} value={display(n('cycle_count'))} /></div>
      </section>}
      {view !== 'diagnostics' ? <><div className="cmd08-analysis"><div>{cellSection}</div><aside>{status}{temperature}</aside></div>{capacities}</> : <div className="cmd08-diagnostic-status">{status}{temperature}</div>}
      {view !== 'cells' && details}
    </Spin>
  </div>
}
