package repository

import "context"

// Only executed tasks may deliver. A pending sibling must wait until the device
// finishes its current module, including across separate parent tasks.
const pendingDeliveryCondition = `du.status = 'pending'
 AND (du.task_id IS NULL OR task.status = 'running')
 AND NOT EXISTS (SELECT 1 FROM device_upgrades active
     WHERE active.device_sn = du.device_sn AND active.status IN ('downloading', 'upgrading'))`

// ListPendingDeliveryDevices recovers tasks after reconnects, lost commands and
// server restarts. The oldest eligible module is selected again before sending.
func (r *OTARepository) ListPendingDeliveryDevices(ctx context.Context) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT du.device_sn
 FROM device_upgrades du
 LEFT JOIN upgrade_tasks task ON task.id = du.task_id
 JOIN devices d ON d.sn = du.device_sn AND d.status IN (1,2) AND d.deleted_at IS NULL
 WHERE `+pendingDeliveryCondition+`
   AND (du.last_dispatched_at IS NULL OR du.last_dispatched_at < NOW() - INTERVAL '1 minute')
 GROUP BY du.device_sn ORDER BY MIN(du.last_dispatched_at) NULLS FIRST, du.device_sn LIMIT 100`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var sns []string
	for rows.Next() {
		var sn string
		if err := rows.Scan(&sn); err != nil {
			return nil, err
		}
		sns = append(sns, sn)
	}
	return sns, rows.Err()
}

// ClaimUpgradeDelivery serializes attempts for the same device and throttles
// unacknowledged commands. Keep the same upgrade ID on every attempt. Do not
// skip a locked head: that could dispatch the following module concurrently.
func (r *OTARepository) ClaimUpgradeDelivery(ctx context.Context, id int64, sn string, retryCount int) (bool, error) {
	var claimed bool
	err := r.db.QueryRow(ctx, `WITH head AS (
 SELECT du.id, du.task_id, du.last_dispatched_at IS NULL AS first_delivery
 FROM device_upgrades du LEFT JOIN upgrade_tasks task ON task.id = du.task_id
 WHERE du.device_sn = $2 AND `+pendingDeliveryCondition+`
 ORDER BY du.created_at, du.id LIMIT 1 FOR UPDATE OF du
), delivered AS (
 UPDATE device_upgrades du SET last_dispatched_at = NOW()
 WHERE du.id = $1 AND du.id = (SELECT id FROM head)
   AND du.status = 'pending'
   AND COALESCE(du.retry_count, 0) = $3
   AND (du.last_dispatched_at IS NULL OR du.last_dispatched_at < NOW() - INTERVAL '1 minute')
   AND EXISTS (SELECT 1 FROM devices d WHERE d.sn = $2 AND d.status IN (1,2) AND d.deleted_at IS NULL)
 RETURNING du.id
), touched AS (
 UPDATE upgrade_tasks SET updated_at = NOW()
 WHERE id = (SELECT task_id FROM head WHERE first_delivery)
   AND EXISTS (SELECT 1 FROM delivered)
)
SELECT EXISTS (SELECT 1 FROM delivered)`, id, sn, retryCount).Scan(&claimed)
	return claimed, err
}
