import React from 'react'
import { Card, Button, Modal, App, Space, Typography } from 'antd'
import { ReloadOutlined, ExclamationCircleOutlined } from '@ant-design/icons'

const cardStyle = { borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }

const ResetSection: React.FC = () => {
  const { message } = App.useApp()

  return (
    <Card
      bordered={false}
      style={cardStyle}
      title={
        <Space>
          <ReloadOutlined />
          <span style={{ fontSize: 16, fontWeight: 'bold' }}>重置操作</span>
        </Space>
      }
    >
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
    </Card>
  )
}

export default ResetSection
