import { useState, useEffect, useRef, useCallback } from 'react';
import useAuthStore from '@/stores/authStore';
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

const SSE_URL = '/api/v1/system/pipeline-health/stream';
const RECONNECT_DELAY_MS = 5000;

export function usePipelineHealthSSE(): UsePipelineHealthSSEReturn {
  const [event, setEvent] = useState<PipelineHealthSSEEvent | null>(null);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const esRef = useRef<EventSource | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout>>();
  const mountedRef = useRef(true);

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
      setError('SSE connection lost');
      // 浏览器 EventSource 内置重连，但连接彻底失败时需要手动处理
      if (es.readyState === EventSource.CLOSED) {
        reconnectTimerRef.current = setTimeout(connect, RECONNECT_DELAY_MS);
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
    if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
    connect();
  }, [connect]);

  return { event, connected, error, reconnect };
}
