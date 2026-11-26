package handler

import (
	"encoding/json"
	"inv-api-server/internal/model"
	"os"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestPanelCatalogPublishedMetadata(t *testing.T) {
	q := panelCatalogQuery{V: 1, SN: "MB00001122334455", RequestID: "0123456789abcdef", Epoch: 7, Target: "esp"}
	if !panelCatalogValid(q) {
		t.Fatal("valid query rejected")
	}
	good := model.Firmware{ID: 7, Model: "6KU", Version: "0.5.0-modbus-full", TargetChip: "esp", FileURL: "https://firmware.example.com/panel.bin", FileSize: 100000,
		FileSHA256: strings.Repeat("a", 64), Status: 1, ReleaseStatus: model.FirmwareReleasePublished, Changelog: strings.Repeat("更新显示，", 30)}
	draft := good
	draft.ReleaseStatus = "draft"
	badHTTP := good
	badHTTP.FileURL = "http://firmware.example.com/panel.bin"
	dsp := good
	dsp.TargetChip = "dsp"
	oversized := good
	oversized.FileSize = 0x1a0001
	out := buildPanelCatalog(q, []model.Firmware{draft, badHTTP, dsp, oversized, good})
	if out.Status != "ok" || out.Total != 1 || out.Firmware == nil || out.Firmware.Version != good.Version {
		t.Fatalf("unexpected catalog: %+v", out)
	}
	if len(out.Firmware.Changelog) > 96 || !utf8.ValidString(out.Firmware.Changelog) {
		t.Fatal("changelog truncation broke UTF8")
	}
	raw, err := json.Marshal(out)
	if err != nil || len(raw) > 1800 {
		t.Fatal("wire limit exceeded")
	}
	if strings.Contains(string(raw), "rollout_targets") || strings.Contains(string(raw), "uploaded_by") {
		t.Fatal("private firmware data exposed")
	}
	if path := os.Getenv("PANEL_CATALOG_FIXTURE_OUT"); path != "" {
		if err := os.WriteFile(path, raw, 0600); err != nil {
			t.Fatal(err)
		}
	}
	q.Index = 1
	out = buildPanelCatalog(q, []model.Firmware{good})
	if out.Status != "error" {
		t.Fatal("stale offset should report an error")
	}
	q.Index = 0
	out = buildPanelCatalog(q, nil)
	if out.Total != 0 || out.Status != "ok" || out.Firmware != nil {
		t.Fatal("empty catalog is not a failure")
	}
	maximal := good
	maximal.Version = strings.Repeat("v", 31)
	maximal.Model = strings.Repeat("M", 31)
	maximal.FileURL = "https://firmware.example.com/" + strings.Repeat("a", 255-len("https://firmware.example.com/"))
	maximal.ReleaseSignature = strings.Repeat("a", 128)
	maximal.HardwareVersions = []string{strings.Repeat("H", 15)}
	maximal.Changelog = strings.Repeat("更", 32)
	out = buildPanelCatalog(q, []model.Firmware{maximal})
	raw, err = json.Marshal(out)
	if err != nil || out.Status != "ok" || out.Firmware == nil || len(raw) > 1800 || len(out.Firmware.Changelog) != 96 {
		t.Fatal("maximal manifest did not fit the device protocol")
	}
	badUTF8URL := good
	badUTF8URL.FileURL = "https://firmware.example.com/中文.bin"
	if buildPanelCatalog(q, []model.Firmware{badUTF8URL}).Total != 0 {
		t.Fatal("device-incompatible unescaped URL was exposed")
	}
}
func TestPanelCatalogValidation(t *testing.T) {
	q := panelCatalogQuery{V: 1, SN: "MB00001122334455", RequestID: "0123456789abcdef", Epoch: 7, Target: "esp"}
	for _, mutate := range []func(*panelCatalogQuery){func(q *panelCatalogQuery) { q.V = 2 }, func(q *panelCatalogQuery) { q.SN = "another" }, func(q *panelCatalogQuery) { q.RequestID = "bad" }, func(q *panelCatalogQuery) { q.Target = "arm" }, func(q *panelCatalogQuery) { q.Index = 1000 }} {
		invalid := q
		mutate(&invalid)
		if panelCatalogValid(invalid) {
			t.Fatalf("accepted invalid query: %+v", invalid)
		}
	}
}
