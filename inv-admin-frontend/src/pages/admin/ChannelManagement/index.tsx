import { useState } from 'react'
import { Tabs, Card, Typography } from 'antd'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import { Role } from '@/types'
import OrganizationTree from './OrganizationTree'
import MemberList from './MemberList'
import InvitationManager from './InvitationManager'
import TransferApprovals from './TransferApprovals'

const { Title } = Typography

const ChannelManagement: React.FC = () => {
  const { t } = useTranslation()
  const { user } = useAuthStore()
  const [selectedOrgId, setSelectedOrgId] = useState<number | null>(null)

  if (user?.role !== Role.SUPER_ADMIN) {
    return (
      <Card bordered={false} style={{ borderRadius: 12 }}>
        <div style={{ textAlign: 'center', padding: 40, color: '#999' }}>
          {t('channel.noPermission')}
        </div>
      </Card>
    )
  }

  return (
    <Card bordered={false} style={{ borderRadius: 12 }}>
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
    </Card>
  )
}

export default ChannelManagement
