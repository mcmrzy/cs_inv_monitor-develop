import { useEffect, useState, type ReactNode } from 'react'
import { createRoot } from 'react-dom/client'
import { ConfigProvider, Segmented, Tooltip, Button } from 'antd'
import {
  ArrowLeftOutlined, ArrowDownOutlined, CheckCircleOutlined, WarningOutlined,
  DisconnectOutlined, ReloadOutlined, DownloadOutlined, ThunderboltOutlined,
  DashboardOutlined, AppstoreOutlined, SettingOutlined, BellOutlined,
  InfoCircleOutlined, SafetyOutlined, RightOutlined, CloudOutlined,
} from '@ant-design/icons'
import ReactECharts from '../lib/echarts'
import './bms-preview.css'

type Scenario = 'normal' | 'alarm' | 'offline' | 'absent'
type View = 'compare' | 'web' | 'mobile'
type Tab = 'overview' | 'cells' | 'diagnostics'
const scenarios = [
  { label: '正常', value: 'normal' }, { label: '告警 / 保护', value: 'alarm' },
  { label: '数据过期', value: 'offline' }, { label: '未接入', value: 'absent' },
]
const initial = new URLSearchParams(location.search)
const baseCells = [3298, 3301, 3296, 3302, 3304, 3299, 3300, 3297, 3303, 3295, 3301, 3299, 3302, 3298, 3300, 3296]
const tabs: { key: Tab; label: string; icon: ReactNode }[] = [
  { key: 'overview', label: '概览', icon: <DashboardOutlined /> },
  { key: 'cells', label: '单体', icon: <AppstoreOutlined /> },
  { key: 'diagnostics', label: '诊断', icon: <SafetyOutlined /> },
]

function fixture(scenario: Scenario) {
  const cells: (number | null)[] = [...baseCells]
  if (scenario === 'alarm') { cells[4] = 3498; cells[15] = null }
  const present = scenario !== 'absent'
  const live = present && scenario !== 'offline'
  const valid = cells.filter((n): n is number => n !== null)
  const max = Math.max(...valid), min = Math.min(...valid)
  const balance = scenario === 'alarm' ? [4] : [3, 4, 8]
  const raw = new Uint8Array(100)
  const dv = new DataView(raw.buffer)
  dv.setUint8(0, 1); dv.setUint16(1, 5278, true); dv.setInt32(3, -840, true)
  dv.setUint16(7, 726, true); dv.setUint16(9, 978, true)
  dv.setUint16(11, 43560, true); dv.setUint16(13, 60000, true); dv.setUint32(15, 64000, true)
  dv.setUint16(19, scenario === 'alarm' ? 1 : 0, true)
  dv.setUint16(21, scenario === 'alarm' ? 1 : 0, true)
  dv.setUint16(23, (1 << 9) | (1 << 11), true)
  dv.setUint16(25, balance.reduce((word, i) => word | (1 << i), 0), true)
  cells.forEach((v, i) => dv.setUint16(27 + i * 2, v ?? 0, true))
  dv.setUint16(67, 128, true); dv.setUint16(69, max, true); dv.setUint16(71, min, true)
  dv.setInt16(77, 382, true); dv.setInt16(79, 328, true); dv.setInt16(81, 264, true)
  dv.setUint8(83, 2); dv.setUint8(84, 1)
  dv.setUint32(85, 136820, true); dv.setUint32(89, 129430, true)
  dv.setUint16(93, 3000, true); dv.setInt16(95, 5600, true)
  return { cells, present, live, max, min, balance, valid, raw: [...raw], alarm: scenario === 'alarm' }
}

function Metric({ label, value, unit, subtle }: { label: string; value: string; unit?: string; subtle?: string }) {
  return <div className="metric"><div className="muted metric-label">{label}</div>
    <div className="metric-number">{value}<span className="unit">{value === '--' ? '' : unit}</span></div>
    {subtle && <div className="metric-sub muted">{subtle}</div>}
  </div>
}

function SectionTitle({ title, right, icon }: { title: string; right?: ReactNode; icon?: ReactNode }) {
  return <div className="section-heading"><h2>{icon}{title}</h2>{right}</div>
}

