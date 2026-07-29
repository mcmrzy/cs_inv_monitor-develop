-- Migration 081: Add 'installer' organization type to support full channel hierarchy
-- Hierarchy: manufacturer -> agent -> distributor -> installer -> end_user

-- Drop the existing constraint
ALTER TABLE organizations DROP CONSTRAINT IF EXISTS organizations_org_type_check;

-- Add new constraint with installer type included
ALTER TABLE organizations ADD CONSTRAINT organizations_org_type_check
    CHECK (org_type IN ('manufacturer', 'agent', 'distributor', 'installer', 'customer', 'service_partner'));

-- Add comment for clarity
COMMENT ON COLUMN organizations.org_type IS 'Organization type in channel hierarchy: manufacturer (原厂), agent (代理商), distributor (经销商), installer (安装商), customer (终端用户), service_partner (服务合作伙伴)';
