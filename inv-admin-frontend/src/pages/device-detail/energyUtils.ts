/**
 * 能源中心共享工具：realtime envelope 解析、新鲜度判断、能源指标提取。
 *
 * 后端 GET /devices/by-sn/:sn/realtime 返回：
 *   { device_sn, data_time, online, realtime: {...} }
 * 其中 realtime 已由 normalizeRealtimeData 展平（pv1_power / charge_power / ac_power ...），
 * 同时保留 pv / ac / battery / energy / sys / fan 等嵌套分组作为回退来源。
 *
 * 离线时 Redis 会回退到「最后有效数据」缓存，陈旧值不能当实时数据展示：
 * 必须 online === true 且 data_time 在新鲜度窗口内（与 StationDetailPage 同策略）。
 */
import { safeNum } from '@/utils/format'

/** 实时数据新鲜度窗口（10 分钟） */
export const REALTIME_FRESH_WINDOW_MS = 10 * 60 * 1000

export interface RtEnvelope {
  online: boolean
  dataTime: unknown
  realtime: Record<string, any>
}

/** 将 realtime API 返回体归一化为 envelope */
export function toRtEnvelope(body: any): RtEnvelope {
  return {
    online: body?.online === true,
    dataTime: body?.data_time ?? null,
    realtime: body?.realtime ?? body ?? {},
  }
}

/** 解析数据时间戳（兼容秒/毫秒数字与字符串），无效返回 NaN */
export const parseRtTimestamp = (raw: unknown): number => {
  if (raw == null || raw === '') return NaN
  if (typeof raw === 'number') return raw > 1e12 ? raw : raw * 1000
  return Date.parse(String(raw))
}

/** 实时数据是否可用：设备在线且时间戳未过期（无时间戳时退化为仅凭在线状态） */
export const isRealtimeFresh = (env?: RtEnvelope | null): boolean => {
  if (!env || !env.online) return false
  const ts = parseRtTimestamp(env.dataTime ?? env.realtime?.updated_at ?? env.realtime?.timestamp)
  if (!Number.isFinite(ts)) return true
  return Date.now() - ts <= REALTIME_FRESH_WINDOW_MS
}

/** 从 envelope 提取新鲜 realtime 数据；不新鲜时返回 null（不得展示陈旧缓存值） */
export function freshRealtime(env?: RtEnvelope | null): Record<string, any> | null {
  if (!isRealtimeFresh(env)) return null
  return env?.realtime ?? null
}

/** 读取展平字段，带嵌套分组回退 */
function pick(rt: Record<string, any>, ...paths: string[]): number | null {
  for (const p of paths) {
    const segs = p.split('.')
    let cur: any = rt
    for (const s of segs) {
      if (cur == null || typeof cur !== 'object') { cur = undefined; break }
      cur = cur[s]
    }
    if (cur !== undefined && cur !== null && cur !== '') return safeNum(cur)
  }
  return null
}

export interface EnergyMetrics {
  // 光伏
  pvPower: number
  pv1Power: number
  pv1Voltage: number
  pv2Power: number
  pv2Voltage: number
  // 电池（battPower：正=充电，负=放电）
  battPower: number
  battSoc: number
  battVoltage: number | null
  battCurrent: number | null
  batteryChargePower: number | null
  batteryDischargePower: number | null
  // 负载 / AC 输出
  loadPower: number
  loadPercent: number | null
  acVoltage: number | null
  acCurrent: number | null
  acFrequency: number | null
  // 电网（gridPower：正=市电输入，负=馈网）
  gridPower: number
  gridVoltage: number | null
  gridFreq: number | null
  acInputPower: number | null
  acChargePower: number | null
  acBypassPower: number | null
  // 发电机
  genPower: number
  // 今日/累计能量 kWh
  dailyPv: number
  totalPv: number
  dailyCharge: number
  totalCharge: number
  dailyDischarge: number
  totalDischarge: number
  dailyLoad: number
  totalLoad: number
  dailyFeedEnergy: number
  dailyGridImport: number
  // 状态
  workState: number | null
  faultCode: number | null
  runStatus: number | null
  sysStatusRaw: number | null
  warning: number | null
  bmsWarning: number | null
  // 温度 / 风扇 / 母线
  inverterTemp: number | null
  boostTemp: number | null
  transformerTemp: number | null
  pvTemp: number | null
  ambientTemp: number | null
  dcBusVoltage: number | null
  fanSpeed: number | null
  mpptFanSpeed: number | null
  efficiency: number | null
}

