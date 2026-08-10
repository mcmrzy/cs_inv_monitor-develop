-- 回滚：删除 app_versions 表及其序列（注意：会级联删除序列）
DROP TABLE IF EXISTS app_versions;
