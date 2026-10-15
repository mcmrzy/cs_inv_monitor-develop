package model

import (
	"encoding/json"
	"regexp"
	"strings"
	"time"

	"inv-api-server/pkg/apperr"
)

type HardwareBoardType struct {
	Model       string    `json:"model"`
	TargetChip  string    `json:"target_chip"`
	BoardCode   string    `json:"board_code"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
}
type HardwareModule struct {
	TargetChip      string `json:"target_chip"`
	BoardCode       string `json:"board_code"`
	BoardUID        string `json:"board_uid"`
	State           string `json:"state"`
	ModuleRevision  int64  `json:"module_revision"`
	ProtectionLevel string `json:"protection_level"`
}
type HardwareRegistry struct {
	SN               string                `json:"sn"`
	VerifiedModel    string                `json:"verified_model"`
	IdentityState    string                `json:"identity_state"`
	IdentityRevision int64                 `json:"identity_revision"`
	Frozen           bool                  `json:"frozen"`
	Source           string                `json:"source"`
	EvidenceRef      string                `json:"evidence_ref"`
	VerifiedBy       int64                 `json:"verified_by"`
	VerifiedAt       *time.Time            `json:"verified_at"`
	Modules          []HardwareModule      `json:"modules"`
	Observations     []HardwareObservation `json:"observations"`
}
type HardwareObservation struct {
	ID                int64     `json:"id"`
	SN                string    `json:"sn"`
	ReportedModel     string    `json:"reported_model"`
	Scope             string    `json:"scope"`
	ReportedBoardCode string    `json:"reported_board_code"`
	ReportedBoardUID  string    `json:"reported_board_uid"`
	Source            string    `json:"source"`
	ReportedAt        time.Time `json:"reported_at"`
}
type HardwareMutation struct {
	ExpectedRevision int64            `json:"expected_revision"`
	VerifiedModel    string           `json:"verified_model"`
	Source           string           `json:"source"`
	EvidenceRef      string           `json:"evidence_ref"`
	Reason           string           `json:"reason"`
	Modules          []HardwareModule `json:"modules"`
	Frozen           bool             `json:"frozen"`
}
type HardwareHistory struct {
	ID               int64           `json:"id"`
	SN               string          `json:"sn"`
	Action           string          `json:"action"`
	PreviousRevision int64           `json:"previous_revision"`
	IdentityRevision int64           `json:"identity_revision"`
	Actor            int64           `json:"actor"`
	Reason           string          `json:"reason"`
	EvidenceRef      string          `json:"evidence_ref"`
	Before           json.RawMessage `json:"before"`
	After            json.RawMessage `json:"after"`
	CreatedAt        time.Time       `json:"created_at"`
}
type HardwareImportInput struct {
	SN string `json:"sn"`
	HardwareMutation
}
type HardwareImportRow struct {
	RowIndex int                 `json:"row_index"`
	Data     HardwareImportInput `json:"data"`
	Valid    bool                `json:"valid"`
	Errors   []string            `json:"errors"`
	Status   string              `json:"status"`
}
type HardwareImportBatch struct {
	ID   int64               `json:"id"`
	Rows []HardwareImportRow `json:"rows"`
}
type HardwareImportCommit struct {
	RowIndexes     []int  `json:"row_indexes"`
	IdempotencyKey string `json:"idempotency_key"`
}
type OTACompatibilityWindow struct {
	ID               int64     `json:"id"`
	SN               string    `json:"sn"`
	TargetChip       string    `json:"target_chip"`
	FirmwareID       int64     `json:"firmware_id"`
	FileSHA256       string    `json:"file_sha256"`
	IdentityRevision int64     `json:"identity_revision"`
	ExpiresAt        time.Time `json:"expires_at"`
	Reason           string    `json:"reason"`
	EvidenceRef      string    `json:"evidence_ref"`
	Actor            int64     `json:"actor"`
}

// OTATaskCandidate is one device the operator can pick when creating an upgrade
// task. Ineligible devices stay in the list with a reason so a task can never
// silently drop them.
type OTATaskCandidate struct {
	SN              string `json:"sn"`
	Model           string `json:"model"`
	Alias           string `json:"alias"`
	VerifiedModel   string `json:"verified_model"`
	IdentityState   string `json:"identity_state"`
	BoardCode       string `json:"board_code"`
	ModuleState     string `json:"module_state"`
	ProtectionLevel string `json:"protection_level"`
	CurrentVersion  string `json:"current_version"`
	Eligible        bool   `json:"eligible"`
	Reason          string `json:"reason"`
}

type OTATaskCandidateList struct {
	TargetChip    string             `json:"target_chip"`
	FirmwareID    int64              `json:"firmware_id"`
	Items         []OTATaskCandidate `json:"items"`
	Total         int                `json:"total"`
	EligibleCount int                `json:"eligible_count"`
	ExcludedCount int                `json:"excluded_count"`
}

var hardwareSNPattern = regexp.MustCompile(`^[A-Z0-9-]{8,64}$`)
var hardwareBoardPattern = regexp.MustCompile(`^[A-Z0-9][A-Z0-9._-]{0,49}$`)

func HardwareTargetValid(target string) bool {
	return target == "arm" || target == "dsp" || target == "esp" || target == "bms"
}
func ValidateHardwareBoardType(b HardwareBoardType) error {
	if strings.TrimSpace(b.Model) == "" || len(b.Model) > 100 || b.Model != strings.TrimSpace(b.Model) || !HardwareTargetValid(b.TargetChip) || !hardwareBoardPattern.MatchString(b.BoardCode) || len(b.Description) > 500 {
		return apperr.BadRequest("invalid board type")
	}
	return nil
}
func ValidateHardwareMutation(sn, action string, r HardwareMutation) error {
	if !hardwareSNPattern.MatchString(sn) || r.ExpectedRevision < 0 {
		return apperr.BadRequest("invalid SN or expected_revision")
	}
	if strings.TrimSpace(r.EvidenceRef) == "" || len(r.EvidenceRef) > 500 || strings.TrimSpace(r.Reason) == "" || len(r.Reason) > 1000 || len(r.Source) > 100 {
		return apperr.BadRequest("evidence_ref and reason required")
	}
	if action == "freeze" {
		return nil
	}
	if action != "verify" && action != "correction" && action != "service_change" && action != "import" {
		return apperr.BadRequest("invalid hardware action")
	}
	if strings.TrimSpace(r.VerifiedModel) == "" || len(r.VerifiedModel) > 100 || r.VerifiedModel != strings.TrimSpace(r.VerifiedModel) || strings.TrimSpace(r.Source) == "" || len(r.Modules) == 0 || len(r.Modules) > 4 {
		return apperr.BadRequest("model, source and modules required")
	}
	seen := map[string]bool{}
	for _, m := range r.Modules {
		if !HardwareTargetValid(m.TargetChip) || seen[m.TargetChip] {
			return apperr.BadRequest("invalid or duplicate module target")
		}
		seen[m.TargetChip] = true
		if m.State != "verified" && m.State != "absent" {
			return apperr.BadRequest("module state must be verified or absent")
		}
		if m.State == "verified" && !hardwareBoardPattern.MatchString(m.BoardCode) {
			return apperr.BadRequest("invalid board_code")
		}
		if m.State == "absent" && (m.BoardCode != "" || m.BoardUID != "") {
			return apperr.BadRequest("absent module cannot carry board identity")
		}
		if len(m.BoardUID) > 128 || (m.ProtectionLevel != "" && m.ProtectionLevel != "registry_verified") {
			return apperr.BadRequest("device protection cannot be granted by registry edits")
		}
	}
	return nil
}
