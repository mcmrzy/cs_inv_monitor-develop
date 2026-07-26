import { useState } from 'react'
import { Tabs, Typography } from 'antd'
import { ProCard } from '@ant-design/pro-components'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import OrganizationTree from './OrganizationTree'
import MemberList from './MemberList'
import InvitationManager from './InvitationManager'
import TransferApprovals from './TransferApprovals'

const { Title } = Typography

const ChannelManagement: React.FC = () => {
  const { t } = useTranslation()
  const { user } = useAuthStore()
  const [selectedOrgId, setSelectedOrgId] = useState<number | null>(null)

  if (!user?.isSystemAdmin) {
    return (
      <ProCard style={{ borderRadius: 12 }}>
        <div style={{ textAlign: 'center', padding: 40, color: '#999' }}>
          {t('channel.noPermission')}
        </div>
      </ProCard>
    )
  }

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
          {
            key: 'members',
            label: t('channel.members'),
            children: <MemberList selectedOrgId={selectedOrgId} />,
          },
          {
            key: 'invitations',
            label: t('channel.invitations'),
            children: <InvitationManager selectedOrgId={selectedOrgId} />,
          },
          {
            key: 'transfers',
            label: t('channel.transfers'),
            children: <TransferApprovals />,
          },
        ]}
      />
    </ProCard>
  )
}

export default ChannelManagement
