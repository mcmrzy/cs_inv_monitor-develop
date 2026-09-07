-- Rollback Migration 081: Remove 'installer' organization type

-- Drop the new constraint
ALTER TABLE organizations DROP CONSTRAINT IF EXISTS organizations_org_type_check;

-- Restore original constraint without installer
ALTER TABLE organizations ADD CONSTRAINT organizations_org_type_check
    CHECK (org_type IN ('manufacturer', 'agent', 'distributor', 'customer', 'service_partner'));
