-- 024: migrate legacy model metadata and add registry governance/reporting.
-- Older installations may have been created from schema.sql without migration 011.
ALTER TABLE device_model_field
    ADD COLUMN IF NOT EXISTS group_name VARCHAR(50) NOT NULL DEFAULT 'legacy';

CREATE TABLE IF NOT EXISTS model_registry_migration_report (
    model_id BIGINT PRIMARY KEY REFERENCES device_models(id) ON DELETE CASCADE,
    legacy_field_count INTEGER NOT NULL DEFAULT 0,
    legacy_json_field_count INTEGER NOT NULL DEFAULT 0,
    migrated_field_count INTEGER NOT NULL DEFAULT 0,
    legacy_mapping_count INTEGER NOT NULL DEFAULT 0,
    migration_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    migrated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Promote legacy structured fields into the global standard dictionary.
INSERT INTO telemetry_field_catalog(field_key,field_type,base_unit,category,description,is_timeseries,is_aggregatable,allowed_aggregates)
SELECT DISTINCT f.field_key,
       CASE f.field_type WHEN 'int' THEN 'integer' WHEN 'bool' THEN 'boolean' ELSE
            CASE WHEN f.field_type IN ('float','integer','boolean','string','bitmask') THEN f.field_type ELSE 'float' END END,
       NULLIF(f.unit,''),COALESCE(NULLIF(f.group_name,''),'legacy'),f.field_name,
       NOT f.is_control,NOT f.is_control,
       CASE WHEN f.is_control THEN '[]'::jsonb ELSE '["avg","min","max","last"]'::jsonb END
FROM device_model_field f
ON CONFLICT(field_key) DO NOTHING;

INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,sort_order,
    is_supported,is_visible,show_realtime,show_history,allow_compare,allow_alarm_rule,default_chart)
SELECT f.model_id,f.field_key,COALESCE(NULLIF(f.field_name,''),'fields.'||f.field_key),
       COALESCE(NULLIF(f.group_name,''),'legacy'),NULLIF(f.unit,''),f.sort,
       TRUE,f.is_show,f.is_show,NOT f.is_control,FALSE,FALSE,FALSE
FROM device_model_field f
ON CONFLICT(model_id,field_key) DO UPDATE SET
    display_name_key=EXCLUDED.display_name_key,group_code=EXCLUDED.group_code,
    display_unit=EXCLUDED.display_unit,sort_order=EXCLUDED.sort_order,
    is_visible=EXCLUDED.is_visible,show_realtime=EXCLUDED.show_realtime,
    show_history=EXCLUDED.show_history,updated_at=NOW();

-- data_fields may contain keys that were never normalized into device_model_field.
INSERT INTO telemetry_field_catalog(field_key,field_type,category,description,allowed_aggregates)
SELECT DISTINCT key,'float','legacy','Migrated from device_models.data_fields','["avg","min","max","last"]'::jsonb
FROM device_models m CROSS JOIN LATERAL jsonb_object_keys(COALESCE(m.data_fields,'{}'::jsonb)) AS key
ON CONFLICT(field_key) DO NOTHING;

INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,sort_order)
SELECT m.id,key,'fields.'||key,'legacy',10000+ROW_NUMBER() OVER(PARTITION BY m.id ORDER BY key)
FROM device_models m CROSS JOIN LATERAL jsonb_object_keys(COALESCE(m.data_fields,'{}'::jsonb)) AS key
ON CONFLICT(model_id,field_key) DO NOTHING;

INSERT INTO model_registry_migration_report(model_id,legacy_field_count,legacy_json_field_count,
    migrated_field_count,legacy_mapping_count,migration_status,details)
SELECT m.id,
       (SELECT COUNT(*) FROM device_model_field f WHERE f.model_id=m.id),
       (SELECT COUNT(*) FROM jsonb_object_keys(COALESCE(m.data_fields,'{}'::jsonb))),
       (SELECT COUNT(*) FROM device_model_fields f WHERE f.model_id=m.id),
       (SELECT COUNT(*) FROM jsonb_object_keys(COALESCE(m.field_mapping,'{}'::jsonb))),
       CASE WHEN COALESCE(m.field_mapping,'{}'::jsonb)='{}'::jsonb THEN 'migrated' ELSE 'needs_review' END,
       jsonb_build_object('legacy_mqtt_topics',COALESCE(m.mqtt_topics,'[]'::jsonb),
           'mapping_preserved',COALESCE(m.field_mapping,'{}'::jsonb),
           'note','Legacy mapping is preserved for review; released array mappings are never inferred automatically.')
FROM device_models m
ON CONFLICT(model_id) DO UPDATE SET
    legacy_field_count=EXCLUDED.legacy_field_count,legacy_json_field_count=EXCLUDED.legacy_json_field_count,
    migrated_field_count=EXCLUDED.migrated_field_count,legacy_mapping_count=EXCLUDED.legacy_mapping_count,
    migration_status=EXCLUDED.migration_status,details=EXCLUDED.details,migrated_at=NOW();

INSERT INTO role_permissions(role,resource,action,is_allowed) VALUES
(1,'models','dictionary',false),(1,'models','protocol_view',true),(1,'models','protocol_publish',false),
(2,'models','protocol_view',true),(3,'models','protocol_view',true),(4,'models','protocol_view',true)
ON CONFLICT(role,resource,action) DO UPDATE SET is_allowed=EXCLUDED.is_allowed;
