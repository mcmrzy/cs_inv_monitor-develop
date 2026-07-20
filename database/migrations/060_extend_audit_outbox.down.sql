-- 060 down: preserve audit rows and block lossy resource_id conversion.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM audit_logs
        WHERE resource_id IS NOT NULL
          AND resource_id !~ '^-?[0-9]+$'
    ) THEN
        RAISE EXCEPTION
            'cannot downgrade audit_logs.resource_id to BIGINT: non-numeric values exist'
            USING ERRCODE = '22018';
    END IF;
END;
$$;
DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
DROP FUNCTION IF EXISTS reject_audit_log_mutation();

DROP TABLE IF EXISTS transactional_outbox;
DROP TABLE IF EXISTS idempotency_responses;

DROP INDEX IF EXISTS idx_audit_logs_request;
DROP INDEX IF EXISTS idx_audit_logs_root_created;
DROP INDEX IF EXISTS idx_audit_logs_active_org_fk;
DROP INDEX IF EXISTS idx_audit_logs_operator_fk;

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_result_check;
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_active_org_requires_root;
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS fk_audit_logs_operator;
ALTER TABLE audit_logs
    DROP COLUMN IF EXISTS root_tenant_id,
    DROP COLUMN IF EXISTS active_organization_id,
    DROP COLUMN IF EXISTS request_id,
    DROP COLUMN IF EXISTS result,
    DROP COLUMN IF EXISTS failure_reason,
    DROP COLUMN IF EXISTS before_data,
    DROP COLUMN IF EXISTS after_data,
    DROP COLUMN IF EXISTS event_schema_version;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'audit_logs'
          AND column_name = 'resource_id'
          AND data_type = 'text'
    ) THEN
        BEGIN
            ALTER TABLE audit_logs
                ALTER COLUMN resource_id TYPE BIGINT USING resource_id::BIGINT;
        EXCEPTION
            WHEN numeric_value_out_of_range THEN
                RAISE EXCEPTION
                    'cannot downgrade audit_logs.resource_id to BIGINT: value out of range'
                    USING ERRCODE = '22003';
        END;
    END IF;
END;
$$;
-- End migration 060 downgrade.
