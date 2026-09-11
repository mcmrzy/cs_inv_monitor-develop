-- 回滚：移除 app_versions 的 APK 元数据列。
-- 注意：回滚会丢失已解析的包名/SDK 版本与文件摘要，仅用于迁移验证。
ALTER TABLE app_versions
    DROP COLUMN IF EXISTS file_sha256,
    DROP COLUMN IF EXISTS package_name,
    DROP COLUMN IF EXISTS file_name,
    DROP COLUMN IF EXISTS min_sdk,
    DROP COLUMN IF EXISTS target_sdk;
