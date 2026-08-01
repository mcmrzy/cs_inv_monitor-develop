-- Migration 083: Simplify role codes to match organization types
-- New role system: org_admin, agent, distributor, installer, customer
-- (5 levels matching the 5-tier org hierarchy)

-- Step 1: Drop old CHECK constraint first (new role codes won't match old constraint)
ALTER TABLE membership_role_assignments DROP CONSTRAINT IF EXISTS membership_role_assignments_role_code_check;

-- Step 2: Migrate existing role assignments to new role codes
UPDATE membership_role_assignments SET role_code = 'agent' WHERE role_code = 'channel_manager';
UPDATE membership_role_assignments SET role_code = 'agent' WHERE role_code = 'operator';
UPDATE membership_role_assignments SET role_code = 'customer' WHERE role_code = 'after_sales';
UPDATE membership_role_assignments SET role_code = 'customer' WHERE role_code = 'viewer';
UPDATE membership_role_assignments SET role_code = 'customer' WHERE role_code = 'finance';
UPDATE membership_role_assignments SET role_code = 'customer' WHERE role_code = 'api_client';

-- Step 3: Add new CHECK constraint
ALTER TABLE membership_role_assignments ADD CONSTRAINT membership_role_assignments_role_code_check
    CHECK (role_code IN ('org_admin', 'agent', 'distributor', 'installer', 'customer'));
