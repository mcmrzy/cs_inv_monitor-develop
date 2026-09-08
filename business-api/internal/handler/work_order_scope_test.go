package handler

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestWorkOrderDataScopeParenthesized 防止回归：
// 数据范围片段会与外部 AND 条件拼接（如 Update/Delete/Escalate 的
// "WHERE id::text=$1 AND <scope> AND ..."），一旦片段本身未加括号，
// SQL 解析时 AND 优先级高于 OR，会退化成 "(原条件) OR creator_id=$N"，
// 导致对系统管理员误更新/误删除其创建的全部工单。
func TestWorkOrderDataScopeParenthesized(t *testing.T) {
	for _, tc := range []struct {
		name          string
		isSystemAdmin bool
	}{
		{name: "system_admin", isSystemAdmin: true},
		{name: "regular_user", isSystemAdmin: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			scope := workOrderDataScope("work_orders", tc.isSystemAdmin, 9)
			if !strings.HasPrefix(scope, "(") || !strings.HasSuffix(scope, ")") {
				t.Fatalf("workOrderDataScope must be fully parenthesized, got: %s", scope)
			}

			// 模拟 Update 的拼接形态，确认 OR 不会逃逸出括号
			where := "id::text=$1 AND " + scope + " AND ($10::bigint IS NULL OR lock_version=$10)"
			depth := 0
			for i := 0; i < len(where); i++ {
				switch where[i] {
				case '(':
					depth++
				case ')':
					depth--
				case 'O', 'o':
					// 顶层（depth==0）不允许出现 OR 关键字
					if depth == 0 && strings.EqualFold(where[i:min(i+2, len(where))], "OR") {
						t.Fatalf("top-level OR found outside parentheses: %s", where)
					}
				}
				if depth < 0 {
					t.Fatalf("unbalanced parentheses: %s", where)
				}
			}
		})
	}
}

// TestWorkOrderSLAFilter 工单列表 sla 参数过滤：
// 正向——"overdue" 追加 "sla_deadline 已过且状态非 resolved/closed" 条件；
// 边界——空值与其他取值均不追加条件（行为不变）。
func TestWorkOrderSLAFilter(t *testing.T) {
	overdue := workOrderSLAFilter("overdue")
	for _, want := range []string{
		"w.sla_deadline IS NOT NULL",
		"w.sla_deadline < NOW()",
		"w.status NOT IN ('resolved','closed')",
	} {
		if !strings.Contains(overdue, want) {
			t.Fatalf("sla=overdue filter missing %q, got: %s", want, overdue)
		}
	}

	// 条件需自带括号，避免与外部 AND/OR 拼接时优先级错乱
	if !strings.HasPrefix(overdue, " AND (") || !strings.HasSuffix(overdue, ")") {
		t.Fatalf("sla filter must start with ' AND (' and end with ')', got: %s", overdue)
	}

	for _, sla := range []string{"", "ok", "overdue2", "OVERDUE"} {
		if got := workOrderSLAFilter(sla); got != "" {
			t.Fatalf("sla=%q should not filter, got: %s", sla, got)
		}
	}
}

// TestWorkOrderRequestResolutionBinding 工单状态更新请求体的 resolution 可选字段
// （契约：JSON 字段名 "resolution"，持久化到 work_orders.resolution，该列已存在）。
func TestWorkOrderRequestResolutionBinding(t *testing.T) {
	// 正向：resolution 随状态更新一并提交并被绑定
	var req workOrderRequest
	if err := json.Unmarshal([]byte(`{"status":"resolved","resolution":"replaced the DC board"}`), &req); err != nil {
		t.Fatalf("bind request: %v", err)
	}
	if req.Status != "resolved" {
		t.Fatalf("status = %q, want resolved", req.Status)
	}
	if req.Resolution != "replaced the DC board" {
		t.Fatalf("resolution = %q, want %q", req.Resolution, "replaced the DC board")
	}

	// 边界：不传 resolution 时为空串；Update 使用 COALESCE(NULLIF($8,''),resolution)
	// 不会覆盖工单已有解决方案
	var empty workOrderRequest
	if err := json.Unmarshal([]byte(`{"status":"open"}`), &empty); err != nil {
		t.Fatalf("bind request: %v", err)
	}
	if empty.Resolution != "" {
		t.Fatalf("resolution should default to empty, got %q", empty.Resolution)
	}
}
