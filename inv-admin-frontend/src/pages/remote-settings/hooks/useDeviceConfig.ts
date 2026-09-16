// 远程设置数据层：config-schema + control-state 读取、命令下发（沿用现有命令构造）
//
// 下发约定（与 SchemaGroupPanel 现有逻辑一致）：
//   deviceApi.sendCommand(sn, { command: <param_key>, params: { value: <工程单位值> } })
// V2.1 起 control-state 与命令参数均为工程单位（物理量），服务端按 schema min/max 校验；
// raw = round(physical × scale) 仅在对接原始量纲来源时使用（见 conversion.ts）。

import { useCallback, useMemo, useState } from 'react'
import { App } from 'antd'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import type { ConfigSchemaItem } from '../config/fields'
import { normalizeIncoming, resolveFieldMeta, type ResolvedFieldMeta } from '../config/conversion'
import type { CommandRecord } from '../types'

export function useDeviceConfig(sn: string) {
  const { t } = useTranslation()
  const { message, modal } = App.useApp()
  const queryClient = useQueryClient()
  const hasPermission = useAuthStore((s) => s.hasPermission)
  const [sendingKey, setSendingKey] = useState<string | null>(null)

  const { data: schemaItems, isLoading: schemaLoading, error: schemaError, refetch: refetchSchema } = useQuery({
    queryKey: ['config-schema', sn],
    queryFn: () =>
      deviceApi.getConfigSchema(sn).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        // 兼容直接数组 / {items:[...]} 两种形状，非数组一律降级为空列表
        return (Array.isArray(d) ? d : (Array.isArray((d as any)?.items) ? (d as any).items : [])) as ConfigSchemaItem[]
      }),
    staleTime: 300_000,
  })

  // 型号控制命令能力（与 /control 校验同源）。schema 已按型号过滤后仍加载一份，
  // 用于下发前二次拦截，以及 Advanced 中 reported 但不可写的扩展键只读展示。
  const { data: capabilities, refetch: refetchCapabilities } = useQuery({
    queryKey: queryKeys.devices.controlCapabilities(sn),
    queryFn: () =>
      deviceApi.getControlCapabilities(sn).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (Array.isArray(d) ? d : []) as Array<{ command_code: string; is_enabled?: boolean }>
      }),
    staleTime: 300_000,
  })

  const allowedCommands = useMemo(() => {
    const s = new Set<string>()
    for (const c of capabilities ?? []) {
      if (c?.command_code && c.is_enabled !== false) s.add(c.command_code)
    }
    return s
  }, [capabilities])

  const { data: controlState, isLoading: stateLoading, error: stateError, refetch: refetchState } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => (r.data?.data ?? null) as any),
    refetchInterval: 10_000,
  })

  const { data: history, refetch: refetchHistory } = useQuery({
    queryKey: ['device-commands', sn],
    queryFn: () =>
      deviceApi.getCommands(sn, { page: 1, page_size: 10 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as CommandRecord[]
      }),
    refetchInterval: 10_000,
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

  const getMeta = useCallback(
    (paramKey: string): ResolvedFieldMeta => resolveFieldMeta(schemaMap, paramKey),
    [schemaMap],
  )

  /** 编辑态当前值（工程单位）：desired 优先（已下发待同步的意图），否则 reported */
  const getEditValue = useCallback(
    (paramKey: string): number | undefined => {
      const meta = resolveFieldMeta(schemaMap, paramKey)
      const v = normalizeIncoming(desired[paramKey], meta)
      return v !== undefined ? v : normalizeIncoming(reported[paramKey], meta)
    },
    [schemaMap, desired, reported],
  )

  /** 展示态当前值（工程单位）：reported 优先（设备实际值），缺失时回退 desired */
  const getSummaryValue = useCallback(
    (paramKey: string): number | undefined => {
      const meta = resolveFieldMeta(schemaMap, paramKey)
      const v = normalizeIncoming(reported[paramKey], meta)
      return v !== undefined ? v : normalizeIncoming(desired[paramKey], meta)
    },
    [schemaMap, desired, reported],
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
      const cur = reported[v.param] ?? desired[v.param]
      if (cur === undefined) return false
      const num = Number(cur)
      if (v.eq !== undefined) return num === v.eq
      if (v.ne !== undefined) return num !== v.ne
      return true
    },
    [reported, desired],
  )

  /** 参数是否可编辑（后端 permission_code 校验） */
  const canEdit = useCallback(
    (paramKey: string): boolean => {
      // schema 已按设备型号命令裁剪：未登记的参数一律只读（含 Advanced 扩展键）
      if (!schemaMap.has(paramKey)) return false
      // 能力表加载后二次拦截禁用命令；能力表尚未返回时不额外阻塞
      if (allowedCommands.size > 0 && !allowedCommands.has(paramKey)) return false
      const code = schemaMap.get(paramKey)?.permission_code
      return !code || hasPermission(code)
    },
    [schemaMap, hasPermission, allowedCommands],
  )

  /** desired 与 reported 是否一致（用于同步徽标） */
  const isSynced = useCallback(
    (paramKey: string): 'synced' | 'pending' | 'none' => {
      const d = desired[paramKey]
      if (d === undefined) return 'none'
      const r = reported[paramKey]
      if (r !== undefined && String(d) === String(r)) return 'synced'
      return 'pending'
    },
    [desired, reported],
  )

  const doSend = useCallback(
    (meta: ResolvedFieldMeta, physical: number) => {
      if (allowedCommands.size > 0 && !allowedCommands.has(meta.paramKey)) {
        message.error(`${t('remote.commandSendFailed')}: ${t('remote.commandNotAllowed')}`)
        return
      }
      setSendingKey(meta.paramKey)
      deviceApi
        .sendCommand(sn, { command: meta.paramKey, params: { value: physical } })
        .then(() => {
          message.success(t('remote.commandSent', { taskId: '' }))
          void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
          void refetchHistory()
        })
        .catch((err: any) => {
          const detail = err?.response?.data?.data?.reject_detail ?? err?.response?.data?.message ?? err?.message ?? ''
          message.error(`${t('remote.commandSendFailed')}${detail ? `: ${detail}` : ''}`)
        })
        .finally(() => setSendingKey(null))
    },
    [sn, message, t, queryClient, refetchHistory, allowedCommands],
  )

  /** 下发工程单位值；confirm 字段弹二次确认（沿用现有确认逻辑） */
  const sendValue = useCallback(
    (meta: ResolvedFieldMeta, physical: number) => {
      if (physical === undefined || physical === null || Number.isNaN(physical)) {
        message.warning(t('remote.paramRequired'))
        return
      }
      if (meta.confirm) {
        modal.confirm({
          title: t('remote.confirmSendTitle'),
          content: t('remote.confirmSendContent', { sn, cmd: fieldLabel(meta.paramKey) }),
          okText: t('remote.confirmExecute'),
          cancelText: t('remote.cancel'),
          okButtonProps: { danger: true },
          onOk: () => doSend(meta, physical),
        })
        return
      }
      doSend(meta, physical)
    },
    [sn, modal, message, t, fieldLabel, doSend],
  )

  return {
    schemaItems: schemaItems ?? [],
    schemaMap,
    schemaLoading,
    schemaError,
    allowedCommands,
    capabilitiesLoaded: capabilities !== undefined,
    modelCommandsMissing,
    controlState,
    reported,
    desired,
    syncStatus,
    hasReportedConfig,
    stateLoading,
    stateError,
    history: history ?? [],
    sendingKey,
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
