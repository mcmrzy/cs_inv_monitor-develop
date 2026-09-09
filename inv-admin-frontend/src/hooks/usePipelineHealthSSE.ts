import { useState, useEffect, useRef, useCallback } from 'react';
import useAuthStore from '@/stores/authStore';
import { API_BASE } from '@/utils/urls';
import type { PipelineHealthSSEEvent } from '@/types/pipeline-health';

interface UsePipelineHealthSSEReturn {
  /** 最新 SSE 推送的管道健康事件数据 */
  event: PipelineHealthSSEEvent | null;
  /** SSE 连接是否已建立 */
  connected: boolean;
  /** 最近一次连接错误 */
  error: string | null;
  /** 手动关闭并重新建立连接 */
  reconnect: () => void;
}

const SSE_URL = `${API_BASE}/system/pipeline-health/stream`;
const RECONNECT_DELAY_MS = 5000;
/** 连续失败达到该次数后停止自动重连（避免无限重连），手动 reconnect 可重置计数 */
const MAX_RECONNECT_ATTEMPTS = 5;

export function usePipelineHealthSSE(): UsePipelineHealthSSEReturn {
  const [event, setEvent] = useState<PipelineHealthSSEEvent | null>(null);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const esRef = useRef<EventSource | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout>>();
  const mountedRef = useRef(true);
  const failureCountRef = useRef(0);

  const token = useAuthStore((s) => s.token);

  const connect = useCallback(() => {
    // 清理旧连接
    if (esRef.current) {
      esRef.current.close();
      esRef.current = null;
    }

    if (!token) {
      setError('No auth token');
      return;
    }

    // EventSource 不支持自定义 Header，通过 query param 传递 token
    const url = `${SSE_URL}?token=${encodeURIComponent(token)}`;
    const es = new EventSource(url);
    esRef.current = es;

    es.addEventListener('open', () => {
      if (!mountedRef.current) return;
      failureCountRef.current = 0; // 连接成功，重置连续失败计数
      setConnected(true);
      setError(null);
    });

    es.addEventListener('pipeline_health', (e: Event) => {
      if (!mountedRef.current) return;
      try {
        const data = JSON.parse((e as MessageEvent).data) as PipelineHealthSSEEvent;
        setEvent(data);
        setError(null);
      } catch (err) {
        console.error('[SSE] Failed to parse pipeline_health event:', err);
      }
    });

    es.addEventListener('error', () => {
      if (!mountedRef.current) return;
      setConnected(false);
      // 浏览器 EventSource 内置重连，但连接彻底失败时需要手动处理
      if (es.readyState === EventSource.CLOSED) {
        failureCountRef.current += 1;
        if (failureCountRef.current >= MAX_RECONNECT_ATTEMPTS) {
          // 连续失败达上限：停止自动重连，置错误状态，等待手动刷新重置
          setError('SSE connection failed after multiple attempts');
          return;
        }
        setError('SSE connection lost');
        reconnectTimerRef.current = setTimeout(connect, RECONNECT_DELAY_MS);
      } else {
        setError('SSE connection lost');
      }
    });
  }, [token]);

  useEffect(() => {
    mountedRef.current = true;
    connect();
    return () => {
      mountedRef.current = false;
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
      if (esRef.current) {
        esRef.current.close();
        esRef.current = null;
      }
    };
  }, [connect]);

  const reconnect = useCallback(() => {
    failureCountRef.current = 0; // 手动刷新重置失败计数
    if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
    connect();
  }, [connect]);

  return { event, connected, error, reconnect };
}