function BmsSurface({ scenario, mobile }: { scenario: Scenario; mobile?: boolean }) {
  const b = fixture(scenario)
  const [tab, setTab] = useState<Tab>('overview')
  const [selected, setSelected] = useState(0)
  const [refreshed, setRefreshed] = useState(false)
  useEffect(() => { setRefreshed(false); setSelected(0) }, [scenario])
  const display = (value: string) => b.live ? value : '--'
  const mode = b.live ? b.alarm ? '保护已触发' : '放电中' : b.present ? '数据已过期' : '未接入 BMS'
  const stateClass = !b.live ? 'neutral' : b.alarm ? 'danger' : 'good'
  const timestamp = !b.present ? '--' : b.live ? refreshed ? '刚刚' : '8 秒前' : '18 分钟前'
  const exportSnapshot = () => {
    const blob = new Blob([JSON.stringify({ simulated: true, scenario, raw_bytes: b.raw }, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a'); a.href = url; a.download = 'bms-simulated-snapshot.json'; a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  const toolbar = <div className="surface-actions">
    <Tooltip title="刷新模拟快照"><Button aria-label="刷新模拟快照" icon={<ReloadOutlined />} onClick={() => setRefreshed(true)} /></Tooltip>
    {!mobile && <Tooltip title="导出模拟快照"><Button aria-label="导出模拟快照" icon={<DownloadOutlined />} onClick={exportSnapshot} disabled={!b.present} /></Tooltip>}
  </div>
  const status = <div className="status-line"><span className={`status ${stateClass}`}>
    {b.live ? <CheckCircleOutlined /> : <DisconnectOutlined />}{b.live ? 'BMS 已连接' : b.present ? 'BMS 数据过期' : '未接入 BMS'}
    </span><span className="muted freshness">更新 {timestamp}</span>
  </div>
  const alert = b.alarm ? <div className="notice danger-notice"><WarningOutlined /><div>
    <strong>单体过压保护</strong><span>BMS 上报 · C05 为当前最高电压单体</span>
  </div><button className="link-button" onClick={() => setTab('diagnostics')} aria-label="查看保护详情"><RightOutlined /></button></div>
    : !b.live && b.present ? <div className="notice offline-notice"><DisconnectOutlined /><div><strong>实时数据已过期</strong>
      <span>最后快照：2026-10-08 14:14:06</span></div><button className="link-button" onClick={() => setTab('diagnostics')} aria-label="查看历史诊断"><RightOutlined /></button></div> : null

  const summary = <section className="summary-band">
    <div className="soc-block"><div className="muted metric-label">剩余电量 <Tooltip title="SOC / SOH 根据协议暂按 0.1% 换算，待实机确认"><InfoCircleOutlined /></Tooltip></div>
      <div className="soc-number">{display('72.6')}<span>{b.live && '%'}</span></div>
      <div className="battery-meter" aria-label={b.live ? 'SOC 72.6%' : 'SOC 不可用'}><div style={{ width: b.live ? '72.6%' : '0%' }} /></div>
      <div className="soc-footer"><span className={`operating ${stateClass}`}>{b.live && !b.alarm && <ArrowDownOutlined />}{mode}</span><span className="muted">{b.present ? '1 个电池组' : '--'}</span></div>
    </div>
    <div className="summary-metrics">
      <Metric label="电池组电压" value={display('52.78')} unit="V" />
      <Metric label="电池组电流" value={display('-8.40')} unit="A" subtle={b.live ? '负值 · 放电方向' : undefined} />
      <Metric label="健康度 SOH" value={display('97.8')} unit="%" />
      <Metric label="循环次数" value={display('128')} unit="次" />
    </div>
  </section>

  const capacities = <section className="capacity-section"><SectionTitle title="容量" right={<span className="muted">Ah</span>} />
    <div className="capacity-grid"><Metric label="剩余容量" value={display('43.560')} /><Metric label="满充容量" value={display('60.000')} />
    <Metric label="设计容量" value={display('64.000')} /></div>
  </section>

  const temperatures = <section className="temperature-section"><SectionTitle title="温度" />
    <div className="temperature-grid">{[['MOS', '38.2'], ['PCB', '32.8'], ['环境', '26.4']].map(([label, value]) =>
      <Metric key={label} label={label} value={display(value)} unit="°C" />)}</div>
    <div className="unavailable-line"><span>单体温度 T1–T4</span><span className="muted">未提供</span></div>
    {tab !== 'overview' && <div className="unavailable-line"><span>单体最高 / 最低温度</span><span className="muted">未提供</span></div>}
  </section>

  const flags = <section className="flags-section"><SectionTitle title={b.live ? '预警与保护' : '最后快照 · 预警与保护'} right={b.live && <span className={`small-status ${b.alarm ? 'danger' : 'good'}`}>{b.alarm ? '2 项上报' : '无活动项'}</span>} />
    {[
      { title: '预警', value: b.alarm ? '单体过压' : '未上报', code: b.alarm ? '0x0001' : '0x0000', kind: 'warning' },
      { title: '保护', value: b.alarm ? '单体过压保护' : '未上报', code: b.alarm ? '0x0001' : '0x0000', kind: 'danger' },
      { title: '故障', value: '未上报', code: '0x0000', kind: 'danger' },
    ].map(row => <div className="flag-row" key={row.title}><span className="muted">{row.title}</span>
      <span className={b.alarm && row.title !== '故障' ? row.kind : ''}>{!b.present ? '--' : row.value}</span>
      {tab === 'diagnostics' && <code>{b.present ? row.code : '--'}</code>}
    </div>)}
    <div className="switch-status"><span className="muted">运行状态</span><span>{b.present ? b.live ? '放电 · 放电 MOS 开启' : '历史：放电 · 放电 MOS 开启' : '--'}</span></div>
  </section>

  const cells = <section className="cells-section"><SectionTitle title="单体一致性" right={<span className="muted">{b.live ? `${b.valid.length} / 16 节有效` : '-- / 16 节'}</span>} />
    <div className="cell-stats"><Metric label="最高电压" value={display(`${b.max}`)} unit="mV" subtle={b.live ? `C${String(b.cells.indexOf(b.max) + 1).padStart(2, '0')}` : undefined} />
      <Metric label="最低电压" value={display(`${b.min}`)} unit="mV" subtle={b.live ? `C${String(b.cells.indexOf(b.min) + 1).padStart(2, '0')}` : undefined} />
      <Metric label="压差" value={display(`${b.max - b.min}`)} unit="mV" /></div>
    <div className="chart-legend"><span><i className="legend highest" />最高</span><span><i className="legend lowest" />最低</span><span><i className="legend balanced" />均衡中</span><span className="muted">mV</span></div>
    {b.live ? <ReactECharts key={`${scenario}-${mobile}`} style={{ height: mobile ? 175 : 195 }} option={{
      animation: false,
      grid: { top: 12, bottom: 26, left: 47, right: 12 },
      tooltip: { trigger: 'axis', valueFormatter: (v: number | null) => v == null ? '未提供' : `${v} mV` },
      xAxis: { type: 'category', data: b.cells.map((_, i) => `${i + 1}`), axisTick: { show: false }, axisLine: { lineStyle: { color: '#dce3e6' } }, axisLabel: { color: '#76828b', fontSize: 10, interval: 0 } },
      yAxis: { type: 'value', min: 3200, max: b.alarm ? 3600 : 3400, splitNumber: 4, axisLabel: { color: '#88949a', fontSize: 10 }, splitLine: { lineStyle: { color: '#edf0f2' } } },
      series: [{ type: 'bar', barMaxWidth: mobile ? 11 : 23, data: b.cells.map((value, i) => ({ value, itemStyle: {
        color: value === b.max ? '#dca342' : value === b.min ? '#5c90c8' : '#88b6aa',
        borderColor: b.balance.includes(i) ? '#16795b' : 'transparent', borderWidth: b.balance.includes(i) ? 2 : 0, borderRadius: [2, 2, 0, 0],
      } })) }],
    }} onChartReady={chart => chart.on('click', params => { if (params.componentType === 'series') setSelected(params.dataIndex) })} />
      : <div className="chart-empty"><DisconnectOutlined /><span>{b.present ? '实时单体数据不可用' : '暂无单体数据'}</span></div>}
    <div className="cell-grid">{b.cells.map((value, i) => <button key={i} className={`cell ${selected === i ? 'selected' : ''} ${b.live && b.balance.includes(i) ? 'balancing' : ''}`} onClick={() => setSelected(i)} aria-pressed={selected === i} aria-label={`单体 C${String(i + 1).padStart(2, '0')}`}>
      <span className="cell-label">C{String(i + 1).padStart(2, '0')}{b.live && b.balance.includes(i) && <span className="balance-dot" />}</span>
      <strong>{b.live && value != null ? value : '--'}</strong>
    </button>)}</div>
    <div className="cell-selection"><span className="selection-title">C{String(selected + 1).padStart(2, '0')}</span><span>{b.live && b.cells[selected] != null ? `${b.cells[selected]} mV` : '无实时读数'}</span><span className="muted">{b.live && b.cells[selected] != null ? b.balance.includes(selected) ? '均衡中' : '未均衡' : '不可用'}</span></div>
  </section>

  const diagnostics = <section className="diagnostics-section"><SectionTitle title="诊断详情" right={<span className="muted">ARM CMD 0x08</span>} />
    {!b.live && b.present && <div className="historical-label">历史快照 · 非实时状态</div>}
    <details open={tab === 'diagnostics'}><summary>采样与通信<span>Layout 0</span></summary><dl>
      {[['电池组数量', b.present ? '1' : '--'], ['采样时间', b.present ? b.live ? '2026-10-08 14:32:06' : '2026-10-08 14:14:06' : '--'], ['ARM 响应年龄', b.present ? '800 ms' : '--'],
        ['上报时间', b.present ? b.live ? '2026-10-08 14:32:07' : '2026-10-08 14:14:07' : '--'], ['数据有效期', b.present ? b.live ? '2026-10-08 14:35:37' : '2026-10-08 14:17:37' : '--'], ['布局版本', b.present ? '0' : '--']].map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
    </dl></details>
    <details><summary>状态字与请求量<span>原始值</span></summary><dl>
      {[['状态 / 故障字', '0x0A00'], ['均衡位图', `0x${b.balance.reduce((v, i) => v | 1 << i, 0).toString(16).padStart(4, '0')}`], ['电池模式', '2'], ['电池状态', '1'], ['系统模式', '0'],
        ['SOC / SOH 原值', '726 / 978'], ['累计充电量 · 单位待确认', '136820'], ['累计放电量 · 单位待确认', '129430'], ['充电请求电流 · 单位待确认', '3000'], ['充电请求电压 · 单位待确认', '5600'], ['充电电压', '未提供']].map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{b.present ? v : '--'}</dd></div>)}
    </dl></details>
    <details><summary>原始报文<span>{b.present ? '100 bytes' : '--'}</span></summary>
      <pre className="raw-payload">{b.present ? Array.from({ length: 7 }, (_, i) => b.raw.slice(i * 16, (i + 1) * 16).map(v => v.toString(16).padStart(2, '0').toUpperCase()).join(' ')).join('\n') : '--'}</pre>
    </details>
  </section>

  const absent = <div className="absent-state"><CloudOutlined /><h2>尚未收到 BMS 数据</h2><p>逆变器在线 · BMS 尚未接入</p><span className="muted">最近 BMS 上报：--</span></div>
  const navigation = <nav className="bms-navigation" aria-label={mobile ? '手机 BMS 导航' : '网页 BMS 导航'}>{tabs.map(t =>
    <button key={t.key} aria-label={t.label} aria-current={tab === t.key ? 'page' : undefined} className={tab === t.key ? 'active' : ''} onClick={() => setTab(t.key)}>{mobile && <span aria-hidden="true">{t.icon}</span>}{t.label}</button>)}</nav>

  const content = !b.present && tab === 'overview' ? absent : tab === 'overview' ? <>{alert}{summary}
    {mobile ? <>{flags}{temperatures}{capacities}<button className="section-link" onClick={() => setTab('cells')}><span>单体一致性</span><span>{display(`${b.max - b.min}`)} {b.live ? 'mV' : ''}<RightOutlined /></span></button></>
      : <><div className="analysis-grid">{cells}<div className="analysis-side">{flags}{temperatures}</div></div>{capacities}{diagnostics}</>}
    </> : tab === 'cells' ? <>{alert}{cells}{mobile && temperatures}</> : <>{alert}{flags}{diagnostics}</>

  if (mobile) return <div className="mobile-surface"><header className="mobile-header">
    <button className="icon-button" aria-label="返回概览" onClick={() => setTab('overview')}><ArrowLeftOutlined /></button><div><strong>储能电池</strong><span>CS-INV-00128</span></div>{toolbar}
  </header><div className="mobile-status">{status}</div>{navigation}<main className="mobile-main">{content}</main>
    <footer className="mobile-footer"><CloudOutlined /> 云端连接<span>ARM · 0x08</span></footer></div>

  return <div className="web-surface"><aside className="web-sidebar"><div className="brand"><ThunderboltOutlined /><strong>CSER<span>GY</span></strong></div>
    <div className="sidebar-station muted">设备管理</div><button><DashboardOutlined />概览</button><button className="active"><AppstoreOutlined />设备监控</button><button><BellOutlined />告警中心</button><button><SettingOutlined />设置</button>
    <div className="sidebar-bottom"><span className="online-dot" /> 云端连接</div></aside>
    <div className="web-body"><header className="web-header"><div className="breadcrumb">设备管理 <RightOutlined /> 设备详情</div><span className="device-connected"><i className="online-dot" />逆变器在线</span></header>
      <main className="web-main"><div className="device-title"><div><h1>储能逆变器 <span>CS-INV-00128</span></h1><p className="muted">家庭储能 / 1 号设备</p></div>{toolbar}</div>
        <div className="device-tabs"><span>能源中心</span><span className="active">储能 BMS</span><span>运行状态</span><span>设备信息</span></div>
        <div className="web-bms-header"><h2>电池监控</h2>{status}</div>{navigation}{content}
      </main></div>
  </div>
}

function Preview() {
  const [scenario, setScenario] = useState<Scenario>(scenarios.some(s => s.value === initial.get('state')) ? initial.get('state') as Scenario : 'normal')
  const [view, setView] = useState<View>(['compare', 'web', 'mobile'].includes(initial.get('view') ?? '') ? initial.get('view') as View : 'compare')
  useEffect(() => { history.replaceState(null, '', `?state=${scenario}&view=${view}`) }, [scenario, view])
  return <ConfigProvider theme={{ token: { colorPrimary: '#19795e', borderRadius: 6, fontFamily: '"Segoe UI", "Microsoft YaHei", sans-serif' } }}>
    <div className="preview-shell"><header className="preview-toolbar"><div className="preview-identity"><strong>BMS 页面设计</strong><span>交互预览 · 模拟数据</span></div>
      <Segmented aria-label="模拟状态" options={scenarios} value={scenario} onChange={v => setScenario(v as Scenario)} />
      <Segmented aria-label="预览设备" options={[{ label: '两端对照', value: 'compare' }, { label: '网页', value: 'web' }, { label: '手机', value: 'mobile' }]} value={view} onChange={v => setView(v as View)} />
    </header><div className={`preview-stage ${view}`}>
      {view !== 'mobile' && <div className="web-preview"><div className="preview-caption">WEB <span>设备详情 / 储能 BMS</span></div><BmsSurface scenario={scenario} /></div>}
      {view !== 'web' && <div className="mobile-preview"><div className="preview-caption">APP <span>储能电池</span></div><BmsSurface mobile scenario={scenario} /></div>}
    </div></div>
  </ConfigProvider>
}

createRoot(document.getElementById('root')!).render(<Preview />)
