-- Prevent an unknown/removed station_id from overwriting the device's
-- NOT NULL timezone with NULL. A scalar subquery keeps COALESCE effective even
-- when no station row exists.
CREATE OR REPLACE FUNCTION sync_device_timezone()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.station_id IS NOT NULL AND (OLD.station_id IS NULL OR OLD.station_id != NEW.station_id) THEN
        NEW.timezone := COALESCE(
            (SELECT s.timezone FROM stations s WHERE s.id = NEW.station_id),
            'Asia/Shanghai'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
