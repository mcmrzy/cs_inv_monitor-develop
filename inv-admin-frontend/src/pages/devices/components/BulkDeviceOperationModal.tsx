import { useCallback, useEffect, useRef, useState } from 'react'
import { Alert, Button, Modal, Progress, Space, Tag, Typography } from 'antd'
import { ReloadOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

export interface BulkFailure {
  sn: string
  message: string
}

export interface BulkSettleResult {
  success: string[]
  failures: BulkFailure[]
}

interface BulkDeviceOperationModalProps {
  open: boolean
  title: string
  /** 本轮要逐台执行的设备 SN 列表 */
  sns: string[]
  /** 单台设备的操作（解绑/删除等），reject 即视为该台失败 */
  execute: (sn: string) => Promise<unknown>
  onCancel: () => void
  /** 全部执行完毕（未被取消）后回调，携带成功/失败明细 */
  onSettled?: (result: BulkSettleResult) => void
}

/**
 * 批量设备操作进度弹窗：
 * - 串行逐台执行，避免 Promise.all 裸跑导致的雪崩与笼统报错
 * - 执行中实时上报「当前第 N/total 台」
 * - 结束后展示成功 x / 失败 y 与失败 SN 列表，支持「重试失败项」
 * - 执行中取消会中止后续设备（当前一台等待在途请求完成后停止）
 */
const BulkDeviceOperationModal: React.FC<BulkDeviceOperationModalProps> = ({
  open,
  title,
  sns,
  execute,
  onCancel,
  onSettled,
}) => {
  const { t } = useTranslation()
  const [running, setRunning] = useState(false)
  const [processed, setProcessed] = useState(0)
  const [current, setCurrent] = useState(0)
  const [total, setTotal] = useState(0)
  const [success, setSuccess] = useState<string[]>([])
  const [failures, setFailures] = useState<BulkFailure[]>([])

  const cancelledRef = useRef(false)
  const executeRef = useRef(execute)
  executeRef.current = execute
  const onSettledRef = useRef(onSettled)
  onSettledRef.current = onSettled

  const run = useCallback(async (queue: string[]) => {
    cancelledRef.current = false
    setRunning(true)
    setProcessed(0)
    setCurrent(0)
    setTotal(queue.length)
    setSuccess([])
    setFailures([])
    const ok: string[] = []
    const bad: BulkFailure[] = []
    for (let i = 0; i < queue.length; i++) {
      if (cancelledRef.current) break
      setCurrent(i + 1)
      const sn = queue[i]!
      try {
        await executeRef.current(sn)
        ok.push(sn)
      } catch (err) {
        const e = err as { response?: { data?: { message?: string } }; message?: string }
        bad.push({ sn, message: e?.response?.data?.message || e?.message || '' })
      }
      setProcessed(i + 1)
      setSuccess([...ok])
      setFailures([...bad])
      if (cancelledRef.current) break
    }
    setRunning(false)
    if (!cancelledRef.current) {
      onSettledRef.current?.({ success: [...ok], failures: [...bad] })
    }
  }, [])

  useEffect(() => {
    if (open && sns.length > 0) {
      void run(sns)
    }
    return () => {
      cancelledRef.current = true
    }
  }, [open, sns, run])

  const percent = total > 0 ? Math.round((processed / total) * 100) : 0

  const handleClose = () => {
    cancelledRef.current = true
    onCancel()
  }

  return (
    <Modal
      open={open}
      title={title}
      onCancel={handleClose}
      maskClosable={false}
      footer={
        running ? (
          <Button onClick={handleClose}>{t('common.cancel')}</Button>
        ) : (
          <Space>
            {failures.length > 0 && (
              <Button
                icon={<ReloadOutlined />}
                onClick={() => void run(failures.map((f) => f.sn))}
              >
                {t('dev.bulkRetryFailed')} ({failures.length})
              </Button>
            )}
            <Button type="primary" onClick={onCancel}>
              {t('common.close')}
            </Button>
          </Space>
        )
      }
    >
      <Space direction="vertical" size="middle" style={{ width: '100%' }}>
        {running && (
          <Text type="secondary">
            {t('dev.bulkRunning')}
            {t('dev.bulkProgressCurrent', { current, total })}
          </Text>
        )}
        <Progress
          percent={percent}
          status={running ? 'active' : failures.length > 0 ? 'exception' : 'success'}
        />
        {!running && (
          <Space size="large">
            <Text>
              {t('dev.bulkSuccessCount')}: <Text type="success" strong>{success.length}</Text>
            </Text>
            <Text>
              {t('dev.bulkFailedCount')}: <Text type="danger" strong>{failures.length}</Text>
            </Text>
          </Space>
        )}
        {!running && failures.length > 0 && (
          <Alert
            type="error"
            showIcon
            message={t('dev.bulkFailedDevices')}
            description={
              <div style={{ maxHeight: 160, overflow: 'auto' }}>
                {failures.map((f) => (
                  <div key={f.sn}>
                    <Tag color="red">{f.sn}</Tag>
                    {f.message && <Text type="secondary">{f.message}</Text>}
                  </div>
                ))}
              </div>
            }
          />
        )}
      </Space>
    </Modal>
  )
}

export default BulkDeviceOperationModal
