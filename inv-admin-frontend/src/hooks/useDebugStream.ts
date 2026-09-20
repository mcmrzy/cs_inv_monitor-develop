/**
 * 调试采样 SSE 订阅（替代旧的 10s 轮询：会话、采样各拉一次）。
 *
 * 服务端事件（见 business-api DeviceDebugHandler.StreamSamples）：
 *  - snapshot：连接建立时的首帧 = 会话 + 设备在线 + 时间窗内已有采样；
 *  - samples ：有新采样点时的增量帧（含当前会话）；
 *  - session ：无新点时定期补推的会话状态帧（含 device_online）；
 *  - stream_error：服务端异常（鉴权失败等），连接会随之关闭。
 *
 * EventSource 不支持自定义 Header，token 走查询参数（与 usePipelineHealthSSE 一致）。
 * 会话 id 变化（旧会话结束、又开了一次）时自动清空本地累积点，避免两个会话的曲线混在一起。
 */
import { useCallback, useEffect, useRef, useState } from 'react'

import useAuthStore from '@/stores/authStore'
import { API_BASE } from '@/utils/urls'
import type { DebugSample, DebugSession } from '@/services/deviceApi'

export interface DebugStreamState {
  samples: DebugSample[]
  session: DebugSession | null
  deviceOnline: boolean
  /** SSE 连接已建立 */
  connected: boolean
  error: string | null
}

interface UseDebugStreamOptions {
  /** 时间窗（分钟），变化会重连并由服务端重发该窗口的快照 */
  windowMinutes: number
  /** 仅在存在可订阅的会话时开启 */
  enabled: boolean
  /** 本地累积点上限，超出裁掉最旧的 */
  maxPoints?: number
}

const RECONNECT_DELAY_MS = 4000
/** 连续失败达到该次数后停止自动重连，等用户手动重试 */
const MAX_RECONNECT_ATTEMPTS = 6

/** 合并增量采样：按 time 去重、升序，超出上限裁掉最旧的 */
function mergeSamples(prev: DebugSample[], incoming: DebugSample[], maxPoints: number): DebugSample[] {
  if (incoming.length === 0) return prev
  const byTime = new Map<string, DebugSample>()
  for (const sample of prev) byTime.set(sample.time, sample)
  for (const sample of incoming) byTime.set(sample.time, sample)
  const merged = [...byTime.values()].sort((a, b) => a.time.localeCompare(b.time))
  return merged.length > maxPoints ? merged.slice(merged.length - maxPoints) : merged
}

