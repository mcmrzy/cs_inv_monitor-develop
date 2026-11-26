// 远程设置数据层：config-schema + control-state 读取、命令下发（沿用现有命令构造）
//
// 下发约定（与 SchemaGroupPanel 现有逻辑一致）：
//   deviceApi.sendCommand(sn, { command: <param_key>, params: { value: <工程单位值> } })
// V2.1 起 control-state 与命令参数均为工程单位（物理量），服务端按 schema min/max 校验；
// raw = round(physical × scale) 仅在对接原始量纲来源时使用（见 conversion.ts）。

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { App } from 'antd'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import type { ConfigSchemaItem } from '../config/fields'
import { normalizeIncoming, resolveFieldMeta, type ResolvedFieldMeta } from '../config/conversion'
import type { CommandRecord, ControlState } from '../types'
import { canUseCapability, commandErrorDetail, commandReadback, getAcOutputState, getTaskId, type ControlCapability } from '../controlContract'
import { freshRealtime, toRtEnvelope } from '../../device-detail/energyUtils'

type PowerCommand = 'ac_on' | 'ac_off'

export function useDeviceConfig(sn: string, online: boolean) {
  const apiSn = encodeURIComponent(sn)
  const { t } = useTranslation()
  const { message, modal } = App.useApp()
  const queryClient = useQueryClient()
  const { hasPermission } = useAuthStore()
  const onlineRef = useRef(online)
  useEffect(() => { onlineRef.current = online }, [online])
  const [sendingKey, setSendingKey] = useState<string | null>(null)
  const [reading, setReading] = useState(false)
  const [writeRequest, setWriteRequest] = useState<{ taskId: string; deadline: number; power: boolean } | null>(null)
  const [readRequest, setReadRequest] = useState<{ taskId: string; baselineTime: number; deadline: number } | null>(null)
  const readBusy = useRef(false)
  const writeBusy = useRef(false)
  const readGeneration = useRef(0)
  useEffect(() => () => { readGeneration.current += 1 }, [sn])

  const { data: schemaItems, isLoading: schemaLoading, error: schemaError, refetch: refetchSchema } = useQuery({
    queryKey: ['config-schema', sn, 'catalog'],
    queryFn: () =>
      deviceApi.getConfigSchema(apiSn, true).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        // 兼容直接数组 / {items:[...]} 两种形状，非数组一律降级为空列表
        return (Array.isArray(d) ? d : (Array.isArray((d as any)?.items) ? (d as any).items : [])) as ConfigSchemaItem[]
      }),
    staleTime: 300_000,
  })

  // 型号控制命令能力（与 /control 校验同源）。schema 已按型号过滤后仍加载一份，
  // 用于下发前二次拦截，以及 Advanced 中 reported 但不可写的扩展键只读展示。
  const { data: capabilities, error: capabilitiesError, refetch: refetchCapabilities } = useQuery({
    queryKey: queryKeys.devices.controlCapabilities(sn),
    queryFn: () =>
      deviceApi.getControlCapabilities(apiSn).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (Array.isArray(d) ? d : []) as ControlCapability[]
      }),
    refetchInterval: 10_000,
  })

  const capabilityMap = useMemo(() => new Map((capabilities ?? []).map((capability) => [capability.command_code, capability])), [capabilities])
  const allowedCommands = useMemo(() => {
    const s = new Set<string>()
    for (const c of capabilities ?? []) {
      if (c?.command_code && c.is_enabled === true) s.add(c.command_code)
    }
    return s
  }, [capabilities])

  const showPower = allowedCommands.has('ac_on') || allowedCommands.has('ac_off')
  const { data: realtime, error: realtimeError, refetch: refetchRealtime } = useQuery({
    queryKey: queryKeys.devices.realtime(sn),
    queryFn: () => deviceApi.getRealtime(apiSn).then((response) => toRtEnvelope(response.data?.data)),
    enabled: showPower && online,
    refetchInterval: 5_000,
  })
  const outputOn = online && !realtimeError ? getAcOutputState(freshRealtime(realtime)) : undefined
  const powerCommand: PowerCommand | undefined = outputOn === undefined ? undefined : outputOn ? 'ac_off' : 'ac_on'
  const powerCommandRef = useRef(powerCommand)
  useEffect(() => { powerCommandRef.current = powerCommand }, [powerCommand])

  const { data: controlState, isLoading: stateLoading, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(apiSn).then((r) => (r.data?.data ?? null) as ControlState | null),
    refetchInterval: reading || sendingKey ? 1_000 : 10_000,
    refetchIntervalInBackground: reading,
  })

  const { data: history, refetch: refetchHistory } = useQuery({
    queryKey: ['device-commands', sn],
    queryFn: () =>
      deviceApi.getCommands(apiSn, { page: 1, page_size: 100 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as CommandRecord[]
      }),
    refetchInterval: reading || sendingKey ? 1_000 : 10_000,
    refetchIntervalInBackground: Boolean(reading || sendingKey),
  })

  const schemaMap = useMemo(() => {
    const m = new Map<string, ConfigSchemaItem>()
    for (const item of schemaItems ?? []) m.set(item.param_key, item)
    return m
  }, [schemaItems])

  // schema 已为空且能力表也为空：通常为设备未绑定型号
  const modelCommandsMissing = useMemo(
    () => (schemaItems ?? []).length === 0 && (capabilities ?? []).length === 0 && !schemaLoading,
    [schemaItems, capabilities, schemaLoading],
  )

  const reported = useMemo(() => (controlState?.reported ?? {}) as Record<string, unknown>, [controlState])
  const desired = useMemo(() => (controlState?.desired ?? {}) as Record<string, unknown>, [controlState])

  /** 后端同步状态（unknown/pending/synced/drifted）：unknown 表示设备尚未回报配置 */
  const syncStatus = (controlState?.sync_status as string) ?? 'unknown'
  /** 设备是否已回报过配置（reported 非空），用于「未上报/值不可信」提示 */
  const hasReportedConfig = useMemo(() => Object.keys(reported).length > 0, [reported])

  // 查询命令被接受后，继续等待比读取前更新的设备配置回报。
  // reported_revision 在参数不变时也不变，不能用它判断本次读取是否完成。
  useEffect(() => {
    if (!readRequest) return
    const record = history?.find((item) => String(item.task_id) === readRequest.taskId)
    if (commandReadback(record) === 'failed') {
      setReadRequest(null)
      setReading(false)
      readBusy.current = false
      message.error(record?.result_message || t('remote.commandFailed'))
      return
    }
    const reportTime = Date.parse(controlState?.reported_at ?? '')
    if (hasReportedConfig && Number.isFinite(reportTime) && reportTime > readRequest.baselineTime) {
      setReadRequest(null)
      setReading(false)
      readBusy.current = false
      message.success(t('remote.readSuccess'))
      return
    }
    const timer = setTimeout(() => {
      setReadRequest(null)
      setReading(false)
      readBusy.current = false
      message.warning(t('remote.readTimeout'))
    }, Math.max(0, readRequest.deadline - Date.now()))
    return () => clearTimeout(timer)
  }, [readRequest, controlState?.reported_at, hasReportedConfig, history, message, t])

  const canRead = online && !capabilitiesError && !sendingKey &&
    canUseCapability(capabilityMap.get('query_config'), hasPermission)

  const readCurrent = useCallback(async () => {
    if (readBusy.current || writeBusy.current || !canRead) return
    readBusy.current = true
    const generation = ++readGeneration.current
    setReading(true)
    message.info(t('remote.readingConfig'))
    try {
      const baseline = await refetchState({ throwOnError: true })
      if (generation !== readGeneration.current) return
      const baselineTime = Date.parse(baseline.data?.reported_at ?? '')
      if (!onlineRef.current) {
        readBusy.current = false
        setReading(false)
        return
      }
      const response = await deviceApi.sendCommand(apiSn, { command: 'query_config', params: {} })
      if (generation !== readGeneration.current) return
      const taskId = getTaskId(response.data?.data)
      if (!taskId) {
        readBusy.current = false
        setReading(false)
        message.warning(t('remote.taskIdMissing'))
        void refetchState()
        void refetchHistory()
        return
      }
      setReadRequest({
        taskId,
        baselineTime: Number.isFinite(baselineTime) ? baselineTime : -Infinity,
        deadline: Date.now() + 30_000,
      })
      void refetchState()
      void refetchHistory()
    } catch (err) {
      if (generation !== readGeneration.current) return
      readBusy.current = false
      setReading(false)
      const detail = commandErrorDetail(err)
      message.error(`${t('remote.commandSendFailed')}${detail ? `: ${detail}` : ''}`)
    }
  }, [apiSn, canRead, refetchState, refetchHistory, message, t])

  const getMeta = useCallback(
    (paramKey: string): ResolvedFieldMeta => resolveFieldMeta(schemaMap, paramKey),
    [schemaMap],
  )

  /** 控件显示设备回报值；历史下发意图仅用于待生效标记。 */
  const getEditValue = useCallback(
    (paramKey: string): number | undefined => {
      const meta = resolveFieldMeta(schemaMap, paramKey)
      return normalizeIncoming(reported[paramKey], meta)
    },
    [schemaMap, reported],
  )

  /** 未回报字段保持未知，不能用下发意图代替设备实际值。 */
  const getSummaryValue = useCallback(
    (paramKey: string): number | undefined => {
      const meta = resolveFieldMeta(schemaMap, paramKey)
      return normalizeIncoming(reported[paramKey], meta)
    },
    [schemaMap, reported],
  )

  /** 字段显示名：schema display_name_key → config.<param_key> → 原键名 */
  const fieldLabel = useCallback(
    (paramKey: string): string => {
      const displayKey = schemaMap.get(paramKey)?.display_name_key
      if (displayKey && t(displayKey) !== displayKey) return t(displayKey)
      const cfgKey = `config.${paramKey}`
      if (t(cfgKey) !== cfgKey) return t(cfgKey)
      return paramKey
    },
    [schemaMap, t],
  )

  /** 枚举选项标签：config.enum.<semanticKey>，缺失时直接显示语义键 */
  const enumLabel = useCallback(
    (semanticKey: string): string => {
      const key = `config.enum.${semanticKey}`
      return t(key) !== key ? t(key) : semanticKey
    },
    [t],
  )

  /** visibility 联动判定 */
  const isVisible = useCallback(
    (meta: ResolvedFieldMeta): boolean => {
      const v = meta.visibility
      if (!v?.param) return true
      const cur = reported[v.param]
      if (cur === undefined) return false
      const num = Number(cur)
      if (v.in) return v.in.includes(num)
      if (v.eq !== undefined) return num === v.eq
      if (v.ne !== undefined) return num !== v.ne
      return true
    },
    [reported],
  )

  useEffect(() => {
    if (!writeRequest) return
    const record = history?.find((item) => String(item.task_id) === writeRequest.taskId)
    const outcome = commandReadback(record, writeRequest.power)
    if (outcome !== 'pending') {
      setWriteRequest(null)
      setSendingKey(null)
      writeBusy.current = false
      if (outcome === 'applied') {
        message.success(t('remote.readbackVerified'))
      } else if (outcome === 'submitted') message.warning(t('remote.readbackUnconfirmed'))
      else message.error(record?.result_message || t('remote.commandFailed'))
      void refetchState()
      if (writeRequest.power && onlineRef.current) void refetchRealtime()
      return
    }
    const timer = setTimeout(() => {
      setWriteRequest(null)
      setSendingKey(null)
      writeBusy.current = false
      message.warning(t('remote.readbackTimeout'))
      void refetchState()
      if (writeRequest.power && onlineRef.current) void refetchRealtime()
    }, Math.max(0, writeRequest.deadline - Date.now()))
    return () => clearTimeout(timer)
  }, [writeRequest, history, message, t, refetchState, refetchRealtime])

  /** 参数是否可编辑（后端 permission_code 校验） */
  const canEdit = useCallback(
    (paramKey: string): boolean => {
      const schema = schemaMap.get(paramKey)
      return online && !capabilitiesError && !reading && sendingKey === null && Boolean(schema) && !schema?.catalog_access &&
        canUseCapability(capabilityMap.get(paramKey), hasPermission, schema?.permission_code)
    },
    [schemaMap, hasPermission, capabilityMap, capabilitiesError, online, reading, sendingKey],
  )

  const canSendPower = useCallback((command: PowerCommand) => {
    return command === powerCommand && online && !capabilitiesError && !reading && sendingKey === null &&
      canUseCapability(capabilityMap.get(command), hasPermission)
  }, [powerCommand, online, reading, sendingKey, capabilitiesError, capabilityMap, hasPermission])

  /** desired 与 reported 是否一致（用于同步徽标） */
  const isSynced = useCallback(
    (paramKey: string): 'synced' | 'pending' | 'none' => {
      const d = desired[paramKey]
      if (d === undefined) return 'none'
      const r = reported[paramKey]
      const meta = resolveFieldMeta(schemaMap, paramKey)
      const expected = normalizeIncoming(d, meta)
      const actual = normalizeIncoming(r, meta)
      if (r !== undefined && (String(d) === String(r) || (expected !== undefined && expected === actual))) return 'synced'
      return 'pending'
    },
    [desired, reported, schemaMap],
  )

  const doSend = useCallback(
    (command: string, physical?: number) => {
      if (!onlineRef.current || writeBusy.current || readBusy.current) return
      const power = command === 'ac_on' || command === 'ac_off'
      if (power ? powerCommandRef.current !== command || !canSendPower(command) : !canEdit(command)) {
        message.error(`${t('remote.commandSendFailed')}: ${t('remote.commandNotAllowed')}`)
        return
      }
      writeBusy.current = true
      const generation = readGeneration.current
      let waitingForReadback = false
      setSendingKey(command)
      const value = getMeta(command).kind === 'boolean' ? Boolean(physical) : physical
      deviceApi
        .sendCommand(apiSn, { command, params: power ? {} : { value } })
        .then((response) => {
          if (generation !== readGeneration.current) return
          const taskId = getTaskId(response.data?.data)
          if (!taskId) {
            message.warning(t('remote.taskIdMissing'))
            void refetchHistory()
            return
          }
          waitingForReadback = true
          setWriteRequest({ taskId, deadline: Date.now() + 35_000, power })
          message.info(t('remote.commandTrackingTask', { taskId }))
          void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
          void refetchHistory()
        })
        .catch((err) => {
          if (generation !== readGeneration.current) return
          const detail = commandErrorDetail(err)
          message.error(`${t('remote.commandSendFailed')}${detail ? `: ${detail}` : ''}`)
        })
        .finally(() => {
          if (!waitingForReadback && generation === readGeneration.current) {
            writeBusy.current = false
            setSendingKey(null)
          }
        })
    },
    [apiSn, sn, message, t, queryClient, refetchHistory, canEdit, canSendPower, getMeta],
  )

  /** 下发工程单位值；confirm 字段弹二次确认（沿用现有确认逻辑） */
  const sendValue = useCallback(
    (meta: ResolvedFieldMeta, physical: number) => {
      if (physical === undefined || physical === null || Number.isNaN(physical)) {
        message.warning(t('remote.paramRequired'))
        return
      }
      modal.confirm({
          title: t('remote.confirmSettings'),
          content: t('remote.confirmDeviceSetting', { sn, cmd: fieldLabel(meta.paramKey) }) + ' ' + t('remote.linkedChange', {
                current: meta.kind === 'boolean' && getEditValue(meta.paramKey) !== undefined
                  ? t(getEditValue(meta.paramKey) ? 'remote3.enabled' : 'remote3.disabled')
                  : getEditValue(meta.paramKey) ?? '—',
                target: meta.kind === 'boolean'
                  ? t(physical ? 'remote3.enabled' : 'remote3.disabled')
                  : physical,
              }),
          okText: t('remote.confirmExecute'),
          cancelText: t('remote.cancel'),
          okButtonProps: { danger: true },
          onOk: () => doSend(meta.paramKey, physical),
      })
    },
    [sn, modal, message, t, fieldLabel, doSend, getEditValue],
  )

  const sendPower = useCallback((command: PowerCommand) => {
    if (!canSendPower(command)) return
    const generation = readGeneration.current
    modal.confirm({
      title: t(`commands.${command}`),
      content: t('remote.confirmDeviceSetting', { sn, cmd: t(`commands.${command}`) }),
      okText: t('remote.confirmExecute'),
      cancelText: t('remote.cancel'),
      okButtonProps: { danger: command === 'ac_off' },
      onOk: () => { if (generation === readGeneration.current) doSend(command) },
    })
  }, [canSendPower, modal, sn, t, doSend])

  return {
    showPower,
    powerCommand,
    canSendPower,
    sendPower,
    schemaItems: schemaItems ?? [],
    schemaMap,
    schemaLoading,
    schemaError,
    allowedCommands,
    capabilitiesLoaded: capabilities !== undefined,
    capabilitiesError,
    modelCommandsMissing,
    controlState,
    reported,
    desired,
    syncStatus,
    hasReportedConfig,
    stateLoading,
    stateError,
    history: history?.slice(0, 10) ?? [],
    sendingKey,
    reading,
    canRead,
    readCurrent,
    getMeta,
    getEditValue,
    getSummaryValue,
    fieldLabel,
    enumLabel,
    isVisible,
    canEdit,
    isSynced,
    sendValue,
    refetchAll: () => {
      void refetchSchema()
      void refetchState()
      void refetchCapabilities()
    },
  }
}

export type DeviceConfigApi = ReturnType<typeof useDeviceConfig>
