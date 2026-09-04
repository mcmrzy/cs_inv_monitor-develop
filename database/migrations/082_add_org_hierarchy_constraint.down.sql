-- Rollback Migration 082: Remove organization hierarchy constraint

DROP TRIGGER IF EXISTS trg_org_hierarchy ON organizations;
DROP FUNCTION IF EXISTS validate_org_hierarchy();
