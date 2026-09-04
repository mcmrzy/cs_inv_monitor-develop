-- 109: 修复邮件模板按钮居中 + 信封页脚更新
-- 为所有邮件模板的按钮 td 添加 text-align:center CSS 属性，确保在所有邮件客户端中居中显示。

UPDATE email_templates
SET html_body = REPLACE(html_body,
    '<td align="center" style="background-color:#1677ff;',
    '<td align="center" style="text-align:center;background-color:#1677ff;'),
    updated_at = NOW()
WHERE html_body LIKE '%<td align="center" style="background-color:#1677ff;%'
  AND html_body NOT LIKE '%text-align:center%';
