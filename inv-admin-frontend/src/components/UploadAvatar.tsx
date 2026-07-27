import React, { useState } from 'react'
import { Upload, Avatar, message, Spin } from 'antd'
import { UserOutlined, CameraOutlined } from '@ant-design/icons'
import type { UploadProps } from 'antd'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'

interface UploadAvatarProps {
  value?: string
  onChange?: (url: string) => void
  size?: number
}

const UploadAvatar: React.FC<UploadAvatarProps> = ({ value, onChange, size = 100 }) => {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(false)
  const token = useAuthStore((state) => state.token)

  const beforeUpload: UploadProps['beforeUpload'] = (file) => {
    const isImage = file.type.startsWith('image/')
    if (!isImage) {
      message.error(t('upload.imageOnly'))
      return false
    }
    const isLt2M = file.size / 1024 / 1024 < 2
    if (!isLt2M) {
      message.error(t('upload.sizeLimit'))
      return false
    }
    return true
  }

  const handleChange: UploadProps['onChange'] = (info) => {
    if (info.file.status === 'uploading') {
      setLoading(true)
      return
    }
    if (info.file.status === 'done') {
      setLoading(false)
      const response = info.file.response
      if (response?.code === 0 && response?.data?.url) {
        onChange?.(response.data.url)
        message.success(t('upload.success'))
      } else {
        message.error(response?.message || t('upload.failed'))
      }
    }
    if (info.file.status === 'error') {
      setLoading(false)
      message.error(t('upload.failed'))
    }
  }

  return (
    <Upload
      name="file"
      action="/api/v1/upload/avatar"
      headers={{
        Authorization: token ? `Bearer ${token}` : '',
      }}
      showUploadList={false}
      beforeUpload={beforeUpload}
      onChange={handleChange}
      accept="image/*"
    >
      <div
        style={{
          position: 'relative',
          cursor: 'pointer',
          display: 'inline-block',
        }}
      >
        <Spin spinning={loading}>
          <Avatar
            size={size}
            src={value || undefined}
            icon={<UserOutlined />}
            style={{
              border: '2px solid #d9d9d9',
              transition: 'border-color 0.3s',
            }}
          />
        </Spin>
        <div
          style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            height: 28,
            background: 'rgba(0, 0, 0, 0.5)',
            borderRadius: '0 0 50% 50%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: '#fff',
            fontSize: 12,
          }}
        >
          <CameraOutlined style={{ marginRight: 4 }} />
          {t('upload.changeAvatar')}
        </div>
      </div>
    </Upload>
  )
}

export default UploadAvatar
