-- 103 down: 回滚品牌字样（仅作用于未被管理员二次定制的主题）
UPDATE email_templates
SET subject = REPLACE(subject, '【CSERGY】', '【CS-INV】'),
    updated_at = NOW()
WHERE subject LIKE '%【CSERGY】%';
