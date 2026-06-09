import { useState, useEffect } from 'react'
import { Navigate } from 'react-router-dom'
import { Spin } from 'antd'
import useAuthStore from '@/stores/authStore'

interface ProtectedRouteProps {
  children: React.ReactNode
}

const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const [ready, setReady] = useState(false)
  const token = useAuthStore((s) => s.token)

  useEffect(() => {
    const t0 = useAuthStore.getState().token
    if (t0) {
      setReady(true)
      return
    }
    const unsub = useAuthStore.subscribe((state) => {
      if (state.token) {
        setReady(true)
      }
    })
    const timer = setTimeout(() => setReady(true), 2000)
    return () => {
      unsub()
      clearTimeout(timer)
    }
  }, [])

  if (!ready) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>
        <Spin size="large" />
      </div>
    )
  }

  if (!token) {
    return <Navigate to="/login" replace />
  }

  return <>{children}</>
}

export default ProtectedRoute
