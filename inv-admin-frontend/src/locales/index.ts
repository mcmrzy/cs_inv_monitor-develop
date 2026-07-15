import type { Lang } from '@/stores/localeStore'
import common from './common'
import layout from './layout'
import dashboard from './dashboard'
import devices from './devices'
import monitoring from './monitoring'
import stations from './stations'
import ota from './ota'
import alerts from './alerts'
import workOrders from './workOrders'
import users from './users'
import admin from './admin'
import parallel from './parallel'
import remoteSettings from './remoteSettings'
import batchSettings from './batchSettings'
import operationLogs from './operationLogs'
import models from './models'
import bigScreen from './bigScreen'
import protocol from './protocol'
import deviceDetail from './deviceDetail'

const merge = (...objs: Record<string, string>[]) => Object.assign({}, ...objs)

const locales: Record<Lang, Record<string, string>> = {
  zh: merge(
    common.zh,
    layout.zh,
    dashboard.zh,
    devices.zh,
    monitoring.zh,
    stations.zh,
    ota.zh,
    alerts.zh,
    workOrders.zh,
    users.zh,
    admin.zh,
    parallel.zh,
    remoteSettings.zh,
    batchSettings.zh,
    operationLogs.zh,
    models.zh,
    bigScreen.zh,
    protocol.zh,
    deviceDetail.zh,
  ),
  en: merge(
    common.en,
    layout.en,
    dashboard.en,
    devices.en,
    monitoring.en,
    stations.en,
    ota.en,
    alerts.en,
    workOrders.en,
    users.en,
    admin.en,
    parallel.en,
    remoteSettings.en,
    batchSettings.en,
    operationLogs.en,
    models.en,
    bigScreen.en,
    protocol.en,
    deviceDetail.en,
  ),
}

export default locales
