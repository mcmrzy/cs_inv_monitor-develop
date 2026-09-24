/** Active pages refresh in the background; TanStack Query pauses polling in hidden tabs. */
export function autoRefreshInterval(queryKey: readonly unknown[]): number | false {
  const [scope, resource] = queryKey

  if (scope === 'ota') {
    if (['tasks', 'task-devices', 'task-detail', 'task-stats'].includes(String(resource))) return 10_000
    if (['history', 'device-history', 'firmware-overview'].includes(String(resource))) return 15_000
    return 120_000
  }

  if (scope === 'devices') {
    if (['realtime', 'control-state', 'commands', 'debug-session'].includes(String(resource))) return 15_000
    if (resource == null || typeof resource === 'object' || ['list', 'all', 'detail', 'by-station'].includes(String(resource))) return 30_000
    return 120_000
  }

  if (scope === 'stations') return resource === 'all' ? 60_000 : 30_000
  if (scope === 'station' || scope === 'station-devices' || scope === 'station-devices-overview' || scope === 'station-devices-list') return 30_000
  if (scope === 'station-alarms' || scope === 'station-alarms-overview' || scope === 'device-alarms') return 15_000
  if (scope === 'station-statistics' || scope === 'station-stats-summary' || scope === 'station-energy-overview') return 60_000
  if (scope === 'station-trend-30d' || scope === 'station-power-flow') return 60_000

  if (scope === 'alerts' || scope === 'notifications') return 15_000
  if (scope === 'work-orders' || scope === 'monitoring') return resource === 'templates' ? 120_000 : 30_000
  if (scope === 'users') return 60_000
  if (scope === 'channels') return ['invitations', 'transfers'].includes(String(resource)) ? 30_000 : 60_000
  if (scope === 'admin') return resource === 'audit-logs' ? 30_000 : 120_000
  if (scope === 'operation-logs' || scope === 'system-logs' || scope === 'operation-stats') return 30_000
  if (scope === 'parallel' || (scope === 'protocol' && resource === 'parallel-state')) return 15_000
  if (scope === 'dashboard') return 30_000
  if (scope === 'batch' && resource === 'devices') return 30_000
  if (scope === 'unbindRequests' || scope === 'allDevices') return 30_000
  if (scope === 'deviceUpgradeHistory' || scope === 'otaFirmwareOverview') return 15_000
  return 120_000
}
