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

  if (businessCode !== undefined && businessCode !== 0) {
    return `API ${businessCode}${detail ? ` · ${detail}` : ''}`
  }
  if (status) return `HTTP ${status}${detail ? ` · ${detail}` : ''}`
  return detail || String(error || '')
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
