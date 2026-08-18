import { useState, useEffect, useMemo } from 'react'
import {
  Card,
  Form,
  Input,
  Button,
  List,
  Modal,
  Typography,
  App,
  Popconfirm,
  Empty,
  Tabs,
  Table,
  Switch,
  Drawer,
  Tag,
  Alert,
  Space,
} from 'antd'
import {
  PlusOutlined,
  EditOutlined,
  DeleteOutlined,
  SaveOutlined,
  NotificationOutlined,
  MailOutlined,
  SendOutlined,
} from '@ant-design/icons'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { ColumnsType } from 'antd/es/table'
import api from '@/services/api'
import { emailApi } from '@/services/emailApi'
import type { EmailTemplate } from '@/services/emailApi'
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

/** 预览信封：与后端统一品牌信封风格一致（仅用于管理后台预览展示） */
function buildPreviewHtml(subject: string, contentBlock: string): string {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>${subject || ''}</title></head>
<body style="margin:0;padding:0;background-color:#F0F4FA;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F0F4FA;">
<tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;font-family:'PingFang SC','Microsoft YaHei',-apple-system,'Segoe UI',Roboto,Arial,sans-serif;">
<tr><td style="background-color:#1677ff;background-image:linear-gradient(135deg,#1677ff 0%,#00D4FF 100%);border-radius:16px 16px 0 0;padding:22px 28px;">
  <span style="color:#ffffff;font-size:20px;font-weight:700;">&#9728;&#65039; CS-INV</span>
  <span style="color:#E6F7FF;font-size:12px;float:right;">预览仅供示意 / Preview only</span>
</td></tr>
<tr><td style="background-color:#ffffff;padding:28px;">
  ${contentBlock || ''}
</td></tr>
<tr><td style="background-color:#ffffff;border-radius:0 0 16px 16px;padding:16px 28px;border-top:1px solid #EEF1F6;">
  <span style="font-size:12px;color:#B0B8C4;">© CS-INV · 光伏逆变器监控平台（此邮件由系统自动发出，请勿直接回复）</span>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`
}

/** 帮助文档配置面板（原有能力） */
const HelpDocsPanel: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [form] = Form.useForm()
  const [faqForm] = Form.useForm()
  const [faqModalOpen, setFaqModalOpen] = useState(false)
  const [editingFaqIndex, setEditingFaqIndex] = useState<number | null>(null)
  const [faqs, setFaqs] = useState<FaqItem[]>([])

  // 获取配置（后端返回所有配置的map，需提取help_center字段）
  const { data: config, error, refetch } = useQuery({
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

  if (error) {
    return <QueryErrorAlert error={error} onRetry={() => refetch()} />
  }

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

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 16 }}>
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

/** 邮件模板配置面板：模板列表 + 编辑（实时预览）+ 测试邮件 */
const EmailTemplatesPanel: React.FC = () => {
  const { message } = App.useApp()
  const { t } = useTranslation()
  const queryClient = useQueryClient()

  const [drawerOpen, setDrawerOpen] = useState(false)
  const [editing, setEditing] = useState<EmailTemplate | null>(null)
  const [editSubject, setEditSubject] = useState('')
  const [editBody, setEditBody] = useState('')
  const [testRecipient, setTestRecipient] = useState('')

  const { data: templates, isLoading, error, refetch } = useQuery({
    queryKey: ['email-templates'],
    queryFn: () => emailApi.listTemplates().then((res) => (res.data?.data ?? []) as EmailTemplate[]),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['email-templates'] })

  // 保存模板编辑
  const saveMutation = useMutation({
    mutationFn: (payload: { key: string; subject: string; html_body: string; enabled: boolean }) =>
      emailApi.updateTemplate(payload.key, {
        subject: payload.subject,
        html_body: payload.html_body,
        enabled: payload.enabled,
      }),
    onSuccess: () => {
      message.success(t('system.emailSaveSuccess'))
      setDrawerOpen(false)
      setEditing(null)
      invalidate()
    },
    onError: (err: Error) => {
      message.error(`${t('system.emailSaveFailed')}: ${err.message}`)
    },
  })

  // 切换启用状态
  const toggleMutation = useMutation({
    mutationFn: (tpl: EmailTemplate) =>
      emailApi.updateTemplate(tpl.template_key, {
        subject: tpl.subject,
        html_body: tpl.html_body,
        enabled: !tpl.enabled,
      }),
    onSuccess: invalidate,
    onError: (err: Error) => {
      message.error(`${t('system.emailSaveFailed')}: ${err.message}`)
    },
  })

  // 发送测试邮件
  const testMutation = useMutation({
    mutationFn: (email: string) => emailApi.sendTestEmail(email),
    onSuccess: () => {
      message.success(t('system.emailTestSuccess'))
    },
    onError: (err: Error) => {
      message.error(`${t('system.emailTestFailed')}: ${err.message}`)
    },
  })

  const openEditor = (tpl: EmailTemplate) => {
    setEditing(tpl)
    setEditSubject(tpl.subject)
    setEditBody(tpl.html_body)
    setDrawerOpen(true)
  }

  const previewHtml = useMemo(() => buildPreviewHtml(editSubject, editBody), [editSubject, editBody])

  const tplName = (key: string) => t(`system.emailTpl.${key}`)

  const columns: ColumnsType<EmailTemplate> = [
    {
      title: t('system.emailTemplateType'),
      dataIndex: 'template_key',
      key: 'template_key',
      width: 240,
      render: (key: string) => (
        <div>
          <Tag color="blue">{tplName(key)}</Tag>
          <div style={{ marginTop: 4 }}>
            <Text type="secondary" style={{ fontSize: 12 }}>{key}</Text>
          </div>
        </div>
      ),
    },
    {
      title: t('system.emailSubject'),
      dataIndex: 'subject',
      key: 'subject',
      ellipsis: true,
    },
    {
      title: t('system.emailEnabled'),
      dataIndex: 'enabled',
      key: 'enabled',
      width: 90,
      render: (_: boolean, record: EmailTemplate) => (
        <Switch
          checked={record.enabled}
          loading={toggleMutation.isPending}
          onChange={() => toggleMutation.mutate(record)}
        />
      ),
    },
    {
      title: t('system.emailUpdatedAt'),
      dataIndex: 'updated_at',
      key: 'updated_at',
      width: 170,
      render: (v: string) => <Text type="secondary">{v}</Text>,
    },
    {
      title: t('system.actions'),
      key: 'actions',
      width: 110,
      render: (_: unknown, record: EmailTemplate) => (
        <Button type="link" icon={<EditOutlined />} onClick={() => openEditor(record)}>
          {t('common.edit')}
        </Button>
      ),
    },
  ]

  if (error) {
    return <QueryErrorAlert error={error} onRetry={() => refetch()} />
  }

  return (
    <div>
      <Card title={t('system.emailTemplateList')} bordered={false} style={{ marginBottom: 16 }}>
        <Table<EmailTemplate>
          rowKey="template_key"
          columns={columns}
          dataSource={templates ?? []}
          loading={isLoading}
          pagination={false}
        />
      </Card>

      <Card title={t('system.emailTestTitle')} bordered={false}>
        <Text type="secondary" style={{ display: 'block', marginBottom: 12 }}>
          {t('system.emailTestHint')}
        </Text>
        <Space.Compact style={{ width: '100%', maxWidth: 520 }}>
          <Input
            value={testRecipient}
            onChange={(e) => setTestRecipient(e.target.value)}
            placeholder={t('system.emailTestRecipientPlaceholder')}
            onPressEnter={() => testRecipient && testMutation.mutate(testRecipient)}
          />
          <Button
            type="primary"
            icon={<SendOutlined />}
            loading={testMutation.isPending}
            disabled={!testRecipient}
            onClick={() => testMutation.mutate(testRecipient)}
          >
            {t('system.emailTestSend')}
          </Button>
        </Space.Compact>
      </Card>

      <Drawer
        title={
          <span>
            <MailOutlined style={{ marginRight: 8 }} />
            {t('system.emailEditTemplate')}
            {editing ? `：${tplName(editing.template_key)}` : ''}
          </span>
        }
        width={820}
        open={drawerOpen}
        onClose={() => {
          setDrawerOpen(false)
          setEditing(null)
        }}
        destroyOnClose
        extra={
          <Button
            type="primary"
            icon={<SaveOutlined />}
            loading={saveMutation.isPending}
            disabled={!editing}
            onClick={() =>
              editing &&
              saveMutation.mutate({
                key: editing.template_key,
                subject: editSubject,
                html_body: editBody,
                enabled: editing.enabled,
              })
            }
          >
            {t('common.save')}
          </Button>
        }
      >
        <Form layout="vertical">
          <Form.Item label={t('system.emailSubject')} required>
            <Input value={editSubject} onChange={(e) => setEditSubject(e.target.value)} />
          </Form.Item>
          <Form.Item label={t('system.emailHtmlBody')} required>
            <Alert type="info" showIcon message={t('system.emailVarsHint')} style={{ marginBottom: 8 }} />
            <TextArea
              value={editBody}
              onChange={(e) => setEditBody(e.target.value)}
              autoSize={{ minRows: 12, maxRows: 24 }}
              style={{ fontFamily: 'Consolas, Menlo, monospace', fontSize: 12 }}
            />
          </Form.Item>
          <Form.Item label={t('system.emailPreview')}>
            <iframe
              title="email-template-preview"
              srcDoc={previewHtml}
              sandbox=""
              style={{ width: '100%', height: 420, border: '1px solid #f0f0f0', borderRadius: 8, background: '#F0F4FA' }}
            />
          </Form.Item>
        </Form>
      </Drawer>
    </div>
  )
}

const SystemConfigPage: React.FC = () => {
  const { t } = useTranslation()

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <NotificationOutlined style={{ marginRight: 8 }} />
        {t('system.systemConfig')}
      </Title>

      <Tabs
        defaultActiveKey="helpDocs"
        items={[
          { key: 'helpDocs', label: t('system.tabHelpDocs'), children: <HelpDocsPanel /> },
          { key: 'emailTemplates', label: t('system.tabEmailTemplates'), children: <EmailTemplatesPanel /> },
        ]}
      />
    </div>
  )
}

export default SystemConfigPage
