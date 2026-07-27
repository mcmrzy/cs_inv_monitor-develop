import { Alert, Button } from 'antd'
import type { AxiosError } from 'axios'
import useTranslation from '@/hooks/useTranslation'

interface ApiEnvelope {
  message?: string
}

export function formatQueryError(error: unknown): string {
  const axiosError = error as AxiosError<ApiEnvelope>
  const status = axiosError.response?.status
  const businessCode = (axiosError.response?.data as { code?: number } | undefined)?.code
  const detail = axiosError.response?.data?.message
    || (error instanceof Error ? error.message : '')

  // 优先显示业务错误码（非0表示业务错误）
  if (businessCode !== undefined && businessCode !== 0) {
    return `API ${businessCode}${detail ? ` · ${detail}` : ''}`
  }
  
  // 如果有 HTTP 状态码且不是 200，显示 HTTP 错误
  if (status && status !== 200) return `HTTP ${status}${detail ? ` · ${detail}` : ''}`
  
  // 如果有详细错误信息，显示它
  if (detail && detail !== 'success') return detail
  
  // 最后显示错误对象字符串
  return String(error || '')
}

interface QueryErrorAlertProps {
  error: unknown
  onRetry?: () => void
  message?: string
  style?: React.CSSProperties
}

const QueryErrorAlert: React.FC<QueryErrorAlertProps> = ({ error, onRetry, message, style }) => {
  const { t } = useTranslation()
  return (
    <Alert
      type="error"
      showIcon
      message={message || t('common.failed')}
      description={formatQueryError(error)}
      action={onRetry ? <Button size="small" onClick={onRetry}>{t('common.refresh')}</Button> : undefined}
      style={style}
    />
  )
}

export default QueryErrorAlert
