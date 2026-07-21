package migration

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestListMigrationsExcludesBackfillAndRollbackFiles(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{
		"001_structure.up.sql", "002_more_structure.sql", "002_more_structure.down.sql",
		"channel_backfill.sql", "README.md",
	} {
		require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte("SELECT 1"), 0o600))
	}
	files, err := listMigrations(dir)
	require.NoError(t, err)
	var names []string
	for _, file := range files {
		names = append(names, filepath.Base(file))
	}
	assert.Equal(t, []string{"001_structure.up.sql", "002_more_structure.sql"}, names)
}
