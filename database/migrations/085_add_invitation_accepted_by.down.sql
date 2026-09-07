-- Rollback Migration 085: Remove invitation accepted-by tracking

DROP INDEX IF EXISTS idx_invitations_accepted_by;

ALTER TABLE invitations DROP COLUMN IF EXISTS accepted_by_user_id;