/** 从展平后的 realtime 数据提取能源指标（兼容 V1 嵌套回退与 V2 展平字段） */
export function extractEnergyMetrics(rt: Record<string, any> | null | undefined): EnergyMetrics {
  const r = rt ?? {}
  // V2 显式充/放电功率优先（方向明确），回退带符号 charge_power
  const chgW = pick(r, 'battery_charge_power', 'bat.battery_charge_power')
  const disW = pick(r, 'battery_discharge_power', 'bat.battery_discharge_power')
  const battPower = (chgW != null || disW != null)
    ? (chgW ?? 0) - (disW ?? 0)
    : pick(r, 'charge_power', 'batt.power', 'battery_power', 'batt_power') ?? 0
  // 市电输入功率：grid_power/meter_power 优先，回退 V2 的 ac_input_power + ac_charge_power
  const acInputPower = pick(r, 'ac_input_power', 'ac.ac_input_power')
  const acChargePower = pick(r, 'ac_charge_power', 'chr.ac_charge_power', 'ac.ac_charge_power')
  const gridPower = pick(r, 'grid_power', 'meter_power')
    ?? ((acInputPower ?? 0) + (acChargePower ?? 0))
  return {
    pvPower: pick(r, 'pv_total_power', 'pv.pv_power_total', 'total_power') ?? 0,
    pv1Power: pick(r, 'pv1_power', 'pv.pv1_power') ?? 0,
    pv1Voltage: pick(r, 'pv1_voltage', 'pv.pv1_voltage') ?? 0,
    pv2Power: pick(r, 'pv2_power', 'pv.pv2_power') ?? 0,
    pv2Voltage: pick(r, 'pv2_voltage', 'pv.pv2_voltage') ?? 0,
    battPower,
    battSoc: pick(r, 'battery_soc', 'soc', 'batt.soc') ?? 0,
    battVoltage: pick(r, 'battery_voltage', 'batt.voltage', 'voltage'),
    battCurrent: pick(r, 'battery_current', 'batt_current', 'batt.current', 'current'),
    batteryChargePower: chgW,
    batteryDischargePower: disW,
    loadPower: pick(r, 'ac_power', 'ac.power', 'output_power', 'ac_active_power') ?? 0,
    loadPercent: pick(r, 'load_percent', 'load_rate', 'ac.load_percent'),
    acVoltage: pick(r, 'ac_voltage', 'ac.voltage', 'output_voltage', 'ac_output_voltage'),
    acCurrent: pick(r, 'ac_current', 'ac.current', 'output_current'),
    acFrequency: pick(r, 'ac_frequency', 'ac.frequency', 'output_frequency'),
    gridPower,
    gridVoltage: pick(r, 'meter_voltage', 'grid_voltage'),
    gridFreq: pick(r, 'meter_frequency', 'grid_frequency'),
    acInputPower,
    acChargePower,
    acBypassPower: pick(r, 'ac_bypass_power', 'ac.ac_bypass_power'),
    genPower: pick(r, 'gen_power', 'gen.power') ?? 0,
    dailyPv: pick(r, 'daily_pv', 'energy.daily_pv', 'daily_pv_energy') ?? 0,
    totalPv: pick(r, 'total_pv', 'energy.total_pv', 'total_pv_energy') ?? 0,
    dailyCharge: pick(r, 'daily_charge', 'energy.daily_charge', 'daily_charge_energy') ?? 0,
    totalCharge: pick(r, 'total_charge', 'energy.total_charge', 'total_charge_energy') ?? 0,
    dailyDischarge: pick(r, 'daily_discharge', 'energy.daily_discharge', 'daily_discharge_energy') ?? 0,
    totalDischarge: pick(r, 'total_discharge', 'energy.total_discharge', 'total_discharge_energy') ?? 0,
    dailyLoad: pick(r, 'daily_load', 'energy.daily_load', 'daily_load_energy', 'output_energy_daily') ?? 0,
    totalLoad: pick(r, 'total_load', 'energy.total_load', 'total_load_energy') ?? 0,
    dailyFeedEnergy: pick(r, 'daily_feed_energy', 'feed_energy_daily', 'energy.daily_feed_energy') ?? 0,
    dailyGridImport: pick(r, 'daily_grid_import', 'grid_import_energy_daily', 'energy.daily_grid_import') ?? 0,
    workState: pick(r, 'work_state', 'run_status', 'sys.state'),
    faultCode: pick(r, 'fault_code'),
    runStatus: pick(r, 'run_status'),
    sysStatusRaw: pick(r, 'sys_status', 'sys.sys_status'),
    warning: pick(r, 'warning', 'sys.warning'),
    bmsWarning: pick(r, 'bms_warning', 'sys.bms_warning'),
    inverterTemp: pick(r, 'inverter_temperature', 'inverter_temp', 'temp_inv', 'sys.inverter_temperature'),
    boostTemp: pick(r, 'temp_boost', 'boost_temp', 'boost_temperature', 'sys.boost_temperature'),
    transformerTemp: pick(r, 'temp_transformer', 'transformer_temp', 'transformer_temperature', 'sys.transformer_temperature'),
    pvTemp: pick(r, 'pv_temperature', 'temp_pv', 'sys.pv_temperature'),
    ambientTemp: pick(r, 'ambient_temperature', 'ambient_temp', 'temp_env'),
    dcBusVoltage: pick(r, 'dc_bus_voltage', 'sys.dc_bus_voltage'),
    fanSpeed: pick(r, 'fan_speed_percent', 'fan.inv_fan_speed', 'inv_fan_speed'),
    mpptFanSpeed: pick(r, 'fan.mppt_fan_speed', 'mppt_fan_speed'),
    efficiency: pick(r, 'efficiency'),
  }
}

