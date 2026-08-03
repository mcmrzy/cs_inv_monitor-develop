-- 093_add_station_country: 回滚

ALTER TABLE stations DROP COLUMN IF EXISTS country;
