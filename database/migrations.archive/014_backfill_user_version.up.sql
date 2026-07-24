-- =====================================================
-- 回填 upgrade_packages 表中的 user_version 和 user_changelog
-- 解决 App 端显示 "unknown" 的问题
-- =====================================================

-- 1. 回填 user_version: 从 main_version (如 V1.0.0.20260703) 提取简化版本 (如 V1.0.0)
UPDATE upgrade_packages
SET user_version = REGEXP_REPLACE(main_version, '\.\d{8}$', '')
WHERE user_version = ''
  AND main_version ~ '^V\d+\.\d+\.\d+\.\d{8}$';

-- 2. 对于不符合上述格式的，直接使用 main_version
UPDATE upgrade_packages
SET user_version = main_version
WHERE user_version = ''
  AND main_version != '';

-- 3. 回填 user_changelog: 使用内部 changelog
UPDATE upgrade_packages
SET user_changelog = changelog
WHERE user_changelog = ''
  AND changelog != ''
  AND changelog IS NOT NULL;

-- 4. 兜底：如果仍然为空，设置默认值
UPDATE upgrade_packages
SET user_changelog = '固件升级优化'
WHERE user_changelog = ''
   OR user_changelog IS NULL;
