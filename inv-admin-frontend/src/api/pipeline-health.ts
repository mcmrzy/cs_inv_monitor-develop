import api from '@/services/api';
import type {
  PipelineHealthResponse,
  PipelineMetricsResponse,
  DLQListResponse,
} from '@/types/pipeline-health';

const BASE = '/system';

/**
 * 获取聚合管道健康状态
 * GET /api/v1/system/pipeline-health
 */
export async function getPipelineHealth(): Promise<PipelineHealthResponse> {
  const resp = await api.get<{ data: PipelineHealthResponse }>(
    `${BASE}/pipeline-health`,
    { expectedDataShape: 'object' },
  );
  return resp.data.data;
}

/**
 * 获取管道关键指标
 * GET /api/v1/system/pipeline-metrics
 */
export async function getPipelineMetrics(): Promise<PipelineMetricsResponse> {
  const resp = await api.get<{ data: PipelineMetricsResponse }>(
    `${BASE}/pipeline-metrics`,
    { expectedDataShape: 'object' },
  );
  return resp.data.data;
}

/**
 * 获取 DLQ 消息列表（分页）
 * GET /api/v1/system/dlq
 */
export async function getDLQList(
  page: number = 1,
  pageSize: number = 20,
  consumerType?: string,
): Promise<DLQListResponse> {
  const params: Record<string, unknown> = { page, page_size: pageSize };
  if (consumerType) params.consumer_type = consumerType;
  const resp = await api.get<{ data: DLQListResponse }>(
    `${BASE}/dlq`,
    { params, expectedDataShape: 'page' },
  );
  return resp.data.data;
}

/**
 * 重试单条 DLQ 消息
 * POST /api/v1/system/dlq/messages/:id/retry
 */
export async function retryDLQItem(id: string): Promise<void> {
  await api.post(`${BASE}/dlq/messages/${encodeURIComponent(id)}/retry`);
}

/**
 * 删除单条 DLQ 消息
 * DELETE /api/v1/system/dlq/messages/:id
 */
export async function deleteDLQItem(id: string): Promise<void> {
  await api.delete(`${BASE}/dlq/messages/${encodeURIComponent(id)}`);
}
