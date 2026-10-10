-- V3 supplies individual PV power/current. The API also repairs retained V3
-- samples and the warning/runtime aliases. Restore only these proven fields;
-- unsupported limits, efficiency and THD remain hidden. No telemetry rewrite.
UPDATE device_model_fields
SET is_supported = TRUE, is_visible = TRUE,
    show_realtime = TRUE, show_history = TRUE, updated_at = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN ('pv1_power','pv2_power','pv1_current','pv2_current',
                    'mos_temperature','alarm_code','runtime_hours')
  AND (is_supported IS DISTINCT FROM TRUE OR is_visible IS DISTINCT FROM TRUE
       OR show_realtime IS DISTINCT FROM TRUE OR show_history IS DISTINCT FROM TRUE);
