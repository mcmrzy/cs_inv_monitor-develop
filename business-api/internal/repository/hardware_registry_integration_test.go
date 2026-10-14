//go:build integration

package repository

import (
	"context"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"strings"
	"sync"
	"testing"
	"time"
)

func hardwareTestMutation() model.HardwareMutation {
	return model.HardwareMutation{VerifiedModel: "MODEL", Source: "factory", EvidenceRef: "ledger-10", Reason: "checked production ledger", Modules: []model.HardwareModule{{TargetChip: "esp", BoardCode: "COMM-A", BoardUID: "board-01", State: "verified"}}}
}
func TestHardwareRegistryConcurrentVerificationAndObservation(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	r := NewHardwareRegistryRepository(pool)
	ctx := context.Background()
	require.NoError(t, r.CreateBoardType(ctx, model.HardwareBoardType{Model: "MODEL", TargetChip: "esp", BoardCode: "COMM-A"}))
	req := hardwareTestMutation()
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); _, err := r.Mutate(ctx, "SN123456", "verify", req, 1); results <- err }()
	}
	wg.Wait()
	close(results)
	success, failure := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else {
			failure++
		}
	}
	require.Equal(t, 1, success)
	require.Equal(t, 1, failure)
	got, err := r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, int64(1), got.IdentityRevision)
	require.Equal(t, "registry_verified", got.Modules[0].ProtectionLevel)
	now := time.Now().UTC()
	require.NoError(t, r.Observe(ctx, model.HardwareObservation{SN: "SN123456", Scope: "legacy_system", ReportedBoardCode: "WRONG-LEGACY", Source: "mqtt", ReportedAt: now}))
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "verified", got.IdentityState, "legacy string is not a module identity")
	require.NoError(t, r.Observe(ctx, model.HardwareObservation{SN: "SN123456", Scope: "esp", ReportedBoardCode: "COMM-B", Source: "mqtt", ReportedAt: now}))
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "conflict", got.IdentityState)
	require.Equal(t, "COMM-A", got.Modules[0].BoardCode)
	require.Equal(t, int64(2), got.IdentityRevision)
	require.NoError(t, r.Observe(ctx, model.HardwareObservation{SN: "SN123456", Scope: "esp", ReportedBoardCode: "COMM-A", Source: "mqtt", ReportedAt: now.Add(time.Minute)}))
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "conflict", got.IdentityState, "later correct report cannot clear conflict")
	req.ExpectedRevision = 2
	_, err = r.Mutate(ctx, "SN123456", "correction", req, 1)
	require.NoError(t, err)
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "verified", got.IdentityState)
	// An older report remains evidence but cannot put the corrected identity back into conflict.
	require.NoError(t, r.Observe(ctx, model.HardwareObservation{SN: "SN123456", Scope: "esp", ReportedBoardCode: "COMM-B", Source: "mqtt", ReportedAt: now.Add(-time.Minute)}))
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "verified", got.IdentityState)
	history, total, err := r.History(ctx, "SN123456", 1, 20)
	require.NoError(t, err)
	require.Equal(t, int64(3), total)
	require.Len(t, history, 3)
}

