import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import { App } from 'antd'

/**
 * 共享 Hook：封装 controlState query + sendCommand mutation
 * 消除 ChargeSettingsTab / DischargeSettingsTab / PowerControlTab / GeneralSettingsTab 中的重复代码
 */
export function useControlState(sn: string) {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()

  // ── Query: control state（每 15 s 轮询）──
  const {
    data: controlState,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: queryKeys.devices.controlState(sn),
    queryFn: () => deviceApi.getControlState(sn).then((r) => (r as any).data?.data ?? null),
    refetchInterval: 15000,
  })

  const reported = (controlState as any)?.reported ?? {}
  const isOnline = (controlState as any)?.sync_status !== 'unknown'

  // ── Mutation: send command ──
  const commandMutation = useMutation({
    mutationFn: (payload: { command: string; params?: Record<string, unknown> }) =>
      deviceApi.sendCommand(sn, payload).then((r: any) => {
        const d = r.data?.data ?? r.data
        if (d && d.success === false) throw new Error(d.message ?? t('common.failed'))
        return d
      }),
    onSuccess: () => {
      message.success(t('common.success'))
      void queryClient.invalidateQueries({ queryKey: queryKeys.devices.controlState(sn) })
      void queryClient.invalidateQueries({ queryKey: queryKeys.devices.commands(sn) })
    },
    onError: (err: Error) => {
      message.error(err.message || t('common.failed'))
    },
  })

  const sendCommand = (command: string, params?: Record<string, unknown>) => {
    commandMutation.mutate({ command, params })
  }

  return {
    controlState,
    reported,
    isOnline,
    isLoading,
    error,
    refetch,
    sendCommand,
    isSending: commandMutation.isPending,
  }
}
