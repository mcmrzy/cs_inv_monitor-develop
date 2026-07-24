-- =====================================================
-- Migration 037 (DOWN): Revert protocol compliance fixes
-- =====================================================

-- C-4: Remove the 4 commands added by this migration
DELETE FROM device_model_commands
WHERE command_code IN (
    'set_soc_low',
    'set_soc_high',
    'parallel_sync_start',
    'parallel_sync_stop'
)
AND model_id = (
    SELECT id FROM device_models WHERE model_code = 'CS-I10-6k2'
);

-- C-3: PV field changes cannot be meaningfully reverted here.
-- Migration 037 deletes ALL PV fields and re-inserts the correct 7.
-- Migration 026 is the authoritative source for the full protocol field
-- set (all groups). To restore PV fields after rolling back 037,
-- simply re-apply migration 026 which will repopulate all protocol
-- fields including the correct 7 PV fields.
