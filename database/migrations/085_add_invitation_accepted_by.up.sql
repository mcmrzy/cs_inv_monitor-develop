-- Migration 085: Track which user accepted an invitation
-- Enables auditing of invitation redemption and the inviter-side "who accepted" view.

ALTER TABLE invitations ADD COLUMN IF NOT EXISTS accepted_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_invitations_accepted_by
    ON invitations(accepted_by_user_id)
    WHERE accepted_by_user_id IS NOT NULL;
