-- 102: 系统邮件模板表（统一品牌化邮件模板管理）
-- email_templates 存放各邮件类型的「主题 + 内容块」，内容块为 Go template 语法，
-- 渲染时由 business-api 套上统一品牌信封（CSERGY，主色 #1677ff，点缀 #00D4FF）。
-- 标准占位变量：{{.Title}} {{.Summary}} {{.Content}} {{.ButtonText}} {{.ButtonURL}} {{.Code}} {{.FooterNote}}

CREATE TABLE IF NOT EXISTS email_templates (
    template_key TEXT PRIMARY KEY,
    subject      TEXT        NOT NULL,
    html_body    TEXT        NOT NULL,
    enabled      BOOLEAN     NOT NULL DEFAULT TRUE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE email_templates IS '系统邮件模板（主题与内容块），渲染时套统一品牌信封';
COMMENT ON COLUMN email_templates.template_key IS '模板类型标识，如 verification_code / invitation_email';
COMMENT ON COLUMN email_templates.subject IS '邮件主题模板（Go template 语法）';
COMMENT ON COLUMN email_templates.html_body IS '邮件内容块 HTML 模板（Go template 语法），信封由后端统一渲染';
COMMENT ON COLUMN email_templates.enabled IS '是否启用；禁用时回退内置默认模板';

-- 默认模板 seed（与 business-api 内置默认模板保持一致；ON CONFLICT DO NOTHING 防止覆盖已定制内容）
INSERT INTO email_templates (template_key, subject, html_body, enabled) VALUES
('verification_code',
 '【CSERGY】{{.Title}}',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
{{if .Code}}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
    <tr>
        <td align="center" style="background-color:#F0F7FF;border:1px solid #BAE0FF;border-radius:12px;padding:24px 16px;">
            <div style="font-size:36px;font-weight:800;letter-spacing:10px;color:#1677ff;font-family:Consolas,'Courier New',monospace;">{{.Code}}</div>
            <div style="margin-top:10px;font-size:13px;color:#8A94A6;">验证码 5 分钟内有效，请勿泄露给他人</div>
        </td>
    </tr>
</table>
{{end}}
{{if .Content}}<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Content}}</p>{{end}}$$,
 TRUE),

('invitation_email',
 '【CSERGY】邀请加入组织 · {{.OrganizationName}}',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:18px 0;background-color:#F7F9FC;border-radius:10px;border-left:4px solid #1677ff;">
    <tr>
        <td style="padding:16px 20px;font-size:14px;line-height:1.8;color:#3E4A5E;">{{.Content}}</td>
    </tr>
</table>
{{if and .ButtonText .ButtonURL}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 10px 0;">
    <tr>
        <td align="center" style="background-color:#1677ff;border-radius:8px;">
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:12px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">{{.ButtonText}}</a>
        </td>
    </tr>
</table>
{{end}}
<p style="margin:0;font-size:13px;line-height:1.6;color:#8A94A6;">如按钮无法点击，请复制以下链接到浏览器打开：<br>{{.ButtonURL}}</p>$$,
 TRUE),

('welcome_email',
 '【CSERGY】欢迎加入平台',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Content}}</p>
{{if and .ButtonText .ButtonURL}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 10px 0;">
    <tr>
        <td align="center" style="background-color:#1677ff;border-radius:8px;">
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:12px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">{{.ButtonText}}</a>
        </td>
    </tr>
</table>
{{end}}$$,
 TRUE),

('password_reset',
 '【CSERGY】重置密码',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Content}}</p>
{{if and .ButtonText .ButtonURL}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 10px 0;">
    <tr>
        <td align="center" style="background-color:#1677ff;border-radius:8px;">
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:12px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">{{.ButtonText}}</a>
        </td>
    </tr>
</table>
{{end}}
<p style="margin:0;font-size:13px;line-height:1.6;color:#8A94A6;">出于安全考虑，重置链接中的令牌仅显示前缀；请勿将重置链接提供给他人。</p>$$,
 TRUE),

('transfer_notification',
 '【CSERGY】设备转移通知',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:18px 0;background-color:#F7F9FC;border-radius:10px;border-left:4px solid #00D4FF;">
    <tr>
        <td style="padding:16px 20px;font-size:14px;line-height:1.8;color:#3E4A5E;">{{.Content}}</td>
    </tr>
</table>
{{if and .ButtonText .ButtonURL}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 10px 0;">
    <tr>
        <td align="center" style="background-color:#1677ff;border-radius:8px;">
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:12px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">{{.ButtonText}}</a>
        </td>
    </tr>
</table>
{{end}}$$,
 TRUE),

('notification_email',
 '【CSERGY】{{.Title}}',
 $${{if .DeviceSN}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 18px 0;">
    <tr>
        <td style="background-color:#F0F7FF;border:1px solid #BAE0FF;border-radius:8px;padding:8px 16px;font-size:14px;font-weight:600;color:#1677ff;letter-spacing:1px;">设备 SN：{{.DeviceSN}}</td>
    </tr>
</table>
{{end}}
<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Content}}</p>
{{if .Summary}}<p style="margin:0;font-size:13px;line-height:1.6;color:#8A94A6;">{{.Summary}}</p>{{end}}
{{if and .ButtonText .ButtonURL}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 10px 0;">
    <tr>
        <td align="center" style="background-color:#1677ff;border-radius:8px;">
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:12px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">{{.ButtonText}}</a>
        </td>
    </tr>
</table>
{{end}}$$,
 TRUE),

('daily_report',
 '【CSERGY】每日发电统计报告',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:18px 0;background-color:#F7F9FC;border-radius:10px;border-left:4px solid #1677ff;">
    <tr>
        <td style="padding:16px 20px;font-size:14px;line-height:1.8;color:#3E4A5E;">{{.Content}}</td>
    </tr>
</table>$$,
 TRUE),

('test_email',
 '【CSERGY】测试邮件 / Test Email',
 $$<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Summary}}</p>
<p style="margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;">{{.Content}}</p>
{{if and .ButtonText .ButtonURL}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 10px 0;">
    <tr>
        <td align="center" style="background-color:#1677ff;border-radius:8px;">
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:12px 36px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">{{.ButtonText}}</a>
        </td>
    </tr>
</table>
{{end}}
<p style="margin:0;font-size:13px;line-height:1.6;color:#8A94A6;">{{.FooterNote}}</p>$$,
 TRUE)
ON CONFLICT (template_key) DO NOTHING;
