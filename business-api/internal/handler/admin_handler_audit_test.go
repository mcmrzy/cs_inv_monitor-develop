package handler

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestBuildAuditLogsWithKeyword 验证 keyword 过滤生成的 SQL 片段与占位符参数正确，
// 且列表与导出两条路径共用同一 WHERE 构造。
func TestBuildAuditLogsWithKeyword(t *testing.T) {
	t.Run("keyword only", func(t *testing.T) {
		where, args := buildAuditLogsWhere("", "", "CS-INV-123", "", "")
		assert.Equal(t,
			"WHERE 1=1 AND (resource_id::text ILIKE $1 OR operator_name ILIKE $1 OR action ILIKE $1)",
			where)
		assert.Equal(t, []interface{}{"%CS-INV-123%"}, args)
	})

	t.Run("keyword combined with other filters keeps placeholder numbering", func(t *testing.T) {
		where, args := buildAuditLogsWhere("alice", "command", "SN123", "2026-01-01", "2026-01-31")
		assert.Equal(t,
			"WHERE 1=1"+
				" AND operator_name ILIKE $1"+
				" AND (resource_id::text ILIKE $2 OR operator_name ILIKE $2 OR action ILIKE $2)"+
				" AND action = $3"+
				" AND created_at >= $4"+
				" AND created_at <= $5",
			where)
		assert.Equal(t, []interface{}{
			"%alice%",
			"%SN123%",
			"command",
			"2026-01-01 00:00:00",
			"2026-01-31 23:59:59",
		}, args)
	})

	t.Run("export path shares the same keyword clause", func(t *testing.T) {
		// ExportAuditLogs 以空 userId/action 调用同一构造函数
		where, args := buildAuditLogsWhere("", "", "CS-INV-123", "2026-01-01", "2026-01-31")
		assert.Equal(t,
			"WHERE 1=1"+
				" AND (resource_id::text ILIKE $1 OR operator_name ILIKE $1 OR action ILIKE $1)"+
				" AND created_at >= $2"+
				" AND created_at <= $3",
			where)
		assert.Equal(t, []interface{}{
			"%CS-INV-123%",
			"2026-01-01 00:00:00",
			"2026-01-31 23:59:59",
		}, args)
	})
}

// TestBuildAuditLogsWithoutKeywordUnchanged 验证 keyword 为空时生成的 WHERE
// 与原有逻辑完全一致（不追加任何条件）。
func TestBuildAuditLogsWithoutKeywordUnchanged(t *testing.T) {
	t.Run("no filters at all", func(t *testing.T) {
		where, args := buildAuditLogsWhere("", "", "", "", "")
		assert.Equal(t, "WHERE 1=1", where)
		assert.Empty(t, args)
	})

	t.Run("legacy userId/action/date filters only", func(t *testing.T) {
		where, args := buildAuditLogsWhere("alice", "login", "", "2026-01-01", "2026-01-31")
		assert.Equal(t,
			"WHERE 1=1"+
				" AND operator_name ILIKE $1"+
				" AND action = $2"+
				" AND created_at >= $3"+
				" AND created_at <= $4",
			where)
		assert.Equal(t, []interface{}{
			"%alice%",
			"login",
			"2026-01-01 00:00:00",
			"2026-01-31 23:59:59",
		}, args)
	})

	t.Run("export path with dates only", func(t *testing.T) {
		where, args := buildAuditLogsWhere("", "", "", "2026-01-01", "2026-01-31")
		assert.Equal(t,
			"WHERE 1=1 AND created_at >= $1 AND created_at <= $2",
			where)
		assert.Equal(t, []interface{}{
			"2026-01-01 00:00:00",
			"2026-01-31 23:59:59",
		}, args)
	})
}
