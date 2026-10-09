ALTER TABLE device_upgrades
    ADD COLUMN stage_progress INTEGER CHECK (stage_progress BETWEEN 0 AND 100),
    ADD COLUMN overall_progress INTEGER CHECK (overall_progress BETWEEN 0 AND 100);

COMMENT ON COLUMN device_upgrades.stage_progress IS 'Device-reported percent in the current stage; NULL for legacy reports';
COMMENT ON COLUMN device_upgrades.overall_progress IS 'Device-reported overall percent; progress retains the legacy contract';
