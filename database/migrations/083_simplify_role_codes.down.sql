-- Migration 083 down: Restore old role codes

-- Step 1: Restore CHECK constraint with old values
ALTER TABLE membership_role_assignments DROP CONSTRAINT IF EXISTS membership_role_assignments_role_code_check;

ALTER TABLE membership_role_assignments ADD CONSTRAINT membership_role_assignments_role_code_check
    CHECK (role_code IN ('org_admin', 'channel_manager', 'operator', 'installer', 'after_sales', 'viewer', 'finance', 'api_client'));

-- Note: Cannot reverse the data migration (agent -> channel_manager, etc.)
-- as the original mapping is lost. Manual intervention required.
