package handler

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"
)

var panelCatalogSN = regexp.MustCompile(`^[A-Z0-9]{16}$`)
var panelCatalogID = regexp.MustCompile(`^[0-9a-f]{16}$`)
var panelCatalogHash = regexp.MustCompile(`^[0-9a-f]{64}$`)

type panelCatalogQuery struct {
	V         int    `json:"v"`
	SN        string `json:"sn"`
	RequestID string `json:"request_id"`
	Epoch     uint32 `json:"epoch"`
	Index     uint32 `json:"index"`
	Target    string `json:"target"`
}
type panelCatalogFirmware struct {
	ID              int64  `json:"id"`
	Version         string `json:"version"`
	Target          string `json:"target_chip"`
	Model           string `json:"model"`
	Hardware        string `json:"hardware"`
	URL             string `json:"file_url"`
	Size            int64  `json:"file_size"`
	SHA256          string `json:"file_sha256"`
	SecurityVersion uint32 `json:"security_version"`
	Signature       string `json:"release_signature"`
	Changelog       string `json:"changelog"`
}
type panelCatalogReply struct {
	V         int                   `json:"v"`
	Action    string                `json:"action"`
	SN        string                `json:"sn"`
	RequestID string                `json:"request_id"`
	Epoch     uint32                `json:"epoch"`
	Index     uint32                `json:"index"`
	Total     int                   `json:"total"`
	Status    string                `json:"status"`
	Firmware  *panelCatalogFirmware `json:"firmware,omitempty"`
}

func panelCatalogValid(q panelCatalogQuery) bool {
	return q.V == 1 && q.Target == "esp" && panelCatalogSN.MatchString(q.SN) && panelCatalogID.MatchString(q.RequestID) && q.Index < 1000
}
func panelCatalogToken(s string, max int) bool {
	if s == "" || len(s) > max {
		return false
	}
	for _, c := range s {
		if c < 33 || c > 126 {
			return false
		}
	}
	return true
}
func panelCatalogChangelog(s string) string {
	s = strings.Map(func(c rune) rune {
		if unicode.IsControl(c) {
			return ' '
		}
		return c
	}, s)
	if len(s) > 96 {
		s = s[:96]
		for !utf8.ValidString(s) {
			s = s[:len(s)-1]
		}
	}
	return s
}
func buildPanelCatalog(q panelCatalogQuery, resources []model.Firmware) panelCatalogReply {
	out := panelCatalogReply{V: 1, Action: "catalog", SN: q.SN, RequestID: q.RequestID, Epoch: q.Epoch, Index: q.Index, Status: "ok"}
	for _, f := range resources {
		hash := strings.ToLower(f.FileSHA256)
		if f.TargetChip != "esp" || f.ReleaseStatus != model.FirmwareReleasePublished || f.Status != 1 ||
			!panelCatalogToken(f.Version, 31) || !panelCatalogToken(f.Model, 31) || f.FileSize <= 0 || f.FileSize > 0x1a0000 ||
			len(f.FileURL) > 255 || !strings.HasPrefix(f.FileURL, "https://") || service.ValidateDeviceDownloadURL(f.FileURL) != nil ||
			!panelCatalogHash.MatchString(hash) || len(f.ReleaseSignature) > 131 {
			continue
		}
		if out.Total == int(q.Index) {
			hardware := ""
			if len(f.HardwareVersions) == 1 && panelCatalogToken(f.HardwareVersions[0], 15) {
				hardware = f.HardwareVersions[0]
			}
			out.Firmware = &panelCatalogFirmware{ID: f.ID, Version: f.Version, Target: f.TargetChip, Model: f.Model, Hardware: hardware,
				URL: f.FileURL, Size: f.FileSize, SHA256: hash, SecurityVersion: f.SecurityVersion, Signature: f.ReleaseSignature, Changelog: panelCatalogChangelog(f.Changelog)}
		}
		out.Total++
		if out.Total == 1000 {
			break
		}
	}
	if out.Total > 0 && out.Firmware == nil {
		out.Status = "error"
	}
	encoded, err := json.Marshal(out)
	if err != nil || len(encoded) > 1800 {
		out.Status = "error"
		out.Firmware = nil
	}
	return out
}

// PanelOTACatalog is called only by the authenticated internal device bridge.
// It exposes no private rollout targets or user fields and creates no OTA task.
func (h *InternalHandler) PanelOTACatalog(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 512)
	var q panelCatalogQuery
	if c.ShouldBindJSON(&q) != nil || !panelCatalogValid(q) {
		response.Error(c, http.StatusBadRequest, "invalid panel firmware query")
		return
	}
	if h.otaService == nil {
		response.Error(c, http.StatusServiceUnavailable, "firmware catalog unavailable")
		return
	}
	resources, err := h.otaService.GetPublishedFirmwareResources(c.Request.Context(), q.SN, q.Target)
	if err != nil {
		response.Error(c, http.StatusServiceUnavailable, "firmware catalog unavailable")
		return
	}
	response.Success(c, buildPanelCatalog(q, resources))
}
