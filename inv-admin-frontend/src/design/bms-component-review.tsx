import { useState } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { App, ConfigProvider, Segmented } from 'antd'
import api from '../services/api'
import BmsTab from '../pages/device-detail/BmsTab'
import useLocaleStore from '../stores/localeStore'
import './bms-component-review.css'

type Scenario = 'normal' | 'alarm' | 'expired' | 'absent' | 'unknown'
let state: Scenario = 'normal'
const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
useLocaleStore.setState({ lang: 'zh' })

function sample() {
  const now = Date.now()
  const cells = Array.from({ length: 16 }, (_, i): number | null => 3295 + i)
  if (state === 'alarm') { cells[4] = 3498; cells[15] = null }
  const bytes = new Uint8Array(100)
  const view = new DataView(bytes.buffer)
  view.setUint8(0, 1); view.setUint16(1, 5278, true); view.setInt32(3, -840, true)
  view.setUint16(7, 726, true); view.setUint16(9, 978, true)
  view.setUint16(11, 43560, true); view.setUint16(13, 60000, true); view.setUint32(15, 64000, true)
  view.setUint16(19, state === 'alarm' ? 1 : 0, true); view.setUint16(21, state === 'alarm' ? 1 : 0, true)
  view.setUint16(23, 0x0a00, true); view.setUint16(25, 0x18, true)
  cells.forEach((v, i) => view.setUint16(27 + i * 2, v ?? 0, true))
  view.setUint16(67, 128, true); view.setUint16(69, state === 'alarm' ? 3498 : 3310, true); view.setUint16(71, 3295, true)
  view.setInt16(77, -55, true); view.setInt16(79, 0, true); view.setInt16(81, 264, true)
  view.setUint8(83, 2); view.setUint8(84, 1)
  view.setUint32(85, 4294967295, true); view.setUint32(89, 129430, true)
  view.setUint16(93, 3000, true); view.setInt16(95, -32768, true)
  return {
    layout: 0, bms_online: 1, battery_count: 1, voltage: 52.78, current: -8.4, soc: 72.6, soh: 97.8,
    soc_raw: 726, soh_raw: 978, capacity_remain: 43.56, capacity_full: 60, capacity_design: 64,
    warning_flag: state === 'alarm' ? 1 : 0, protection_flag: state === 'alarm' ? 1 : 0,
    status_fault_flag: 0x0a00, balance_status: 0x18, cell_voltages: cells, cell_temperatures: [null, null, null, null], cycle_count: 128,
    max_cell_voltage: state === 'alarm' ? 3498 : 3310, min_cell_voltage: 3295, max_cell_temp: null, min_cell_temp: null,
    mos_temp: -5.5, pcb_temp: 0, env_temp: 26.4, battery_mode: 2, battery_status: 1, system_mode: 0,
    total_chg_capacity_raw: 4294967295, total_dsg_capacity_raw: 129430, chg_request_current_raw: 3000, chg_request_voltage_raw: -32768,
    charging_voltage: null, raw_bytes: [...bytes], age_ms: 800,
    updated_at: new Date(now - (state === 'expired' ? 1200000 : 800)).toISOString(),
    reported_at: new Date(now - (state === 'expired' ? 1200000 : 0)).toISOString(),
    expires_at: state === 'unknown' ? null : new Date(now + (state === 'expired' ? -1000000 : 210000)).toISOString(),
  }
}

// Isolated review entry: no requests leave this adapter, no auth or production route changes.
api.defaults.adapter = async config => {
  if (config.url !== '/devices/by-sn/BMS-LOCAL-REVIEW/realtime') throw new Error('Unexpected local review request')
  return { config, status: 200, statusText: 'OK', headers: {}, data: { code: 0, message: 'success', data: {
    device_sn: 'BMS-LOCAL-REVIEW', online: true, data_time: new Date().toISOString(),
    realtime: state === 'absent' ? {} : { bms_summary: sample() },
  } } }
}

function Review() {
  const [scenario, setScenario] = useState<Scenario>('normal')
  const [lang, setLang] = useState<'zh' | 'en'>('zh')
  return <ConfigProvider theme={{ token: { colorPrimary: '#1677ff', borderRadius: 6 } }}><App>
    <header className="component-review-toolbar"><div><strong>BMS 正式组件验收</strong><span>隔离模拟接口 · 不连接真实设备</span></div>
      <Segmented value={scenario} options={[{ label: '正常', value: 'normal' }, { label: '告警', value: 'alarm' }, { label: '过期', value: 'expired' }, { label: '未接入', value: 'absent' }, { label: '未知', value: 'unknown' }]}
        onChange={value => { state = value as Scenario; setScenario(state); void queryClient.invalidateQueries() }} />
      <Segmented value={lang} options={[{ label: '中文', value: 'zh' }, { label: 'English', value: 'en' }]}
        onChange={value => { setLang(value as 'zh' | 'en'); useLocaleStore.setState({ lang: value as 'zh' | 'en' }) }} />
    </header><main className="component-review-main"><BmsTab sn="BMS-LOCAL-REVIEW" /></main>
  </App></ConfigProvider>
}

createRoot(document.getElementById('root')!).render(<QueryClientProvider client={queryClient}><Review /></QueryClientProvider>)
