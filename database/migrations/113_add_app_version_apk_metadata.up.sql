-- Migration 113: app_versions 增加 APK 元数据列
--
-- 背景：管理后台「App版本管理」原先要求管理员手工填写下载链接、文件大小、
-- 版本号等元数据，人工填写与真实安装包不一致时会直接导致客户端收不到更新
-- （version_code 写错）或下载到过期链接。本次改为上传 APK 后由服务端解析
-- AndroidManifest.xml 并计算摘要，所以需要落库保存解析结果。
--
-- 变更：为 app_versions 增加 5 个元数据列，全部带默认值，对存量行与既有
-- INSERT 路径向后兼容（未提供时取默认值）。
-- 幂等：ADD COLUMN IF NOT EXISTS / COMMENT 重放安全。
--
-- 前置：app_versions 由 097_create_app_versions 创建（097 设计为幂等），
--       迁移按编号串行执行，故此处可直接 ALTER。
ALTER TABLE app_versions
    ADD COLUMN IF NOT EXISTS file_sha256  character varying(64)  NOT NULL DEFAULT ''::character varying,
    ADD COLUMN IF NOT EXISTS package_name character varying(255) NOT NULL DEFAULT ''::character varying,
    ADD COLUMN IF NOT EXISTS file_name    character varying(255) NOT NULL DEFAULT ''::character varying,
    ADD COLUMN IF NOT EXISTS min_sdk      integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS target_sdk   integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN app_versions.file_sha256 IS '安装包 SHA-256（服务端计算，供完整性校验与下载页展示）';
COMMENT ON COLUMN app_versions.package_name IS 'APK 包名（服务端从 AndroidManifest.xml 解析）';
COMMENT ON COLUMN app_versions.file_name IS '服务器上的安装包文件名（相对 /firmware/ 目录）';
COMMENT ON COLUMN app_versions.min_sdk IS 'APK minSdkVersion';
COMMENT ON COLUMN app_versions.target_sdk IS 'APK targetSdkVersion';