// ═════════════════════ SysStatus 12 位状态位 ═════════════════════
// CS-L10-6K2 V2.1 协议（docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md）：
//   bit0 StandBy | bit1 Fault | bit2 Charge | bit3 Discharging
//   bit4 PVCharging | bit5 ACCharging | bit6 GenCharging | bit7 ACBypass
//   bit8 ToLoad | bit9 Pvinput | bit10 AcInput | bit11 GeInput

export interface SysStatusBits {
  standby: boolean
  fault: boolean
  charge: boolean
  discharge: boolean
  pvCharge: boolean
  acCharge: boolean
  geCharge: boolean
  acBypass: boolean
  toLoad: boolean
  pvInput: boolean
  acInput: boolean
  geInput: boolean
}

/** 位掩码展开为 12 位布尔对象；无效输入返回 null */
export function parseSysStatusBits(mask: number | null | undefined): SysStatusBits | null {
  if (mask == null || !Number.isFinite(mask)) return null
  const m = Math.trunc(mask)
  const bit = (n: number) => ((m >> n) & 1) === 1
  return {
    standby: bit(0),
    fault: bit(1),
    charge: bit(2),
    discharge: bit(3),
    pvCharge: bit(4),
    acCharge: bit(5),
    geCharge: bit(6),
    acBypass: bit(7),
    toLoad: bit(8),
    pvInput: bit(9),
    acInput: bit(10),
    geInput: bit(11),
  }
}

/** V1 设备无位掩码时按功率/workState 推导（动画语义与位驱动保持一致） */
export function deriveBitsFromMetrics(m: EnergyMetrics): SysStatusBits {
  return {
    standby: m.workState === 0,
    fault: m.faultCode != null && m.faultCode !== 0,
    charge: m.battPower > 5,
    discharge: m.battPower < -5,
    pvCharge: m.pvPower > 0 && m.battPower > 5,
    acCharge: m.acChargePower != null && m.acChargePower > 5,
    geCharge: m.genPower > 0 && m.battPower > 5,
    acBypass: m.workState === 2 || (m.acBypassPower != null && m.acBypassPower > 5),
    toLoad: m.loadPower > 0,
    pvInput: m.pvPower > 0,
    acInput: m.gridPower > 5,
    geInput: m.genPower > 0,
  }
}

/** 统一入口：位掩码优先（V2），推导兜底（V1） */
export function getSysBits(m: EnergyMetrics): SysStatusBits {
  return parseSysStatusBits(m.sysStatusRaw) ?? deriveBitsFromMetrics(m)
}

/** 功率格式化：< 1000W 显示 W，否则显示 kW */
export function formatPower(w: number | null | undefined): string {
  if (w == null || !Number.isFinite(w)) return '--'
  const abs = Math.abs(w)
  if (abs >= 1000) return `${(abs / 1000).toFixed(2)} kW`
  return `${Math.round(abs)} W`
}

/** 带符号功率格式化（电池：充电 +W / 放电 -W） */
export function formatSignedPower(w: number | null | undefined): string {
  if (w == null || !Number.isFinite(w)) return '--'
  const sign = w > 0 ? '+' : ''
  const abs = Math.abs(w)
  if (abs >= 1000) return `${sign}${(w / 1000).toFixed(2)} kW`
  return `${sign}${Math.round(w)} W`
}

export type BattState = 'charging' | 'discharging' | 'standby'

/** 电池状态：charge_power 正为充电、负为放电，接近 0 视为待机 */
export function getBattState(battPower: number): BattState {
  if (battPower > 5) return 'charging'
  if (battPower < -5) return 'discharging'
  return 'standby'
}

export type GridState = 'import' | 'export' | 'idle'

/** 电网方向：正为市电输入，负为馈网输出，0 为待机/无数据 */
export function getGridState(gridPower: number): GridState {
  if (gridPower > 5) return 'import'
  if (gridPower < -5) return 'export'
  return 'idle'
}

/** 能源主题色 */
export const ENERGY_COLORS = {
  smartBlue: '#00D4FF',
  energyGreen: '#00E676',
  dark: '#111827',
  pv: '#F59E0B',
  battery: '#00E676',
  load: '#00D4FF',
  grid: '#8B5CF6',
}
