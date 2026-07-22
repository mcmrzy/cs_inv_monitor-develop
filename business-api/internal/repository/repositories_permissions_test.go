package repository

import (
	"context"
	"errors"
	"sort"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/stretchr/testify/require"
)

type rolePermissionTestDB struct {
	role        int64
	roleErr     error
	permissions []permissionTestRecord
	queryErr    error
	rowsErr     error
	lastSQL     string
	lastArgs    []any
}

type permissionTestRecord struct {
	PermissionEntry
	allowed bool
}

func (d *rolePermissionTestDB) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
	d.lastSQL = sql
	d.lastArgs = args
	return rolePermissionTestRow{role: d.role, err: d.roleErr}
}

func (d *rolePermissionTestDB) Query(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
	d.lastSQL = sql
	d.lastArgs = args
	if d.queryErr != nil {
		return nil, d.queryErr
	}

	permissions := make([]PermissionEntry, 0, len(d.permissions))
	filtersAllowed := strings.Contains(normalizeSQL(sql), "is_allowed = true")
	for _, record := range d.permissions {
		if filtersAllowed && !record.allowed {
			continue
		}
		permissions = append(permissions, record.PermissionEntry)
	}
	if strings.Contains(normalizeSQL(sql), "order by resource, action") {
		sort.Slice(permissions, func(i, j int) bool {
			if permissions[i].Resource == permissions[j].Resource {
				return permissions[i].Action < permissions[j].Action
			}
			return permissions[i].Resource < permissions[j].Resource
		})
	}

	return &rolePermissionTestRows{permissions: permissions, index: -1, err: d.rowsErr}, nil
}

type rolePermissionTestRow struct {
	role int64
	err  error
}

func (r rolePermissionTestRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	if len(dest) != 1 {
		return errors.New("unexpected role scan destination count")
	}
	role, ok := dest[0].(*int64)
	if !ok {
		return errors.New("unexpected role scan destination type")
	}
	*role = r.role
	return nil
}

type rolePermissionTestRows struct {
	permissions []PermissionEntry
	index       int
	err         error
}

