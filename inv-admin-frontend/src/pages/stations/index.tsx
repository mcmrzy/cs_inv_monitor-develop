import { useEffect, useState, useCallback } from 'react'
import { Table, Card, Typography, Tag, Select, Modal, message, Space, Popconfirm } from 'antd'
import { ReloadOutlined, SwapOutlined } from '@ant-design/icons'
import api from '@/services/api'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'

const { Title } = Typography

const StationsPage: React.FC = () => {
  const { user, hasPermission } = useAuthStore()
  const [loading, setLoading] = useState(true)
  const [stations, setStations] = useState<any[]>([])
  const [users, setUsers] = useState<any[]>([])
  const [assignVisible, setAssignVisible] = useState(false)
  const [currentStation, setCurrentStation] = useState<any>(null)
  const [targetUserId, setTargetUserId] = useState<number | null>(null)

  const isAdmin = user && (user.role === Role.SUPER_ADMIN || user.role === Role.AGENT)

  const fetchData = useCallback(async () => {
    try {
      setLoading(true)
      const stationRes = await api.get('/stations')
      const stationData = stationRes.data?.data ?? stationRes.data ?? []
      setStations(Array.isArray(stationData) ? stationData : (stationData?.items ?? []))
      
      // 只有管理员才获取用户列表
      if (isAdmin && hasPermission('users:view')) {
        try {
          const userRes = await api.get('/users', { params: { pageSize: 9999 } })
          const userData = userRes.data?.data ?? userRes.data ?? []
          setUsers(Array.isArray(userData) ? userData : (userData?.items ?? []))
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    setLoading(false)
  }, [isAdmin, hasPermission])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const handleAssign = async () => {
    if (!currentStation || targetUserId == null) return
    try {
      await api.put(`/stations/${currentStation.id}/assign`, { user_id: targetUserId })
      message.success('分配成功')
      setAssignVisible(false)
      fetchData()
    } catch {
      message.error('分配失败')
    }
  }

  const columns: any[] = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: '电站名称', dataIndex: 'name', width: 180 },
    {
      title: '位置',
      key: 'location',
      width: 200,
      render: (_: any, r: any) => [r.province, r.city, r.district].filter(Boolean).join(' ') || '-',
    },
    { title: '容量(kW)', dataIndex: 'capacity', width: 90 },
    { title: '面板数', dataIndex: 'panel_count', width: 70 },
    {
      title: '状态',
      dataIndex: 'status',
      width: 70,
      render: (v: number) => <Tag color={v === 1 ? 'green' : 'red'}>{v === 1 ? '正常' : '停用'}</Tag>,
    },
    // 只有管理员才显示归属用户ID和操作列
    ...(isAdmin ? [
      {
        title: '归属用户ID',
        dataIndex: 'user_id',
        width: 100,
        render: (uid: number) => {
          const u = users.find((x: any) => x.id === uid)
          return u ? `${u.nickname || u.phone} (${uid})` : String(uid)
        },
      },
      ...(hasPermission('stations:edit') ? [{
        title: '操作',
        key: 'action',
        width: 100,
        render: (_: any, record: any) => (
          <Popconfirm
            title="分配电站给其他用户"
            description={
              <Select
                showSearch
                style={{ width: 250 }}
                placeholder="选择用户"
                optionFilterProp="label"
                onChange={(val) => setTargetUserId(val)}
                options={users.map((u: any) => ({
                  value: u.id,
                  label: `${u.nickname || u.phone} (ID:${u.id}) [角色:${u.role}]`,
                }))}
              />
            }
            onConfirm={() => {
              if (!currentStation) { setCurrentStation(record) }
              handleAssign()
            }}
            onCancel={() => setCurrentStation(null)}
            onOpenChange={(open) => { if (open) setCurrentStation(record) }}
          >
            <a><SwapOutlined /> 分配用户</a>
          </Popconfirm>
        ),
      }] : []),
    ] : []),
  ]

  return (
    <div style={{ padding: '0 0 24px' }}>
      <Space style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Title level={4} style={{ margin: 0 }}>⚡ 电站管理</Title>
        {isAdmin && <Tag icon={<ReloadOutlined spin={loading} />} color="processing">管理所有电站</Tag>}
      </Space>

      <Card>
        <Table
          columns={columns}
          dataSource={stations}
          rowKey="id"
          loading={loading}
          size="middle"
          pagination={{ pageSize: 20, showSizeChanger: false }}
        />
      </Card>
    </div>
  )
}

export default StationsPage
