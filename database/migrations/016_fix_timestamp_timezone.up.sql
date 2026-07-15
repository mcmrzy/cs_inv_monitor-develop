-- 016: Normalize legacy TIMESTAMP WITHOUT TIME ZONE columns to TIMESTAMPTZ.
-- Values written by the legacy services were UTC, hence the explicit UTC
-- interpretation during conversion.
--
-- Canonical baselines already define these columns as TIMESTAMPTZ. PostgreSQL
-- still validates dependencies for a redundant ALTER TYPE, so every conversion
-- below is guarded by the current pg_type. This is important for baselines that
-- already contain v_device_latest and v_user_device_access.

-- Save only the known views whose _RETURN rules actually depend on a column
-- that will be converted. pg_get_viewdef keeps the installed definition (old
-- upgrade path or current canonical path) instead of replacing it with a stale
-- hard-coded definition.
CREATE TEMP TABLE IF NOT EXISTS migration016_saved_views (
    qualified_name TEXT PRIMARY KEY,
    view_definition TEXT NOT NULL,
    view_comment TEXT
) ON COMMIT DROP;
TRUNCATE migration016_saved_views;

DO $$
DECLARE
    dependent_view RECORD;
BEGIN
    FOR dependent_view IN
        WITH targets(table_name, column_name) AS (
            VALUES
                ('users', 'last_login_at'), ('users', 'created_at'),
                ('users', 'updated_at'), ('users', 'deleted_at'),
                ('verification_codes', 'expires_at'), ('verification_codes', 'created_at'),
                ('stations', 'created_at'), ('stations', 'updated_at'), ('stations', 'deleted_at'),
                ('devices', 'last_online_at'), ('devices', 'created_at'),
                ('devices', 'updated_at'), ('devices', 'deleted_at'),
                ('alarms', 'occurred_at'), ('alarms', 'recovered_at'),
                ('alarms', 'handled_at'), ('alarms', 'created_at'),
                ('notifications', 'created_at'), ('firmware_versions', 'created_at'),
                ('system_configs', 'updated_at'),
                ('device_telemetry', 'time'), ('device_telemetry', 'created_at'),
                ('device_models', 'created_at'), ('device_models', 'updated_at'),
                ('device_alarms', 'created_at'), ('device_cmd_logs', 'sent_at'),
                ('device_day_data', 'created_at'), ('station_day_data', 'created_at')
        ), conversions AS (
            SELECT relation.oid AS table_oid, attribute.attnum
            FROM targets target
            JOIN pg_class relation ON relation.oid = to_regclass(target.table_name)
            JOIN pg_attribute attribute
              ON attribute.attrelid = relation.oid
             AND attribute.attname = target.column_name
             AND NOT attribute.attisdropped
            WHERE attribute.atttypid = 'timestamp without time zone'::regtype
        )
        SELECT view_relation.oid,
               format('%I.%I', view_namespace.nspname, view_relation.relname) AS qualified_name,
               pg_get_viewdef(view_relation.oid, true) AS view_definition,
               obj_description(view_relation.oid, 'pg_class') AS view_comment
        FROM pg_class view_relation
        JOIN pg_namespace view_namespace ON view_namespace.oid = view_relation.relnamespace
        WHERE view_relation.relkind = 'v'
          AND view_relation.relname IN ('v_device_latest', 'v_user_device_access')
          AND EXISTS (
              SELECT 1
              FROM pg_rewrite rewrite_rule
              JOIN pg_depend dependency
                ON dependency.classid = 'pg_rewrite'::regclass
               AND dependency.objid = rewrite_rule.oid
              JOIN conversions conversion
                ON conversion.table_oid = dependency.refobjid
               AND conversion.attnum = dependency.refobjsubid
              WHERE rewrite_rule.ev_class = view_relation.oid
          )
    LOOP
        INSERT INTO migration016_saved_views(qualified_name, view_definition, view_comment)
        VALUES (dependent_view.qualified_name, dependent_view.view_definition, dependent_view.view_comment)
        ON CONFLICT (qualified_name) DO UPDATE
        SET view_definition = EXCLUDED.view_definition,
            view_comment = EXCLUDED.view_comment;

        EXECUTE format('DROP VIEW %s', dependent_view.qualified_name);
    END LOOP;
END
$$;

-- Convert only columns that both exist and are still TIMESTAMP WITHOUT TIME
-- ZONE. Missing legacy tables/columns and already-normalized baselines are
-- intentionally safe no-ops.
DO $$
DECLARE
    target RECORD;
    relation_oid REGCLASS;
    current_type OID;
BEGIN
    FOR target IN
        SELECT *
        FROM (VALUES
            ('users', 'last_login_at'), ('users', 'created_at'),
            ('users', 'updated_at'), ('users', 'deleted_at'),
            ('verification_codes', 'expires_at'), ('verification_codes', 'created_at'),
            ('stations', 'created_at'), ('stations', 'updated_at'), ('stations', 'deleted_at'),
            ('devices', 'last_online_at'), ('devices', 'created_at'),
            ('devices', 'updated_at'), ('devices', 'deleted_at'),
            ('alarms', 'occurred_at'), ('alarms', 'recovered_at'),
            ('alarms', 'handled_at'), ('alarms', 'created_at'),
            ('notifications', 'created_at'), ('firmware_versions', 'created_at'),
            ('system_configs', 'updated_at'),
            ('device_telemetry', 'time'), ('device_telemetry', 'created_at'),
            ('device_models', 'created_at'), ('device_models', 'updated_at'),
            ('device_alarms', 'created_at'), ('device_cmd_logs', 'sent_at'),
            ('device_day_data', 'created_at'), ('station_day_data', 'created_at')
        ) AS columns_to_convert(table_name, column_name)
    LOOP
        relation_oid := to_regclass(target.table_name);
        IF relation_oid IS NULL THEN
            CONTINUE;
        END IF;

        SELECT attribute.atttypid
          INTO current_type
          FROM pg_attribute attribute
         WHERE attribute.attrelid = relation_oid
           AND attribute.attname = target.column_name
           AND NOT attribute.attisdropped;

        IF current_type = 'timestamp without time zone'::regtype THEN
            EXECUTE format(
                'ALTER TABLE %s ALTER COLUMN %I TYPE TIMESTAMPTZ USING %I AT TIME ZONE ''UTC''',
                relation_oid, target.column_name, target.column_name
            );
        END IF;
    END LOOP;
END
$$;

-- Restore the exact view definitions saved above after their source column
-- types have changed.
DO $$
DECLARE
    saved_view RECORD;
BEGIN
    FOR saved_view IN
        SELECT qualified_name, view_definition, view_comment
        FROM migration016_saved_views
        ORDER BY qualified_name
    LOOP
        EXECUTE format('CREATE VIEW %s AS %s', saved_view.qualified_name, saved_view.view_definition);
        IF saved_view.view_comment IS NOT NULL THEN
            EXECUTE format('COMMENT ON VIEW %s IS %L', saved_view.qualified_name, saved_view.view_comment);
        END IF;
    END LOOP;
END
$$;

-- Keep the trigger helper timezone-neutral: NOW() is a TIMESTAMPTZ value and
-- PostgreSQL performs the appropriate assignment for every normalized column.
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF to_regclass('device_telemetry') IS NOT NULL THEN
        EXECUTE format(
            'COMMENT ON TABLE %s IS %L',
            to_regclass('device_telemetry'),
            '设备遥测数据表 - 时间字段已修复为TIMESTAMPTZ，统一存储UTC时间'
        );
    END IF;
END
$$;
