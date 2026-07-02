ALTER TABLE device_model_field ADD COLUMN IF NOT EXISTS group_name VARCHAR(64) NOT NULL DEFAULT '';
ALTER TABLE device_model_field ADD COLUMN IF NOT EXISTS control_params JSONB;
