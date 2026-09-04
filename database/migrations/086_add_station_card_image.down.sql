-- 086: 回滚 - 删除stations表的卡片图片字段

ALTER TABLE stations DROP COLUMN IF EXISTS card_image_url;
