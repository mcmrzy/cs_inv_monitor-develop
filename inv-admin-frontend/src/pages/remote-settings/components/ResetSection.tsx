import React from 'react'
import { Button, Modal, App, Typography } from 'antd'
import { ExclamationCircleOutlined } from '@ant-design/icons'

const { Text } = Typography

const ResetSection: React.FC = () => {
  const { message } = App.useApp()

  return (
    <div>
      <Text type="secondary" style={{ display: 'block', marginBottom: 12 }}>
        将所有系统设置恢复为出厂默认值，此操作不可撤销。
      </Text>
      <Button
        danger
        size="large"
        onClick={() => {
          Modal.confirm({
            title: '确认恢复默认设置',
            icon: <ExclamationCircleOutlined />,
            content: '确定要将所有系统设置恢复为出厂默认值吗？此操作不可撤销。',
            okText: '确认执行',
            okType: 'danger',
            cancelText: '取消',
            onOk: () => message.success('恢复默认设置命令已发送'),
          })
        }}
      >
        系统设置恢复默认值
      </Button>
    </div>
  )
}

export default ResetSection
