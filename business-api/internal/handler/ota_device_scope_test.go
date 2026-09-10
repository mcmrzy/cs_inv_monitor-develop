package handler

import (
	"context"
	"go/ast"
	"go/parser"
	"go/token"
	"testing"
)

type denyingOTADeviceScopeChecker struct {
	calls int
}

func (f *denyingOTADeviceScopeChecker) CheckDeviceOwnership(context.Context, string, int64) (bool, error) {
	f.calls++
	return false, nil
}

func TestOTADeviceScopeDeniesBeforeHistoryRead(t *testing.T) {
	checker := &denyingOTADeviceScopeChecker{}
	handler := &OTAHandler{deviceScopeChecker: checker}
	c, recorder := createTestGinContext("/api/v1/ota/devices/OTHER-SN/history", "GET", nil)
	c.AddParam("sn", "OTHER-SN")
	c.Set("user_id", int64(42))

	handler.GetDeviceOTAHistory(c)

	assertBizResponse(t, recorder, 403, "无权管理该设备")
	if checker.calls != 1 {
		t.Fatalf("scope checker calls = %d, want 1", checker.calls)
	}
}

func TestOTADeviceScopeGuardCoversEveryAppDeviceHandler(t *testing.T) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "ota_handler.go", nil, 0)
	if err != nil {
		t.Fatalf("parse ota_handler.go: %v", err)
	}

	requiredHandlers := []string{
		"CheckUpdate",
		"TriggerOTA",
		"ResendUpgradeCommand",
		"GetDeviceOTAStatus",
		"GetDeviceOTAHistory",
		"ReportLocalOTAResult",
		"AppInstallPackage",
		"GetDevicePackageUpgradeInfo",
		"ListDeviceUpgradePackages",
		"GetAvailablePackages",
	}

	functions := make(map[string]*ast.FuncDecl)
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok {
			functions[fn.Name.Name] = fn
		}
	}

	helper := functions["ensureDeviceManagementScope"]
	if helper == nil {
		t.Fatal("ensureDeviceManagementScope helper is missing")
	}
	if !callsMethod(helper, "CheckDeviceOwnership") {
		t.Error("ensureDeviceManagementScope must delegate to CheckDeviceOwnership")
	}

	for _, name := range requiredHandlers {
		fn := functions[name]
		if fn == nil {
			t.Errorf("required OTA handler %s is missing", name)
			continue
		}
		if !callsMethod(fn, "ensureDeviceManagementScope") {
			t.Errorf("%s must call ensureDeviceManagementScope", name)
		}
	}
}

func callsMethod(fn *ast.FuncDecl, method string) bool {
	found := false
	ast.Inspect(fn.Body, func(node ast.Node) bool {
		call, ok := node.(*ast.CallExpr)
		if !ok {
			return true
		}
		selector, ok := call.Fun.(*ast.SelectorExpr)
		if ok && selector.Sel.Name == method {
			found = true
			return false
		}
		return true
	})
	return found
}
