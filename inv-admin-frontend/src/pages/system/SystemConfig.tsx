import { useState, useEffect } from 'react'
import { Card, Form, Input, Button, List, Modal, Space, Typography, App, Popconfirm, Empty } from 'antd'
import { PlusOutlined, EditOutlined, DeleteOutlined, SaveOutlined, BookOutlined } from '@ant-design/icons'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/services/api'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

const { Title, Text } = Typography
const { TextArea } = Input

interface FaqItem {
  q: string
  a: string
}

interface HelpCenterConfig {
  docs: {
    device: string
    app: string
    system: string
  }
  phone: string
  faqs: FaqItem[]
}

const SystemConfigPage: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [form] = Form.useForm()
  const [faqForm] = Form.useForm()
  const [faqModalOpen, setFaqModalOpen] = useState(false)
  const [editingFaqIndex, setEditingFaqIndex] = useState<number | null>(null)
  const [faqs, setFaqs] = useState<FaqItem[]>([])

  // 获取配置（后端返回所有配置的map，需提取help_center字段）
  const { data: config, isLoading, error, refetch } = useQuery({
    queryKey: ['system-config', 'help-center'],
    queryFn: () => api.get('/admin/system-config').then((res) => {
      const allConfigs = res.data?.data as Record<string, unknown>
      return (allConfigs?.help_center || {}) as HelpCenterConfig
    }),
  })

  // 保存配置（后端期望map格式：{ help_center: {...} }）
  const saveMutation = useMutation({
    mutationFn: (data: HelpCenterConfig) => api.patch('/admin/system-config', { help_center: data }),
    onSuccess: () => {
      message.success(t('system.saveSuccess'))
      queryClient.invalidateQueries({ queryKey: ['system-config'] })
    },
    onError: () => {
      message.error(t('system.saveFailed'))
    },
  })

  // 初始化表单
  useEffect(() => {
    if (config) {
      form.setFieldsValue({
        phone: config.phone,
        deviceDoc: config.docs?.device || '',
        appDoc: config.docs?.app || '',
        systemDoc: config.docs?.system || '',
      })
      setFaqs(config.faqs || [])
    }
  }, [config, form])

  // 保存所有配置
  const handleSave = async () => {
    try {
      const values = await form.validateFields()
      const data: HelpCenterConfig = {
        docs: {
          device: values.deviceDoc,
          app: values.appDoc,
          system: values.systemDoc,
        },
        phone: values.phone,
        faqs: faqs,
      }
      saveMutation.mutate(data)
    } catch {
      // validation failed
    }
  }

  // 添加/编辑 FAQ
  const handleFaqOk = async () => {
    try {
      const values = await faqForm.validateFields()
      const newFaq: FaqItem = { q: values.question, a: values.answer }
      
      if (editingFaqIndex !== null) {
        const newFaqs = [...faqs]
        newFaqs[editingFaqIndex] = newFaq
        setFaqs(newFaqs)
      } else {
        setFaqs([...faqs, newFaq])
      }
      
      setFaqModalOpen(false)
      setEditingFaqIndex(null)
      faqForm.resetFields()
    } catch {
      // validation failed
    }
  }

  // 删除 FAQ
  const handleDeleteFaq = (index: number) => {
    setFaqs(faqs.filter((_, i) => i !== index))
  }

  // 编辑 FAQ
  const handleEditFaq = (index: number) => {
    setEditingFaqIndex(index)
    faqForm.setFieldsValue({
      question: faqs[index].q,
      answer: faqs[index].a,
    })
    setFaqModalOpen(true)
  }

  // 添加 FAQ
  const handleAddFaq = () => {
    setEditingFaqIndex(null)
    faqForm.resetFields()
    setFaqModalOpen(true)
  }

  if (error) {
    return (
      <div>
        <Title level={4} style={{ marginBottom: 16 }}>
          <BookOutlined style={{ marginRight: 8 }} />
          {t('system.systemConfig')}
        </Title>
        <QueryErrorAlert error={error} onRetry={() => refetch()} />
      </div>
    )
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <Title level={4} style={{ margin: 0 }}>
          <BookOutlined style={{ marginRight: 8 }} />
          {t('system.systemConfig')}
        </Title>
        <Button type="primary" icon={<SaveOutlined />} onClick={handleSave} loading={saveMutation.isPending}>
          {t('common.save')}
        </Button>
      </div>

      <Card title={t('system.helpCenterConfig')} bordered={false} style={{ marginBottom: 16 }}>
        <Form form={form} layout="vertical">
          <Form.Item name="phone" label={t('system.phone')} rules={[{ required: true }]}>
            <Input placeholder={t('system.phonePlaceholder')} />
          </Form.Item>

          <Title level={5} style={{ marginBottom: 16 }}>{t('system.docs')}</Title>
          
          <Form.Item name="deviceDoc" label={t('system.deviceDoc')}>
            <Input placeholder={t('system.deviceDocPlaceholder')} />
          </Form.Item>

          <Form.Item name="appDoc" label={t('system.appDoc')}>
            <Input placeholder={t('system.appDocPlaceholder')} />
          </Form.Item>

          <Form.Item name="systemDoc" label={t('system.systemDoc')}>
            <Input placeholder={t('system.systemDocPlaceholder')} />
          </Form.Item>
        </Form>
      </Card>

      <Card
        title={t('system.faqs')}
        bordered={false}
        extra={
          <Button type="primary" icon={<PlusOutlined />} onClick={handleAddFaq}>
            {t('system.addFaq')}
          </Button>
        }
      >
        {faqs.length > 0 ? (
          <List
            dataSource={faqs}
            renderItem={(item, index) => (
              <List.Item
                actions={[
                  <Button key="edit" type="link" icon={<EditOutlined />} onClick={() => handleEditFaq(index)}>
                    {t('common.edit')}
                  </Button>,
                  <Popconfirm
                    key="delete"
                    title={t('system.faqDeleteConfirm')}
                    onConfirm={() => handleDeleteFaq(index)}
                    okText={t('common.confirm')}
                    cancelText={t('common.cancel')}
                  >
                    <Button type="link" danger icon={<DeleteOutlined />}>
                      {t('common.delete')}
                    </Button>
                  </Popconfirm>,
                ]}
              >
                <List.Item.Meta
                  title={<Text strong>{item.q}</Text>}
                  description={<Text type="secondary">{item.a}</Text>}
                />
              </List.Item>
            )}
          />
        ) : (
          <Empty description={t('system.noData')} />
        )}
      </Card>

      <Modal
        title={editingFaqIndex !== null ? t('system.editFaq') : t('system.addFaq')}
        open={faqModalOpen}
        onOk={handleFaqOk}
        onCancel={() => {
          setFaqModalOpen(false)
          setEditingFaqIndex(null)
          faqForm.resetFields()
        }}
        destroyOnClose
      >
        <Form form={faqForm} layout="vertical">
          <Form.Item name="question" label={t('system.faqQuestion')} rules={[{ required: true }]}>
            <Input placeholder={t('system.faqQuestionPlaceholder')} />
          </Form.Item>
          <Form.Item name="answer" label={t('system.faqAnswer')} rules={[{ required: true }]}>
            <TextArea rows={4} placeholder={t('system.faqAnswerPlaceholder')} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default SystemConfigPage
