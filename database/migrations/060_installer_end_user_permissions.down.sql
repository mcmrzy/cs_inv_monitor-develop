-- Do not delete permission rows on rollback: an administrator may have changed
-- them after migration 060. Rollback of the access views is handled by 059.
SELECT 1;
