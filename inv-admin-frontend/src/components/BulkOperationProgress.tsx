import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  Card,
  Typography,
  Progress,
  Button,
  Space,
  Tag,
  message,
  Spin,
  Result,
  Descriptions,
  Timeline,
} from 'antd';
import {
  CheckCircleOutlined,
  CloseCircleOutlined,
  SyncOutlined,
  ClockCircleOutlined,
  ReloadOutlined,
} from '@ant-design/icons';
import { useWebSocket } from '@/hooks/useWebSocket';
import { useQuery } from '@tanstack/react-query';

const { Title, Text } = Typography;

interface JobStatus {
  job_id: string;
  job_type: string;
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled';
  total: number;
  processed: number;
  progress: number;
  retry_count: number;
  error_message?: string;
  created_at: number;
  updated_at: number;
  completed_at?: number;
}

interface BulkOperationProgressProps {
  jobId: string;
  onComplete?: (jobStatus: JobStatus) => void;
  onError?: (error: string) => void;
}

// API client for fetching job status
const fetchJobStatus = async (jobId: string): Promise<JobStatus> => {
  const response = await fetch(`/api/v1/jobs/${jobId}/status`);
  if (!response.ok) {
    throw new Error('Failed to fetch job status');
  }
  return response.json();
};

export function BulkOperationProgress({ 
  jobId, 
  onComplete, 
  onError 
}: BulkOperationProgressProps) {
  const [jobStatus, setJobStatus] = useState<JobStatus | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'connecting' | 'connected' | 'disconnected'>('connecting');
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // React Query for initial job status fetch
  const { data: initialStatus, isLoading, error: queryError } = useQuery({
    queryKey: ['jobStatus', jobId],
    queryFn: () => fetchJobStatus(jobId),
    refetchInterval: jobStatus?.status === 'processing' ? 5000 : false,
    refetchOnWindowFocus: false,
  });

  // WebSocket connection for real-time updates
  const { lastMessage, readyState } = useWebSocket(`/ws/jobs/${jobId}/progress?user_id=${getCurrentUserId()}`);

  // Handle WebSocket messages
  useEffect(() => {
    if (lastMessage) {
      try {
        const data = JSON.parse(lastMessage.data);
        
        if (data.type === 'status') {
          setJobStatus(data.data);
          setConnectionStatus('connected');
        } else if (data.type === 'progress') {
          setJobStatus(prev => prev ? {
            ...prev,
            progress: data.data.progress,
            processed: data.data.progress,
            status: data.data.status,
          } : null);
        } else if (data.type === 'complete') {
          setJobStatus(prev => prev ? {
            ...prev,
            status: data.data.status,
            completed_at: Date.now() / 1000,
          } : null);
          
          if (data.data.status === 'completed') {
            message.success('批量操作已完成！');
            onComplete?.(data.data);
          } else if (data.data.status === 'failed') {
            message.error('批量操作失败');
            onError?.(data.data.error_message || 'Unknown error');
          }
        }
      } catch (error) {
        console.error('Failed to parse WebSocket message:', error);
      }
    }
  }, [lastMessage, onComplete, onError]);

  // Set initial status from query
  useEffect(() => {
    if (initialStatus && !jobStatus) {
      setJobStatus(initialStatus);
      setConnectionStatus('connected');
    }
  }, [initialStatus, jobStatus]);

  // Handle connection state changes
  useEffect(() => {
    if (readyState === WebSocket.OPEN) {
      setConnectionStatus('connected');
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
    } else if (readyState === WebSocket.CONNECTING) {
      setConnectionStatus('connecting');
    } else if (readyState === WebSocket.CLOSED || readyState === WebSocket.CLOSING) {
      setConnectionStatus('disconnected');
      
      // Auto-reconnect after 3 seconds
      reconnectTimeoutRef.current = setTimeout(() => {
        console.log('Attempting to reconnect WebSocket...');
      }, 3000);
    }

    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
    };
  }, [readyState]);

  const percentage = jobStatus 
    ? Math.round((jobStatus.processed / jobStatus.total) * 100) 
    : 0;

  const getStatusTag = () => {
    if (!jobStatus) return null;

    const statusMap = {
      pending: { color: 'default', icon: <ClockCircleOutlined />, text: '等待中' },
      processing: { color: 'processing', icon: <SyncOutlined spin />, text: '处理中' },
      completed: { color: 'success', icon: <CheckCircleOutlined />, text: '已完成' },
      failed: { color: 'error', icon: <CloseCircleOutlined />, text: '失败' },
      cancelled: { color: 'warning', icon: <CloseCircleOutlined />, text: '已取消' },
    };

    const config = statusMap[jobStatus.status];
    return (
      <Tag color={config.color} icon={config.icon}>
        {config.text}
      </Tag>
    );
  };

  const getProgressStatus = () => {
    if (!jobStatus) return 'normal';
    if (jobStatus.status === 'failed') return 'exception';
    if (jobStatus.status === 'completed') return 'success';
    return 'active';
  };

  const formatTime = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleString('zh-CN');
  };

  if (isLoading) {
    return (
      <Card>
        <div style={{ textAlign: 'center', padding: '40px' }}>
          <Spin size="large" tip="加载作业状态..." />
        </div>
      </Card>
    );
  }

  if (queryError) {
    return (
      <Card>
        <Result
          status="error"
          title="加载作业信息失败"
          subTitle="无法获取作业状态，请检查作业是否存在或已过期"
          extra={[
            <Button 
              key="retry" 
              type="primary" 
              icon={<ReloadOutlined />}
              onClick={() => window.location.reload()}
            >
              重试
            </Button>,
          ]}
        />
      </Card>
    );
  }

  return (
    <Card
      title={
        <Space>
          <Title level={5} style={{ margin: 0 }}>
            批量操作进度
          </Title>
          {getStatusTag()}
          {connectionStatus === 'disconnected' && (
            <Tag color="warning">连接已断开</Tag>
          )}
        </Space>
      }
    >
      {jobStatus && (
        <Space direction="vertical" style={{ width: '100%' }} size="large">
          {/* Progress Bar */}
          <div>
            <Progress
              percent={percentage}
              status={getProgressStatus()}
              strokeColor={{
                '0%': '#108ee9',
                '100%': '#87d068',
              }}
              format={() => `${jobStatus.processed} / ${jobStatus.total}`}
            />
            <Text type="secondary" style={{ fontSize: '14px' }}>
              {percentage}% 完成
            </Text>
          </div>

          {/* Job Details */}
          <Descriptions column={2} size="small" bordered>
            <Descriptions.Item label="作业ID">
              <Text code>{jobStatus.job_id}</Text>
            </Descriptions.Item>
            <Descriptions.Item label="作业类型">
              {getJobTypeName(jobStatus.job_type)}
            </Descriptions.Item>
            <Descriptions.Item label="总数量">
              {jobStatus.total}
            </Descriptions.Item>
            <Descriptions.Item label="已处理">
              {jobStatus.processed}
            </Descriptions.Item>
            <Descriptions.Item label="创建时间">
              {formatTime(jobStatus.created_at)}
            </Descriptions.Item>
            <Descriptions.Item label="更新时间">
              {formatTime(jobStatus.updated_at)}
            </Descriptions.Item>
            {jobStatus.completed_at && (
              <Descriptions.Item label="完成时间" span={2}>
                {formatTime(jobStatus.completed_at)}
              </Descriptions.Item>
            )}
            {jobStatus.retry_count > 0 && (
              <Descriptions.Item label="重试次数">
                <Tag color="orange">{jobStatus.retry_count}</Tag>
              </Descriptions.Item>
            )}
          </Descriptions>

          {/* Error Message */}
          {jobStatus.error_message && (
            <div>
              <Text type="danger" strong>
                错误信息：
              </Text>
              <Text type="secondary" style={{ marginLeft: '8px' }}>
                {jobStatus.error_message}
              </Text>
            </div>
          )}

          {/* Action Buttons */}
          {(jobStatus.status === 'completed' || jobStatus.status === 'failed') && (
            <Space>
              <Button 
                type="primary" 
                onClick={() => window.location.reload()}
                icon={<ReloadOutlined />}
              >
                刷新列表
              </Button>
              {jobStatus.status === 'failed' && (
                <Button 
                  danger
                  onClick={() => message.info('请联系管理员重试')}
                >
                  联系支持
                </Button>
              )}
            </Space>
          )}
        </Space>
      )}
    </Card>
  );
}

