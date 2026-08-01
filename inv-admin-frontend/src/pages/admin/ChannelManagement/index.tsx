import { useState } from 'react'
import { Tabs } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import OrganizationTree from './OrganizationTree'
import MemberList from './MemberList'
import TransferApprovals from './TransferApprovals'

const ChannelManagement: React.FC = () => {
  const { t } = useTranslation()
  const { user } = useAuthStore()
  const [selectedOrgId, setSelectedOrgId] = useState<number | null>(null)
  const isSystemAdmin = !!user?.isSystemAdmin

  return (
    <ProCard style={{ borderRadius: 12 }}>
      <Tabs
        defaultActiveKey="organizations"
        items={[
          {
            key: 'organizations',
            label: t('channel.orgTree'),
            children: (
              <OrganizationTree
                selectedOrgId={selectedOrgId}
                onSelectOrg={setSelectedOrgId}
              />
            ),
          },
          // 非系统管理员仅开放组织架构（含邀请）；成员/转移审批为系统管理员能力
          ...(isSystemAdmin
            ? [
                {
                  key: 'members',
                  label: t('channel.members'),
                  children: <MemberList selectedOrgId={selectedOrgId} />,
                },
                {
                  key: 'transfers',
                  label: t('channel.transfers'),
                  children: <TransferApprovals />,
                },
              ]
            : []),
        ]}
      />
    </ProCard>
  )
}

export default ChannelManagement
