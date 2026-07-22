// Pipeline Health Service Types
// Spec: docs/superpowers/specs/2026-07-22-device-pipeline-reliability-observability-design.md §14

export type ServiceStatus = 'ok' | 'degraded' | 'down';

export interface BridgeHealth {
  status: ServiceStatus;
  kafka_connected: boolean;
  last_heartbeat: string;
}

export interface DeviceServerHealth {
  status: ServiceStatus;
  kafka_lag: number;
  redis: 'connected' | 'disconnected';
  last_heartbeat: string;
}

export interface ApiHealth {
  status: ServiceStatus;
  db_pool_active: number;
  last_heartbeat: string;
}

export interface PipelineHealthServices {
  bridge: BridgeHealth;
  'device-server': DeviceServerHealth;
  api: ApiHealth;
}

export interface PipelineHealthSummary {
  online_devices: number;
  total_devices: number;
  connection_rate: string;
}

export interface PipelineHealthResponse {
  overall_status: ServiceStatus;
  services: PipelineHealthServices;
  summary: PipelineHealthSummary;
}

export interface PipelineMetricsResponse {
  message_rate: number;
  kafka_lag: number;
  commands_sent: number;
  commands_acked: number;
  commands_expired: number;
  commands_success_rate: number;
}

export interface DLQItem {
  id: string;
  consumer_type: string;
  topic: string;
  payload_summary: string;
  error_message: string;
  retry_count: number;
  created_at: string;
}

export interface DLQListResponse {
  items: DLQItem[];
  total: number;
  page: number;
  page_size: number;
}

/** SSE pipeline_health event payload */
export interface PipelineHealthSSEEvent {
  overall_status: ServiceStatus;
  online_devices: number;
  total_devices: number;
  message_rate: number;
  dlq_pending: number;
}