func (r *rolePermissionTestRows) Close()                                       {}
func (r *rolePermissionTestRows) Err() error                                   { return r.err }
func (r *rolePermissionTestRows) CommandTag() pgconn.CommandTag                { return pgconn.CommandTag{} }
func (r *rolePermissionTestRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (r *rolePermissionTestRows) RawValues() [][]byte                          { return nil }
func (r *rolePermissionTestRows) Conn() *pgx.Conn                              { return nil }

func (r *rolePermissionTestRows) Next() bool {
	if r.index+1 >= len(r.permissions) {
		return false
	}
	r.index++
	return true
}

func (r *rolePermissionTestRows) Scan(dest ...any) error {
	if r.index < 0 || r.index >= len(r.permissions) {
		return errors.New("scan called without a current permission row")
	}
	if len(dest) != 2 {
		return errors.New("unexpected permission scan destination count")
	}
	resource, resourceOK := dest[0].(*string)
	action, actionOK := dest[1].(*string)
	if !resourceOK || !actionOK {
		return errors.New("unexpected permission scan destination type")
	}
	*resource = r.permissions[r.index].Resource
	*action = r.permissions[r.index].Action
	return nil
}

func (r *rolePermissionTestRows) Values() ([]any, error) {
	if r.index < 0 || r.index >= len(r.permissions) {
		return nil, errors.New("values called without a current permission row")
	}
	return []any{r.permissions[r.index].Resource, r.permissions[r.index].Action}, nil
}

func normalizeSQL(sql string) string {
	return strings.Join(strings.Fields(strings.ToLower(sql)), " ")
}

func TestGetUserRoleIDsReturnsSingleLegacyRoleIncludingZero(t *testing.T) {
	db := &rolePermissionTestDB{role: 0}
	repo := &UserRepository{roleDB: db}

	roles, err := repo.GetUserRoleIDs(context.Background(), 42)

	require.NoError(t, err)
	require.Equal(t, []int64{0}, roles)
	require.Equal(t, []any{int64(42)}, db.lastArgs)
	query := normalizeSQL(db.lastSQL)
	require.Contains(t, query, "select role from users")
	require.Contains(t, query, "id = $1 and deleted_at is null")
	require.NotContains(t, query, "sys_")
}

func TestGetUserRoleIDsUserDoesNotExist(t *testing.T) {
	db := &rolePermissionTestDB{roleErr: pgx.ErrNoRows}
	repo := &UserRepository{roleDB: db}

	roles, err := repo.GetUserRoleIDs(context.Background(), 404)

	require.NoError(t, err)
	require.Empty(t, roles)
	require.NotNil(t, roles)
}

func TestGetUserRoleIDsReturnsDatabaseError(t *testing.T) {
	wantErr := errors.New("role query failed")
	db := &rolePermissionTestDB{roleErr: wantErr}
	repo := &UserRepository{roleDB: db}

	roles, err := repo.GetUserRoleIDs(context.Background(), 7)

	require.Nil(t, roles)
	require.ErrorIs(t, err, wantErr)
}

func TestGetRolePermissionsUsesLegacyAllowedRowsInStableOrder(t *testing.T) {
	db := &rolePermissionTestDB{permissions: []permissionTestRecord{
		{PermissionEntry: PermissionEntry{Resource: "devices", Action: "view"}, allowed: true},
		{PermissionEntry: PermissionEntry{Resource: "admin", Action: "manage"}, allowed: false},
		{PermissionEntry: PermissionEntry{Resource: "alerts", Action: "edit"}, allowed: true},
		{PermissionEntry: PermissionEntry{Resource: "alerts", Action: "view"}, allowed: true},
	}}
	repo := &UserRepository{roleDB: db}

	permissions, err := repo.GetRolePermissions(context.Background(), 1)

	require.NoError(t, err)
	require.Equal(t, []PermissionEntry{
		{Resource: "alerts", Action: "edit"},
		{Resource: "alerts", Action: "view"},
		{Resource: "devices", Action: "view"},
	}, permissions)
	require.Equal(t, []any{int64(1)}, db.lastArgs)
	query := normalizeSQL(db.lastSQL)
	require.Contains(t, query, "from role_permissions")
	require.Contains(t, query, "where role = $1 and is_allowed = true")
	require.Contains(t, query, "order by resource, action")
	require.NotContains(t, query, "sys_")
}

func TestGetRolePermissionsSupportsRoleZero(t *testing.T) {
	db := &rolePermissionTestDB{permissions: []permissionTestRecord{
		{PermissionEntry: PermissionEntry{Resource: "admin", Action: "manage"}, allowed: true},
	}}
	repo := &UserRepository{roleDB: db}

	permissions, err := repo.GetRolePermissions(context.Background(), 0)

	require.NoError(t, err)
	require.Equal(t, []PermissionEntry{{Resource: "admin", Action: "manage"}}, permissions)
	require.Equal(t, []any{int64(0)}, db.lastArgs)
}

func TestGetRolePermissionsReturnsEmptyNonNilSlice(t *testing.T) {
	repo := &UserRepository{roleDB: &rolePermissionTestDB{}}

	permissions, err := repo.GetRolePermissions(context.Background(), 5)

	require.NoError(t, err)
	require.Empty(t, permissions)
	require.NotNil(t, permissions)
}

func TestGetRolePermissionsReturnsDatabaseErrors(t *testing.T) {
	t.Run("query", func(t *testing.T) {
		wantErr := errors.New("permission query failed")
		repo := &UserRepository{roleDB: &rolePermissionTestDB{queryErr: wantErr}}

		permissions, err := repo.GetRolePermissions(context.Background(), 2)

		require.Nil(t, permissions)
		require.ErrorIs(t, err, wantErr)
	})

	t.Run("rows", func(t *testing.T) {
		wantErr := errors.New("permission rows failed")
		repo := &UserRepository{roleDB: &rolePermissionTestDB{rowsErr: wantErr}}

		permissions, err := repo.GetRolePermissions(context.Background(), 2)

		require.Nil(t, permissions)
		require.ErrorIs(t, err, wantErr)
	})
}
