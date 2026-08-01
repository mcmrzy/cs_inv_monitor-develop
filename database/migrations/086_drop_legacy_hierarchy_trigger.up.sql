-- Migration 086: Drop legacy hierarchy trigger and fix member channel roles
--
-- Root cause of "create organization failed: illegal organization hierarchy:
-- distributor cannot be parent of installer (SQLSTATE 23514)":
-- the organizations table carried TWO BEFORE triggers:
--   1. trg_org_hierarchy                -> validate_org_hierarchy()          (migration 084 rules, allows installer under distributor)
--   2. trg_organizations_validate_hierarchy -> validate_organization_hierarchy() (legacy 073 rules, has NO installer rule and no
--        manufacturer/installer/customer chain, so it rejects installer creation)
-- Both ran on INSERT, and the legacy trigger rejected valid hierarchy moves.
--
-- This migration removes the legacy trigger and function. The governed move
-- workflow no longer exists (governed_move_org was removed in 083/084), so
-- nothing else references validate_organization_hierarchy.

-- 1. Drop the legacy trigger and function
DROP TRIGGER IF EXISTS trg_organizations_validate_hierarchy ON organizations;
DROP FUNCTION IF EXISTS validate_organization_hierarchy();

-- 2. Fix member channel roles that violate the org-type capacity rules.
-- Org capacity = {own org_type} U {invitable roles}:
--   manufacturer: {manufacturer, agent, distributor, installer, customer}
--   agent:        {agent, installer, customer}
--   distributor:  {distributor, installer, customer}
--   installer:    {installer, customer}
--   customer:     {customer}
-- org_admin and non-channel roles are untouched.
--
-- Step 2a: drop role rows that must be corrected but collide with an existing
-- active row carrying the target role for the same membership
-- (uq_role_assignments_active_role: membership_id + role_code unique when active).
DELETE FROM membership_role_assignments mra
USING organization_memberships m
JOIN organizations o ON o.id = m.organization_id
WHERE mra.membership_id = m.id
  AND mra.status = 'active'
  AND mra.role_code IN ('agent', 'distributor', 'installer', 'customer')
  AND mra.role_code <> o.org_type
  AND NOT (
      o.org_type = 'manufacturer'
      OR (o.org_type = 'agent' AND mra.role_code IN ('installer', 'customer'))
      OR (o.org_type = 'distributor' AND mra.role_code IN ('installer', 'customer'))
      OR (o.org_type = 'installer' AND mra.role_code = 'customer')
  )
  AND EXISTS (
      SELECT 1 FROM membership_role_assignments x
      WHERE x.membership_id = mra.membership_id
        AND x.status = 'active'
        AND x.role_code = o.org_type
  );

-- Step 2b: rewrite remaining illegal channel roles to the org's own type
UPDATE membership_role_assignments mra
SET role_code = o.org_type, updated_at = NOW()
FROM organization_memberships m
JOIN organizations o ON o.id = m.organization_id
WHERE mra.membership_id = m.id
  AND mra.status = 'active'
  AND mra.role_code IN ('agent', 'distributor', 'installer', 'customer')
  AND mra.role_code <> o.org_type
  AND NOT (
      o.org_type = 'manufacturer'
      OR (o.org_type = 'agent' AND mra.role_code IN ('installer', 'customer'))
      OR (o.org_type = 'distributor' AND mra.role_code IN ('installer', 'customer'))
      OR (o.org_type = 'installer' AND mra.role_code = 'customer')
  );
