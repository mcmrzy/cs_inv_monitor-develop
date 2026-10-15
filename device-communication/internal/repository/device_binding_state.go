package repository

import (
	"context"
	"fmt"
)

// BindingSnapshot reads ownership and its revision in the same SQL snapshot.
// Missing/deleted devices are UNKNOWN, never automatically UNBOUND.
func (r *DeviceRepository) BindingSnapshot(ctx context.Context, sn string) (string, string, error) {
	var state, revision string
	err := r.db.QueryRow(ctx, `SELECT
 CASE WHEN d.sn IS NULL OR d.deleted_at IS NOT NULL THEN 'UNKNOWN'
      WHEN COALESCE(d.user_id,0) > 0 THEN 'BOUND' ELSE 'UNBOUND' END,
 COALESCE(b.revision,0)::text
 FROM (SELECT $1::text AS sn) requested
 LEFT JOIN devices d ON d.sn = requested.sn
 LEFT JOIN binding_state_revisions b ON b.sn = requested.sn`, sn).Scan(&state, &revision)
	if err != nil {
		return "", "", fmt.Errorf("read binding snapshot: %w", err)
	}
	return state, revision, nil
}
