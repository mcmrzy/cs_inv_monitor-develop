import React, { useEffect, useState } from 'react'
import { Alert, App, Form, Input, Modal } from 'antd'
import { UserOutlined } from '@ant-design/icons'
import api from '@/services/api'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import UploadAvatar from '@/components/UploadAvatar'

export type ProfileSetupResult = 'saved' | 'skipped'

interface ProfileSetupModalProps {
  open: boolean
  /** saved = 已保存资料；skipped = 用户选择暂时跳过。两者都不再重复提示 */
  onDone: (result: ProfileSetupResult) => void
}

/**
 * 注册后的一次性「完善资料」引导：头像与昵称都是选填，可整块跳过。
 * 与「个人信息」弹窗（MainLayout）分开维护：这里只做最小引导，避免刚注册就摊开全部字段。
 */
const ProfileSetupModal: React.FC<ProfileSetupModalProps> = ({ open, onDone }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const user = useAuthStore((state) => state.user)

  const [avatar, setAvatar] = useState('')
  const [nickname, setNickname] = useState('')
  const [saving, setSaving] = useState(false)

  // 每次打开都用当前用户资料回填，避免残留上一次打开的输入
  useEffect(() => {
    if (!open) return
    setAvatar(user?.avatar || '')
    setNickname(user?.nickname || '')
  }, [open, user?.avatar, user?.nickname])

  const handleSave = async () => {
    setSaving(true)
    try {
      const trimmed = nickname.trim()
      const res = await api.put('/auth/profile', { nickname: trimmed, avatar })
      const data = res.data as Record<string, unknown>
      if (data?.code !== undefined && data.code !== 0) {
        message.error((data.message as string) || t('msg.profileUpdateFailed'))
        return
      }
      if (user) {
        useAuthStore.setState({
          user: {
            ...user,
            nickname: trimmed || user.nickname,
            avatar: avatar || user.avatar,
          },
        })
      }
      message.success(t('msg.profileUpdated'))
      onDone('saved')
    } catch {
      message.error(t('msg.profileUpdateFailed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal
      title={t('modal.profileSetupTitle')}
      open={open}
      onCancel={() => !saving && onDone('skipped')}
      onOk={handleSave}
      confirmLoading={saving}
      okText={t('modal.save')}
      cancelText={t('modal.profileSetupSkip')}
      maskClosable={false}
      destroyOnHidden
    >
      <Alert
        message={t('modal.profileSetupDesc')}
        type="info"
        showIcon
        style={{ marginTop: 8 }}
      />
      <Form layout="vertical" style={{ marginTop: 16 }}>
        <Form.Item label={t('modal.avatar')}>
          <UploadAvatar value={avatar} onChange={setAvatar} size={72} />
        </Form.Item>
        <Form.Item label={t('modal.nickname')}>
          <Input
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            maxLength={30}
            prefix={<UserOutlined />}
            placeholder={t('modal.nicknamePlaceholder')}
          />
        </Form.Item>
      </Form>
      <div style={{ color: 'rgba(0, 0, 0, 0.45)', fontSize: 12 }}>
        {t('modal.profileSetupHint')}
      </div>
    </Modal>
  )
}

export default ProfileSetupModal
