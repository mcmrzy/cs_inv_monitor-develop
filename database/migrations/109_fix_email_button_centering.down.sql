-- 109 rollback: 移除按钮 td 上的 text-align:center（恢复原状）

UPDATE email_templates
SET html_body = REPLACE(html_body,
    '<td align="center" style="text-align:center;background-color:#1677ff;',
    '<td align="center" style="background-color:#1677ff;'),
    updated_at = NOW()
WHERE html_body LIKE '%text-align:center;background-color:#1677ff;%';
