-- 103: 邮件品牌字样统一为 CSERGY
-- 针对 102 已执行过、email_templates 表中 seed 了「【CS-INV】」主题前缀的库做幂等修正；
-- 未执行过 102 的库不受影响（102 的 seed 已直接使用 CSERGY）。
UPDATE email_templates
SET subject = REPLACE(subject, '【CS-INV】', '【CSERGY】'),
    updated_at = NOW()
WHERE subject LIKE '%【CS-INV】%';
