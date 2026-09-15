package handler

import (
	"context"
	"go/ast"
	"go/parser"
	"go/token"
	"testing"

	"inv-api-server/internal/model"
)

type denyingOTADeviceScopeChecker struct {
	calls      int
	permission string
}

func (f *denyingOTADeviceScopeChecker) CheckDevicePermission(_ context.Context, _ model.ActorContext, permission, _ string) (bool, error) {
	f.calls++
	f.permission = permission
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
	if checker.permission != "devices:view" {
		t.Fatalf("permission = %q, want devices:view", checker.permission)
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

	helper := functions["ensureDeviceScope"]
	if helper == nil {
		t.Fatal("ensureDeviceScope helper is missing")
	}
	if !callsMethod(helper, "CheckDevicePermission") {
		t.Error("ensureDeviceScope must delegate to CheckDevicePermission")
	}

	for _, name := range requiredHandlers {
		fn := functions[name]
		if fn == nil {
			t.Errorf("required OTA handler %s is missing", name)
			continue
		}
		if !callsMethod(fn, "ensureDeviceViewScope") && !callsMethod(fn, "ensureDeviceControlScope") {
			t.Errorf("%s must call an explicit view/control device scope guard", name)
		}
	}
}

func TestOTADeviceControlScopeUsesDevicesControl(t *testing.T) {
	checker := &denyingOTADeviceScopeChecker{}
	handler := &OTAHandler{deviceScopeChecker: checker}
	c, recorder := createTestGinContext("/api/v1/ota/resend/SN-1", "POST", nil)
	c.AddParam("sn", "SN-1")
	c.Set("user_id", int64(42))

	handler.ResendUpgradeCommand(c)

	assertBizResponse(t, recorder, 403, "无权")
	if checker.permission != "devices:control" {
		t.Fatalf("permission = %q, want devices:control", checker.permission)
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
