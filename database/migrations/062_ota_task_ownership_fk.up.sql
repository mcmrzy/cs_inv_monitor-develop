-- Enforce integrity for new/updated rows while allowing legacy orphan review.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_device_upgrades_task'
          AND conrelid = 'device_upgrades'::regclass
    ) THEN
        ALTER TABLE device_upgrades
            ADD CONSTRAINT fk_device_upgrades_task
            FOREIGN KEY (task_id)
            REFERENCES upgrade_tasks(id)
            ON DELETE CASCADE
            NOT VALID;
    END IF;
END $$;
