-- 086: 为stations表添加卡片图片字段
-- 支持用户自定义电站卡片展示图片

ALTER TABLE stations ADD COLUMN IF NOT EXISTS card_image_url VARCHAR(500);

-- 添加注释
COMMENT ON COLUMN stations.card_image_url IS '电站卡片展示图片URL，用户上传的自定义图片';

-- 创建索引（可选，如果需要按图片查询）
-- CREATE INDEX IF NOT EXISTS idx_stations_card_image_url ON stations(card_image_url) WHERE card_image_url IS NOT NULL;