func TestHardwareRegistryImportsAreIdempotentAndDoNotCreateDevices(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	r := NewHardwareRegistryRepository(pool)
	ctx := context.Background()
	require.NoError(t, r.CreateBoardType(ctx, model.HardwareBoardType{Model: "MODEL", TargetChip: "esp", BoardCode: "COMM-A"}))
	input := model.HardwareImportInput{SN: "SN123456", HardwareMutation: hardwareTestMutation()}
	batch, err := r.StageImport(ctx, []model.HardwareImportInput{input, input}, 1)
	require.NoError(t, err)
	require.True(t, batch.Rows[0].Valid)
	require.False(t, batch.Rows[1].Valid)
	batch, err = r.CommitImport(ctx, batch.ID, 1, model.HardwareImportCommit{RowIndexes: []int{1}, IdempotencyKey: "test-commit"})
	require.NoError(t, err)
	require.Equal(t, "committed", batch.Rows[0].Status)
	_, err = r.CommitImport(ctx, batch.ID, 1, model.HardwareImportCommit{RowIndexes: []int{1}, IdempotencyKey: "test-commit"})
	require.NoError(t, err)
	record, err := r.Get(ctx, input.SN)
	require.NoError(t, err)
	require.Equal(t, int64(1), record.IdentityRevision)
	var deviceCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT count(*) FROM devices`).Scan(&deviceCount))
	require.Zero(t, deviceCount)
	input.Modules[0].BoardUID = "replacement"
	different, err := r.StageImport(ctx, []model.HardwareImportInput{input}, 1)
	require.NoError(t, err)
	require.False(t, different.Rows[0].Valid)
	require.Equal(t, "conflict", different.Rows[0].Status)
	_, err = r.CommitImport(ctx, different.ID, 1, model.HardwareImportCommit{RowIndexes: []int{1}, IdempotencyKey: "bad"})
	require.Error(t, err)
	record, err = r.Get(ctx, input.SN)
	require.NoError(t, err)
	require.Equal(t, "board-01", record.Modules[0].BoardUID)
}

func TestHardwareRegistryFreezeAndScopeAudit(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	r := NewHardwareRegistryRepository(pool)
	ctx := context.Background()
	require.NoError(t, r.CreateBoardType(ctx, model.HardwareBoardType{Model: "MODEL", TargetChip: "esp", BoardCode: "COMM-A"}))
	require.NoError(t, r.CreateBoardType(ctx, model.HardwareBoardType{Model: "MODEL", TargetChip: "esp", BoardCode: "COMM-B"}))
	req := hardwareTestMutation()
	_, err := r.Mutate(ctx, "SN123456", "verify", req, 1)
	require.NoError(t, err)
	req.ExpectedRevision = 1
	req.Modules[0].BoardCode = "COMM-B"
	_, err = r.Mutate(ctx, "SN123456", "service_change", req, 1)
	require.ErrorContains(t, err, "freeze")
	freeze := model.HardwareMutation{ExpectedRevision: 1, Frozen: true, Source: "service", Reason: "repair", EvidenceRef: "workorder-1"}
	_, err = r.Mutate(ctx, "SN123456", "freeze", freeze, 1)
	require.NoError(t, err)
	req.ExpectedRevision = 2
	_, err = r.Mutate(ctx, "SN123456", "service_change", req, 1)
	require.NoError(t, err)
	record, err := r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.True(t, record.Frozen)
	freeze.ExpectedRevision = 3
	freeze.Frozen = false
	_, err = r.Mutate(ctx, "SN123456", "freeze", freeze, 1)
	require.NoError(t, err)
	var fid int64
	require.NoError(t, pool.QueryRow(ctx, `INSERT INTO firmware_versions(model,target_chip,version,file_url,file_sha256,status,release_status) VALUES('MODEL','esp','1.0','/firmware/a', $1,1,'published') RETURNING id`, strings.Repeat("a", 64)).Scan(&fid))
	require.NoError(t, r.SetFirmwareBoards(ctx, fid, 1, []string{"COMM-B"}, "historical scope checked", "release-evidence"))
	require.Error(t, r.SetFirmwareBoards(ctx, fid, 1, []string{"COMM-A"}, "change", "evidence"))
	w := model.OTACompatibilityWindow{SN: "SN123456", TargetChip: "esp", FirmwareID: fid, FileSHA256: strings.Repeat("a", 64), IdentityRevision: 4, ExpiresAt: time.Now().Add(time.Hour), Reason: "controlled migration", EvidenceRef: "workorder-1"}
	_, err = r.CreateCompatibilityWindow(ctx, w, 1)
	require.NoError(t, err)
	var audit int
	require.NoError(t, pool.QueryRow(ctx, `SELECT count(*) FROM firmware_board_scope_audits`).Scan(&audit))
	require.Equal(t, 1, audit)
}

func TestHardwareRegistryAuthenticatedSNConflictIsAnchored(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	r := NewHardwareRegistryRepository(pool)
	ctx := context.Background()
	require.NoError(t, r.RecordIdentityConflict(ctx, "SN123456", "payload SN mismatch", "mqtt payload_sn=OTHER"))
	got, err := r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "conflict", got.IdentityState)
	require.Equal(t, int64(1), got.IdentityRevision)
	other, err := r.Get(ctx, "SN999999")
	require.NoError(t, err)
	require.Zero(t, other.IdentityRevision)
	require.Empty(t, other.Modules)
	require.NoError(t, r.RecordIdentityConflict(ctx, "SN123456", "payload SN mismatch", "mqtt"))
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, int64(1), got.IdentityRevision)
}

func TestHardwareRegistryFutureClockCannotHideLaterConflict(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	r := NewHardwareRegistryRepository(pool)
	ctx := context.Background()
	require.NoError(t, r.CreateBoardType(ctx, model.HardwareBoardType{Model: "MODEL", TargetChip: "esp", BoardCode: "COMM-A"}))
	req := hardwareTestMutation()
	req.Modules[0].BoardUID = ""
	_, err := r.Mutate(ctx, "SN123456", "verify", req, 1)
	require.NoError(t, err)
	future := time.Now().Add(10 * 365 * 24 * time.Hour)
	require.NoError(t, r.Observe(ctx, model.HardwareObservation{SN: "SN123456", Scope: "esp", ReportedBoardCode: "COMM-A", ReportedBoardUID: "read-new-uid", Source: "mqtt", ReportedAt: future}))
	got, err := r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "verified", got.IdentityState, "missing ledger UID does not prevent registry-only approval")
	require.WithinDuration(t, future, got.Observations[0].ReportedAt, time.Millisecond, "raw clock is retained")
	require.NoError(t, r.Observe(ctx, model.HardwareObservation{SN: "SN123456", Scope: "esp", ReportedBoardCode: "COMM-B", Source: "mqtt", ReportedAt: time.Now().UTC()}))
	got, err = r.Get(ctx, "SN123456")
	require.NoError(t, err)
	require.Equal(t, "conflict", got.IdentityState)
}
