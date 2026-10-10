-- Restore the pre-128 visibility policy; raw measurements remain untouched.
UPDATE device_model_fields
SET is_supported = FALSE, is_visible = FALSE,
    show_realtime = FALSE, show_history = FALSE, updated_at = NOW()
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN ('pv1_power','pv2_power','pv1_current','pv2_current',
                    'mos_temperature','alarm_code','runtime_hours');
