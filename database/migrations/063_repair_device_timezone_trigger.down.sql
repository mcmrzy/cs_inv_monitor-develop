CREATE OR REPLACE FUNCTION sync_device_timezone()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.station_id IS NOT NULL AND (OLD.station_id IS NULL OR OLD.station_id != NEW.station_id) THEN
        SELECT COALESCE(s.timezone, 'Asia/Shanghai')
        INTO NEW.timezone
        FROM stations s
        WHERE s.id = NEW.station_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
