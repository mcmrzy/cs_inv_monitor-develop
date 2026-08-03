-- 093_add_station_country: 电站表添加国家字段
-- 创建/编辑电站时支持选择国家（与用户表 country 语义一致，存中文国家名）

ALTER TABLE stations ADD COLUMN IF NOT EXISTS country VARCHAR(100);

COMMENT ON COLUMN stations.country IS '电站所在国家（中文名，如 中国）';
