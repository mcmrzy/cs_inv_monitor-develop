-- Forward-only data repair. The inserted commands and permissions may have
-- existed before migration 056, so a rollback cannot remove them safely.
SELECT 1;