export function useDebugStream(sn: string, { windowMinutes, enabled, maxPoints = 400 }: UseDebugStreamOptions) {
  const token = useAuthStore((s) => s.token)
  const [state, setState] = useState<DebugStreamState>({
    samples: [], session: null, deviceOnline: false, connected: false, error: null,
  })

  const esRef = useRef<EventSource | null>(null)
  const retryTimerRef = useRef<ReturnType<typeof setTimeout>>()
  const failureCountRef = useRef(0)
  const mountedRef = useRef(true)
  const sessionIdRef = useRef<number | null>(null)
  const maxPointsRef = useRef(maxPoints)
  maxPointsRef.current = maxPoints

  const applySession = useCallback((session: DebugSession | null, deviceOnline?: boolean) => {
    setState((prev) => {
      // 换了会话：清空旧会话的累积点，从新会话的快照重新开始
      const sessionChanged = (session?.id ?? null) !== sessionIdRef.current
      sessionIdRef.current = session?.id ?? null
      return {
        ...prev,
        session,
        deviceOnline: deviceOnline ?? prev.deviceOnline,
        samples: sessionChanged ? [] : prev.samples,
      }
    })
  }, [])

  const appendSamples = useCallback((incoming: DebugSample[]) => {
    if (incoming.length === 0) return
    setState((prev) => ({ ...prev, samples: mergeSamples(prev.samples, incoming, maxPointsRef.current) }))
  }, [])

  const close = useCallback(() => {
    if (retryTimerRef.current) {
      clearTimeout(retryTimerRef.current)
      retryTimerRef.current = undefined
    }
    if (esRef.current) {
      esRef.current.close()
      esRef.current = null
    }
    if (mountedRef.current) setState((prev) => ({ ...prev, connected: false }))
  }, [])

  const connect = useCallback(() => {
    close()
    if (!enabled || !token) return

    // EventSource 带不了 Authorization 头，token 走查询参数（服务端 AuthWithQueryToken）
    const url = `${API_BASE}/devices/by-sn/${encodeURIComponent(sn)}/debug-stream`
      + `?token=${encodeURIComponent(token)}&window_minutes=${windowMinutes}`
    const es = new EventSource(url)
    esRef.current = es

    const onSnapshot = (e: Event) => {
      if (!mountedRef.current) return
      const payload = JSON.parse((e as MessageEvent).data) as {
        session: DebugSession | null
        device_online: boolean
        items: DebugSample[]
      }
      applySession(payload.session, payload.device_online)
      appendSamples(payload.items ?? [])
      failureCountRef.current = 0
      setState((prev) => ({ ...prev, connected: true, error: null }))
    }

    const onSamples = (e: Event) => {
      if (!mountedRef.current) return
      const payload = JSON.parse((e as MessageEvent).data) as {
        items: DebugSample[]
        session: DebugSession | null
      }
      applySession(payload.session)
      appendSamples(payload.items ?? [])
    }

    const onSession = (e: Event) => {
      if (!mountedRef.current) return
      const payload = JSON.parse((e as MessageEvent).data) as {
        session: DebugSession | null
        device_online: boolean
      }
      applySession(payload.session, payload.device_online)
    }

    const onStreamError = (e: Event) => {
      if (!mountedRef.current) return
      try {
        const payload = JSON.parse((e as MessageEvent).data) as { message?: string }
        setState((prev) => ({ ...prev, error: payload.message || 'stream error' }))
      } catch {
        setState((prev) => ({ ...prev, error: 'stream error' }))
      }
    }

    es.addEventListener('open', () => {
      if (!mountedRef.current) return
      failureCountRef.current = 0
      setState((prev) => ({ ...prev, connected: true, error: null }))
    })
    es.addEventListener('snapshot', onSnapshot)
    es.addEventListener('samples', onSamples)
    es.addEventListener('session', onSession)
    es.addEventListener('stream_error', onStreamError)
    es.addEventListener('error', () => {
      if (!mountedRef.current) return
      setState((prev) => ({ ...prev, connected: false, error: prev.error ?? 'SSE connection lost' }))
      // EventSource 内置重连；连接彻底关闭（服务端 4xx/5xx 等）时手动兜底重连
      if (es.readyState === EventSource.CLOSED) {
        failureCountRef.current += 1
        if (failureCountRef.current >= MAX_RECONNECT_ATTEMPTS) {
          setState((prev) => ({ ...prev, error: 'SSE connection failed' }))
          return
        }
        if (retryTimerRef.current) clearTimeout(retryTimerRef.current)
        retryTimerRef.current = setTimeout(connect, RECONNECT_DELAY_MS)
      }
    })
  }, [sn, windowMinutes, enabled, token, applySession, appendSamples, close])

  // 页面不可见时断开（服务端仍按 2s 轮询数据库，没必要为隐藏页白耗），回到前台自动重连
  useEffect(() => {
    const onVisibility = () => {
      if (!enabled) return
      if (document.visibilityState === 'visible') connect()
      else close()
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [connect, close, enabled])

  useEffect(() => {
    mountedRef.current = true
    connect()
    return () => {
      mountedRef.current = false
      close()
    }
  }, [connect, close])

  const reconnect = useCallback(() => {
    failureCountRef.current = 0
    setState((prev) => ({ ...prev, error: null }))
    connect()
  }, [connect])

  return { ...state, reconnect }
}
