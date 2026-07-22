import { useState, useEffect, useRef, useCallback } from 'react';
import useAuthStore from '@/stores/authStore';

interface UseWebSocketReturn {
  /** 最后收到的消息 */
  lastMessage: MessageEvent | null;
  /** WebSocket 连接状态 (1=CONNECTING, 2=OPEN, 3=CLOSED) */
  readyState: number;
}

const WS_URL = '/ws/jobs';

export function useWebSocket(jobId: string): UseWebSocketReturn {
  const [lastMessage, setLastMessage] = useState<MessageEvent | null>(null);
  const [readyState, setReadyState] = useState<number>(1); // Default to OPEN
  
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<NodeJS.Timeout | null>(null);
  const mountedRef = useRef(true);

  const token = useAuthStore((s) => s.token);

  const connect = useCallback(() => {
    if (!mountedRef.current || !token) {
      return;
    }

    if (wsRef.current) {
      wsRef.current.close();
    }

    try {
      const url = `${WS_URL}/${jobId}/progress?user_id=${useAuthStore.getState().user?.id}`;
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        if (!mountedRef.current) return;
        setReadyState(1); // OPEN
        setLastMessage(null);
      };

      ws.onmessage = (event) => {
        if (!mountedRef.current) return;
        setLastMessage(event);
      };

      ws.onerror = () => {
        if (!mountedRef.current) return;
        setReadyState(3); // CLOSED
      };

      ws.onclose = () => {
        if (!mountedRef.current) return;
        setReadyState(3); // CLOSED
        
        // Auto-reconnect after delay
        reconnectTimerRef.current = setTimeout(() => {
          reconnectTimerRef.current = null;
          if (token) {
            connect();
          }
        }, 5000);
      };
    } catch (error) {
      console.error('[WebSocket] Connection error:', error);
      setReadyState(3);
    }
  }, [jobId, token]);

  useEffect(() => {
    mountedRef.current = true;
    
    if (token) {
      connect();
    }

    return () => {
      mountedRef.current = false;
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [connect, token]);

  return { lastMessage, readyState };
}
