package service

import (
	"context"
	"errors"
	"sort"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type permissionTestRow struct {
	allowed bool
	err     error
}

func (r permissionTestRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	*(dest[0].(*bool)) = r.allowed
	return nil
}

type permissionTestDB struct {
	owners   map[int64]map[string]bool
	grants   map[int64]map[string]bool
	deleted  map[string]bool
	err      error
	queryErr error
	query    string
	queryArg []any
}

func (d *permissionTestDB) Query(_ context.Context, query string, args ...any) (pgx.Rows, error) {
	d.query = query
	d.queryArg = append([]any(nil), args...)
	if d.queryErr != nil {
		return nil, d.queryErr
	}
	userID := args[0].(int64)
	seen := make(map[string]bool)
	for sn := range d.owners[userID] {
		if !d.deleted[sn] {
			seen[sn] = true
		}
	}
	for sn := range d.grants[userID] {
		if !d.deleted[sn] {
			seen[sn] = true
		}
	}
	sns := make([]string, 0, len(seen))
	for sn := range seen {
		sns = append(sns, sn)
	}
	sort.Strings(sns)
	return &permissionTestRows{sns: sns}, nil
}

func (d *permissionTestDB) QueryRow(_ context.Context, query string, args ...any) pgx.Row {
	d.query = query
	d.queryArg = append([]any(nil), args...)
	if d.err != nil {
		return permissionTestRow{err: d.err}
	}
	userID := args[0].(int64)
	sn := args[1].(string)
	allowed := !d.deleted[sn] && (d.owners[userID][sn] || d.grants[userID][sn])
	return permissionTestRow{allowed: allowed}
}

type permissionTestRows struct {
	sns   []string
	index int
	err   error
}

func (r *permissionTestRows) Close()                                       {}
func (r *permissionTestRows) Err() error                                   { return r.err }
func (r *permissionTestRows) CommandTag() pgconn.CommandTag                { return pgconn.CommandTag{} }
func (r *permissionTestRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (r *permissionTestRows) Values() ([]any, error)                       { return nil, errors.New("not implemented") }
func (r *permissionTestRows) RawValues() [][]byte                          { return nil }
func (r *permissionTestRows) Conn() *pgx.Conn                              { return nil }

func (r *permissionTestRows) Next() bool {
	return r.index < len(r.sns)
}

func (r *permissionTestRows) Scan(dest ...any) error {
	if !r.Next() {
		return errors.New("scan called without a row")
	}
	*(dest[0].(*string)) = r.sns[r.index]
	r.index++
	return nil
}

func TestDataPermissionHasDeviceAccess(t *testing.T) {
	tests := []struct {
		name   string
		db     *permissionTestDB
		userID int64
		sn     string
		want   bool
	}{
		{
			name:   "direct owner",
			db:     &permissionTestDB{owners: map[int64]map[string]bool{7: {"OWNER-1": true}}, grants: map[int64]map[string]bool{}, deleted: map[string]bool{}},
			userID: 7,
			sn:     "OWNER-1",
			want:   true,
		},
		{
			name:   "delegated relation",
			db:     &permissionTestDB{owners: map[int64]map[string]bool{}, grants: map[int64]map[string]bool{8: {"SHARED-1": true}}, deleted: map[string]bool{}},
			userID: 8,
			sn:     "SHARED-1",
			want:   true,
		},
		{
			name:   "foreign device",
			db:     &permissionTestDB{owners: map[int64]map[string]bool{9: {"FOREIGN-1": true}}, grants: map[int64]map[string]bool{}, deleted: map[string]bool{}},
			userID: 8,
			sn:     "FOREIGN-1",
			want:   false,
		},
		{
			name:   "soft deleted device",
			db:     &permissionTestDB{owners: map[int64]map[string]bool{7: {"DELETED-1": true}}, grants: map[int64]map[string]bool{}, deleted: map[string]bool{"DELETED-1": true}},
			userID: 7,
			sn:     "DELETED-1",
			want:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			permission := &DataPermission{pool: tt.db}
			got, err := permission.HasDeviceAccess(context.Background(), tt.userID, tt.sn)
			if err != nil {
				t.Fatal(err)
			}
			if got != tt.want {
				t.Fatalf("allowed=%v, want %v", got, tt.want)
			}
			if !strings.Contains(tt.db.query, "FROM devices d") ||
				!strings.Contains(tt.db.query, "FROM user_device_rel udr") ||
				!strings.Contains(tt.db.query, "d.deleted_at IS NULL") {
				t.Fatalf("access query does not cover owner, delegated and soft-delete rules: %s", tt.db.query)
			}
			if len(tt.db.queryArg) != 2 || tt.db.queryArg[0] != tt.userID || tt.db.queryArg[1] != tt.sn {
				t.Fatalf("unexpected query args: %#v", tt.db.queryArg)
			}
		})
	}
}

func TestDataPermissionHasDeviceAccessReturnsDatabaseError(t *testing.T) {
	wantErr := errors.New("database unavailable")
	db := &permissionTestDB{err: wantErr}
	permission := &DataPermission{pool: db}

	allowed, err := permission.HasDeviceAccess(context.Background(), 7, "OWNER-1")
	if allowed || !errors.Is(err, wantErr) {
		t.Fatalf("allowed=%v err=%v, want false and %v", allowed, err, wantErr)
	}
}

func TestDataPermissionBuildSNFilterDoesNotBypassRoleOneWithoutDevices(t *testing.T) {
	// User ID 1 represents a role=1 account. DataPermission deliberately does
	// not treat it as a superuser; only role=0 may bypass at the handler layer.
	db := &permissionTestDB{owners: map[int64]map[string]bool{}, grants: map[int64]map[string]bool{}, deleted: map[string]bool{}}
	permission := &DataPermission{pool: db}

	filter, args, err := permission.BuildSNFilter(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if filter != "1=0" || len(args) != 0 {
		t.Fatalf("filter=%q args=%#v, want deny-all", filter, args)
	}
}

func TestDataPermissionBuildSNFilterRoleOneOnlyIncludesBoundDevices(t *testing.T) {
	db := &permissionTestDB{
		owners:  map[int64]map[string]bool{},
		grants:  map[int64]map[string]bool{1: {"BOUND-2": true, "BOUND-1": true}},
		deleted: map[string]bool{},
	}
	permission := &DataPermission{pool: db}

	filter, args, err := permission.BuildSNFilter(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if filter != "sn IN ($1,$2)" {
		t.Fatalf("filter=%q", filter)
	}
	if len(args) != 2 || args[0] != "BOUND-1" || args[1] != "BOUND-2" {
		t.Fatalf("args=%#v, want only bound devices", args)
	}
}
