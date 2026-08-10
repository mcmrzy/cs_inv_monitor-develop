--
-- 背景：app_versions 表在 schema squash 时从迁移体系与 schema.sql 中丢失（仅残留于
--       pg_dump 备份 backup-schema-before-023-20260713-190544.sql / deploy/inv_full.sql），
--       后端 OTARepository 及管理后台「App版本管理」页面依赖该表，缺失导致
--       GET /api/v1/ota/app/versions 返回 500「查询版本列表失败」。
--       本迁移按备份快照中的原始定义重建（表 + 序列 + 主键 + 索引）。
--
-- 幂等可重放：CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS。
--

CREATE TABLE IF NOT EXISTS app_versions (
    id bigint NOT NULL,
    platform character varying(16) NOT NULL,
    version_code integer NOT NULL,
    version_name character varying(32) NOT NULL,
    download_url text,
    file_size bigint DEFAULT 0,
    file_md5 character varying(64) DEFAULT ''::character varying,
    changelog text DEFAULT ''::text,
    is_force boolean DEFAULT false,
    min_supported_version integer DEFAULT 0,
    status integer DEFAULT 1,
    created_by bigint DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    rollout_percentage integer DEFAULT 100,
    is_rolled_back boolean DEFAULT false,
    rolled_back_at timestamp with time zone
);

-- 序列（与备份快照一致：id 自增，owner 为表本身）
CREATE SEQUENCE IF NOT EXISTS app_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE app_versions_id_seq OWNED BY app_versions.id;

ALTER TABLE ONLY app_versions ALTER COLUMN id SET DEFAULT nextval('app_versions_id_seq'::regclass);

-- 主键（幂等：表已存在且已有主键时跳过，避免容器启动迁移重放时重复建主键报错）
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'app_versions_pkey' AND conrelid = 'app_versions'::regclass) THEN
        ALTER TABLE ONLY app_versions ADD CONSTRAINT app_versions_pkey PRIMARY KEY (id);
    END IF;
END $$;

-- 索引（按平台+状态+时间倒序查询，与 ListAppVersions 查询匹配）
CREATE INDEX IF NOT EXISTS idx_app_versions_platform_status ON app_versions USING btree (platform, status, created_at DESC);
