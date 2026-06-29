import { Result, Button } from 'antd'
import { useNavigate } from 'react-router-dom'
import useTranslation from '@/hooks/useTranslation'

const UnauthorizedPage: React.FC = () => {
  const navigate = useNavigate()
  const { t } = useTranslation()

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#f0f2f5',
      }}
    >
      <Result
        status="403"
        title="403"
        subTitle={t('unauthorized.title')}
        extra={
          <Button type="primary" onClick={() => navigate('/dashboard')}>
            {t('unauthorized.backHome')}
          </Button>
        }
      />
    </div>
  )
}

export default UnauthorizedPage
