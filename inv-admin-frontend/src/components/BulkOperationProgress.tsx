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
import useTranslation from '@/hooks/useTranslation';

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
  const { t } = useTranslation();
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
            message.success(t('bulk.operationCompleted'));
            onComplete?.(data.data);
          } else if (data.data.status === 'failed') {
            message.error(t('bulk.operationFailed'));
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
      pending: { color: 'default', icon: <ClockCircleOutlined />, text: t('bulk.pending') },
      processing: { color: 'processing', icon: <SyncOutlined spin />, text: t('bulk.processing') },
      completed: { color: 'success', icon: <CheckCircleOutlined />, text: t('bulk.completed') },
      failed: { color: 'error', icon: <CloseCircleOutlined />, text: t('bulk.failed') },
      cancelled: { color: 'warning', icon: <CloseCircleOutlined />, text: t('bulk.cancelled') },
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

  const getJobTypeName = (jobType: string): string => {
    const typeMap: Record<string, string> = {
      bulk_add_members: t('bulk.bulkAddMembers'),
      bulk_transfer_members: t('bulk.bulkTransferMembers'),
      bulk_export: t('bulk.bulkExport'),
      bulk_import: t('bulk.bulkImport'),
    };
    return typeMap[jobType] || jobType;
  };

  if (isLoading) {
    return (
      <Card>
        <div style={{ textAlign: 'center', padding: '40px' }}>
          <Spin size="large" tip={t('bulk.loadingStatus')} />
        </div>
      </Card>
    );
  }

  if (queryError) {
    return (
      <Card>
        <Result
          status="error"
          title={t('bulk.loadFailed')}
          subTitle={t('bulk.loadFailedDesc')}
          extra={[
            <Button 
              key="retry" 
              type="primary" 
              icon={<ReloadOutlined />}
              onClick={() => window.location.reload()}
            >
              {t('common.retry')}
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
            {t('bulk.progress')}
          </Title>
          {getStatusTag()}
          {connectionStatus === 'disconnected' && (
            <Tag color="warning">{t('bulk.connectionLost')}</Tag>
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
              {percentage}% {t('bulk.complete')}
            </Text>
          </div>

          {/* Job Details */}
          <Descriptions column={2} size="small" bordered>
            <Descriptions.Item label={t('bulk.jobId')}>
              <Text code>{jobStatus.job_id}</Text>
            </Descriptions.Item>
            <Descriptions.Item label={t('bulk.jobType')}>
              {getJobTypeName(jobStatus.job_type)}
            </Descriptions.Item>
            <Descriptions.Item label={t('bulk.total')}>
              {jobStatus.total}
            </Descriptions.Item>
            <Descriptions.Item label={t('bulk.processed')}>
              {jobStatus.processed}
            </Descriptions.Item>
            <Descriptions.Item label={t('bulk.createdAt')}>
              {formatTime(jobStatus.created_at)}
            </Descriptions.Item>
            <Descriptions.Item label={t('bulk.updatedAt')}>
              {formatTime(jobStatus.updated_at)}
            </Descriptions.Item>
            {jobStatus.completed_at && (
              <Descriptions.Item label={t('bulk.completedAt')} span={2}>
                {formatTime(jobStatus.completed_at)}
              </Descriptions.Item>
            )}
            {jobStatus.retry_count > 0 && (
              <Descriptions.Item label={t('bulk.retryCount')}>
                <Tag color="orange">{jobStatus.retry_count}</Tag>
              </Descriptions.Item>
            )}
          </Descriptions>

          {/* Error Message */}
          {jobStatus.error_message && (
            <div>
              <Text type="danger" strong>
                {t('bulk.errorMessage')}
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
                {t('common.refreshList')}
              </Button>
              {jobStatus.status === 'failed' && (
                <Button 
                  danger
                  onClick={() => message.info(t('bulk.contactAdmin'))}
                >
                  {t('bulk.contactSupport')}
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

// Helper function to get job type display name (moved inside component to use t)
// function getJobTypeName is now defined inside BulkOperationProgress

// Hook for bulk operations with progress tracking
export function useBulkOperation() {
  const { t } = useTranslation();
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
      message.success(t('bulk.taskCreated'));
      
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