// Helper function to get user ID from current context
function getCurrentUserId(): string {
  // This should be replaced with actual user ID retrieval logic
  const userStr = localStorage.getItem('user');
  if (userStr) {
    try {
      const user = JSON.parse(userStr);
      return user.id?.toString() || '0';
    } catch {
      return '0';
    }
  }
  return '0';
}

// Helper function to get job type display name
function getJobTypeName(jobType: string): string {
  const typeMap: Record<string, string> = {
    bulk_add_members: '批量添加成员',
    bulk_transfer_members: '批量转移成员',
    bulk_export: '批量导出',
    bulk_import: '批量导入',
  };
  return typeMap[jobType] || jobType;
}

// Hook for bulk operations with progress tracking
export function useBulkOperation() {
  const [currentJobId, setCurrentJobId] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);

  const startBulkOperation = async (
    endpoint: string,
    data: any
  ): Promise<string> => {
    setIsProcessing(true);
    
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      if (!response.ok) {
        throw new Error('Failed to start bulk operation');
      }

      const result = await response.json();
      const jobId = result.job_id;
      
      setCurrentJobId(jobId);
      message.success(`任务已创建，正在后台处理`);
      
      return jobId;
    } finally {
      setIsProcessing(false);
    }
  };

  return {
    currentJobId,
    isProcessing,
    startBulkOperation,
  };
}

export default BulkOperationProgress;
