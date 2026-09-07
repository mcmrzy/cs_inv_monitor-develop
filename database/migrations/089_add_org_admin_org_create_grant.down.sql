-- Migration 089 (down): Remove organizations:create grant added for org_admin
DELETE FROM role_permission_grants
WHERE permission_code = 'organizations:create'
  AND role_assignment_id IN (
      SELECT ra.id FROM membership_role_assignments ra
      WHERE ra.role_code = 'org_admin'
  );
