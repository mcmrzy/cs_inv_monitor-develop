package migration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

const (
	ReasonUnmappedLegacyRole      = "UNMAPPED_LEGACY_ROLE"
	ReasonConflictingRoleMapping  = "CONFLICTING_ROLE_MAPPING"
	ReasonParentCycle             = "PARENT_CYCLE"
	ReasonOrphanParent            = "ORPHAN_PARENT"
	ReasonDuplicateIdentifier     = "DUPLICATE_IDENTIFIER"
	ReasonOwnerConflict           = "OWNER_CONFLICT"
	ReasonBlockedAncestor         = "BLOCKED_ANCESTOR"
	ReasonIllegalHierarchy        = "ILLEGAL_HIERARCHY"
	ReasonMissingTenantRoot       = "MISSING_OR_AMBIGUOUS_TENANT"
	ReasonInvalidQuotaInheritance = "INVALID_QUOTA_INHERITANCE"
	organizationBackfillJob       = "backfill-organizations-v1"
)

type LegacyUser struct {
	ID       int64  `json:"id"`
	Phone    string `json:"phone"`
	Email    string `json:"email,omitempty"`
	Nickname string `json:"nickname,omitempty"`
	Role     int    `json:"role"`
	ParentID *int64 `json:"parent_id,omitempty"`
	Status   int    `json:"status"`
	Deleted  bool   `json:"deleted"`
}

type LegacyOwnershipFact struct {
	ResourceType string `json:"resource_type"`
	ResourceKey  string `json:"resource_key"`
	OwnerUserID  int64  `json:"owner_user_id"`
}

type LegacyRoleMapping struct {
	LegacyRole       int              `json:"legacy_role"`
	OrganizationType string           `json:"organization_type"`
	RoleCodes        []string         `json:"role_codes"`
	QuotaDefaults    map[string]int64 `json:"quota_defaults,omitempty"`
}

type ChannelMappingConfig struct {
	SchemaVersion string              `json:"schema_version"`
	Roles         []LegacyRoleMapping `json:"roles"`
}

func LoadChannelMappingConfig(path string) (ChannelMappingConfig, string, error) {
	var config ChannelMappingConfig
	contents, err := os.ReadFile(path)
	if err != nil {
		return config, "", fmt.Errorf("read channel mapping config: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&config); err != nil {
		return config, "", fmt.Errorf("decode channel mapping config: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return config, "", fmt.Errorf("channel mapping config must contain one JSON object")
	}
	if err := ValidateChannelMappingConfig(config); err != nil {
		return config, "", err
	}
	digest, err := config.Digest()
	return config, digest, err
}

func ValidateChannelMappingConfig(config ChannelMappingConfig) error {
	if config.SchemaVersion != "1" {
		return fmt.Errorf("unsupported mapping schema_version %q; expected 1", config.SchemaVersion)
	}
	if len(config.Roles) == 0 {
		return fmt.Errorf("at least one explicit legacy role mapping is required")
	}
	allowedOrganizations := map[string]bool{
		"manufacturer": true, "agent": true, "distributor": true,
		"customer": true, "service_partner": true,
	}
	allowedRoles := map[string]bool{
		"org_admin": true, "channel_manager": true, "operator": true, "installer": true,
		"after_sales": true, "viewer": true, "finance": true, "api_client": true,
	}
	allowedQuotas := map[string]bool{
		"members": true, "direct_child_organizations": true, "descendant_organizations": true,
		"inventory_devices": true, "claimed_devices": true, "stations": true,
		"pending_invitations": true, "concurrent_exports": true, "api_requests_per_minute": true,
	}
	seen := make(map[int]struct{})
	for _, mapping := range config.Roles {
		if _, exists := seen[mapping.LegacyRole]; exists {
			return fmt.Errorf("legacy role %d appears more than once; numeric roles are never auto-resolved", mapping.LegacyRole)
		}
		seen[mapping.LegacyRole] = struct{}{}
		if !allowedOrganizations[mapping.OrganizationType] {
			return fmt.Errorf("legacy role %d has invalid organization_type %q", mapping.LegacyRole, mapping.OrganizationType)
		}
		if len(mapping.RoleCodes) == 0 {
			return fmt.Errorf("legacy role %d must declare at least one functional role", mapping.LegacyRole)
		}
		roleSeen := make(map[string]struct{})
		for _, roleCode := range mapping.RoleCodes {
			if !allowedRoles[roleCode] {
				return fmt.Errorf("legacy role %d has invalid role_code %q", mapping.LegacyRole, roleCode)
			}
			if _, exists := roleSeen[roleCode]; exists {
				return fmt.Errorf("legacy role %d repeats role_code %q", mapping.LegacyRole, roleCode)
			}
			roleSeen[roleCode] = struct{}{}
		}
		for resourceType, limit := range mapping.QuotaDefaults {
			if !allowedQuotas[resourceType] || limit < 0 {
				return fmt.Errorf("legacy role %d has invalid quota %q=%d", mapping.LegacyRole, resourceType, limit)
			}
		}
	}
	return nil
}

func (c ChannelMappingConfig) Digest() (string, error) {
	normalized := make([]LegacyRoleMapping, len(c.Roles))
	for i, role := range c.Roles {
		normalized[i] = role
		normalized[i].RoleCodes = append([]string(nil), role.RoleCodes...)
		normalized[i].QuotaDefaults = copyQuotaDefaults(role.QuotaDefaults)
	}
	sort.Slice(normalized, func(i, j int) bool { return normalized[i].LegacyRole < normalized[j].LegacyRole })
	for i := range normalized {
		sort.Strings(normalized[i].RoleCodes)
	}
	payload, err := json.Marshal(struct {
		SchemaVersion string              `json:"schema_version"`
		Roles         []LegacyRoleMapping `json:"roles"`
	}{c.SchemaVersion, normalized})
	if err != nil {
		return "", fmt.Errorf("marshal mapping config: %w", err)
	}
	digest := sha256.Sum256(payload)
	return hex.EncodeToString(digest[:]), nil
}

type QuarantineEntry struct {
	SourceTable string         `json:"source_table"`
	SourceKey   string         `json:"source_key"`
	ReasonCode  string         `json:"reason_code"`
	Detail      string         `json:"detail,omitempty"`
	Payload     map[string]any `json:"payload,omitempty"`
}

type BackfillOperation struct {
	Kind              string           `json:"kind"`
	SourceUserID      int64            `json:"source_user_id"`
	OrganizationID    int64            `json:"organization_id"`
	RootTenantID      int64            `json:"root_tenant_id"`
	ParentID          *int64           `json:"parent_id,omitempty"`
	OrganizationType  string           `json:"organization_type"`
	OrganizationCode  string           `json:"organization_code"`
	OrganizationName  string           `json:"organization_name"`
	Status            string           `json:"status"`
	RoleCodes         []string         `json:"role_codes"`
	QuotaDefaults     map[string]int64 `json:"quota_defaults,omitempty"`
	Depth             int              `json:"depth"`
	SourceFingerprint string           `json:"source_fingerprint"`
}

type PreflightReport struct {
	Operations          []BackfillOperation `json:"operations"`
	Quarantine          []QuarantineEntry   `json:"quarantine"`
	OwnershipQuarantine []QuarantineEntry   `json:"ownership_quarantine"`
}

func (r PreflightReport) ReasonsFor(userID int64) []string {
	key := fmt.Sprint(userID)
	var reasons []string
	for _, entry := range r.Quarantine {
		if entry.SourceTable == "users" && entry.SourceKey == key {
			reasons = append(reasons, entry.ReasonCode)
		}
	}
	sort.Strings(reasons)
	return reasons
}

func AnalyzeLegacyUsers(users []LegacyUser, mappings []LegacyRoleMapping, ownership []LegacyOwnershipFact) PreflightReport {
	userByID := make(map[int64]LegacyUser, len(users))
	for _, user := range users {
		userByID[user.ID] = user
	}

	mappingByRole := make(map[int]LegacyRoleMapping)
	conflictingRoles := make(map[int]bool)
	for _, mapping := range mappings {
		if existing, ok := mappingByRole[mapping.LegacyRole]; ok {
			if existing.OrganizationType != mapping.OrganizationType || !equalStrings(existing.RoleCodes, mapping.RoleCodes) {
				conflictingRoles[mapping.LegacyRole] = true
			} else {
				conflictingRoles[mapping.LegacyRole] = true
			}
			continue
		}
		mappingByRole[mapping.LegacyRole] = mapping
	}

	reasons := make(map[int64]map[string]string)
	addReason := func(id int64, code, detail string) {
		if reasons[id] == nil {
			reasons[id] = make(map[string]string)
		}
		reasons[id][code] = detail
	}
	for _, user := range users {
		if conflictingRoles[user.Role] {
			addReason(user.ID, ReasonConflictingRoleMapping, fmt.Sprintf("legacy role %d has more than one mapping", user.Role))
		} else if _, ok := mappingByRole[user.Role]; !ok {
			addReason(user.ID, ReasonUnmappedLegacyRole, fmt.Sprintf("legacy role %d has no explicit mapping", user.Role))
		}
		if user.ParentID != nil {
			if _, ok := userByID[*user.ParentID]; !ok {
				addReason(user.ID, ReasonOrphanParent, fmt.Sprintf("parent user %d does not exist", *user.ParentID))
			}
		}
	}

	markDuplicateIdentifiers(users, addReason)
	markCycles(users, userByID, addReason)

	depthByID := make(map[int64]int)
	rootByID := make(map[int64]int64)
	var resolve func(int64) (int64, int, bool)
	resolve = func(id int64) (int64, int, bool) {
		if _, bad := reasons[id]; bad {
			return 0, 0, false
		}
		if root, ok := rootByID[id]; ok {
			return root, depthByID[id], true
		}
		user := userByID[id]
		mapping, ok := mappingByRole[user.Role]
		if !ok || conflictingRoles[user.Role] {
			return 0, 0, false
		}
		if user.ParentID == nil {
			if mapping.OrganizationType != "manufacturer" {
				addReason(id, ReasonMissingTenantRoot, "top-level legacy user is not mapped to manufacturer")
				return 0, 0, false
			}
			rootByID[id], depthByID[id] = id, 0
			return id, 0, true
		}
		parentRoot, parentDepth, ok := resolve(*user.ParentID)
		if !ok {
			addReason(id, ReasonBlockedAncestor, fmt.Sprintf("parent user %d is quarantined", *user.ParentID))
			return 0, 0, false
		}
		parentMapping := mappingByRole[userByID[*user.ParentID].Role]
		if !legalOrganizationEdge(parentMapping.OrganizationType, mapping.OrganizationType) {
			addReason(id, ReasonIllegalHierarchy, fmt.Sprintf("%s cannot parent %s", parentMapping.OrganizationType, mapping.OrganizationType))
			return 0, 0, false
		}
		for resourceType, limit := range mapping.QuotaDefaults {
			found := false
			ancestorID := user.ParentID
			for ancestorID != nil {
				ancestor := userByID[*ancestorID]
				ancestorMapping, mapped := mappingByRole[ancestor.Role]
				if mapped {
					if ancestorLimit, exists := ancestorMapping.QuotaDefaults[resourceType]; exists {
						found = true
						if limit > ancestorLimit {
							addReason(id, ReasonInvalidQuotaInheritance, fmt.Sprintf("quota %s=%d exceeds ancestor %d limit %d", resourceType, limit, ancestor.ID, ancestorLimit))
							return 0, 0, false
						}
					}
				}
				ancestorID = ancestor.ParentID
			}
			if !found {
				addReason(id, ReasonInvalidQuotaInheritance, fmt.Sprintf("quota %s has no configured ancestor limit", resourceType))
				return 0, 0, false
			}
		}
		rootByID[id], depthByID[id] = parentRoot, parentDepth+1
		return parentRoot, parentDepth + 1, true
	}

	orderedUsers := append([]LegacyUser(nil), users...)
	sort.Slice(orderedUsers, func(i, j int) bool { return orderedUsers[i].ID < orderedUsers[j].ID })
	for _, user := range orderedUsers {
		_, _, _ = resolve(user.ID)
	}

	var operations []BackfillOperation
	for _, user := range orderedUsers {
		root, depth, ok := resolve(user.ID)
		if !ok {
			continue
		}
		mapping := mappingByRole[user.Role]
		// Legacy nickname can contain personal data. The backfill uses a stable,
		// non-PII placeholder; operators may rename organizations after review.
		name := "Legacy user " + fmt.Sprint(user.ID)
		status := "active"
		if user.Status == 0 || user.Deleted {
			status = "disabled"
		}
		sourceFingerprint, _ := fingerprintJSON(user)
		operations = append(operations, BackfillOperation{
			Kind:              "organization",
			SourceUserID:      user.ID,
			OrganizationID:    user.ID,
			RootTenantID:      root,
			ParentID:          user.ParentID,
			OrganizationType:  mapping.OrganizationType,
			OrganizationCode:  fmt.Sprintf("legacy-user-%d", user.ID),
			OrganizationName:  name,
			Status:            status,
			RoleCodes:         sortedCopy(mapping.RoleCodes),
			QuotaDefaults:     copyQuotaDefaults(mapping.QuotaDefaults),
			Depth:             depth,
			SourceFingerprint: sourceFingerprint,
		})
	}
	sort.Slice(operations, func(i, j int) bool {
		if operations[i].Depth != operations[j].Depth {
			return operations[i].Depth < operations[j].Depth
		}
		return operations[i].SourceUserID < operations[j].SourceUserID
	})

	quarantine := flattenReasons(reasons, userByID)
	ownerQuarantine := analyzeOwnershipConflicts(ownership)
	return PreflightReport{Operations: operations, Quarantine: quarantine, OwnershipQuarantine: ownerQuarantine}
}

func markDuplicateIdentifiers(users []LegacyUser, add func(int64, string, string)) {
	owners := make(map[string][]int64)
	for _, user := range users {
		for _, pair := range []struct{ kind, value string }{{"phone", user.Phone}, {"email", user.Email}} {
			value := strings.ToLower(strings.TrimSpace(pair.value))
			if value != "" {
				owners[pair.kind+":"+value] = append(owners[pair.kind+":"+value], user.ID)
			}
		}
	}
	for identifier, ids := range owners {
		if len(ids) < 2 {
			continue
		}
		for _, id := range ids {
			identifierType := strings.SplitN(identifier, ":", 2)[0]
			add(id, ReasonDuplicateIdentifier, "normalized "+identifierType+" collision")
		}
	}
}

func markCycles(users []LegacyUser, userByID map[int64]LegacyUser, add func(int64, string, string)) {
	state := make(map[int64]int)
	stack := make([]int64, 0)
	position := make(map[int64]int)
	var visit func(int64)
	visit = func(id int64) {
		if state[id] == 2 {
			return
		}
		if state[id] == 1 {
			for _, cycleID := range stack[position[id]:] {
				add(cycleID, ReasonParentCycle, "legacy parent graph contains a cycle")
			}
			return
		}
		state[id] = 1
		position[id] = len(stack)
		stack = append(stack, id)
		if parent := userByID[id].ParentID; parent != nil {
			if _, ok := userByID[*parent]; ok {
				visit(*parent)
			}
		}
		stack = stack[:len(stack)-1]
		delete(position, id)
		state[id] = 2
	}
	for _, user := range users {
		visit(user.ID)
	}
}

func flattenReasons(reasons map[int64]map[string]string, users map[int64]LegacyUser) []QuarantineEntry {
	var entries []QuarantineEntry
	for id, byCode := range reasons {
		for code, detail := range byCode {
			entries = append(entries, QuarantineEntry{
				SourceTable: "users", SourceKey: fmt.Sprint(id), ReasonCode: code, Detail: detail,
				Payload: map[string]any{"legacy_role": users[id].Role},
			})
		}
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].SourceKey != entries[j].SourceKey {
			return entries[i].SourceKey < entries[j].SourceKey
		}
		return entries[i].ReasonCode < entries[j].ReasonCode
	})
	return entries
}

func analyzeOwnershipConflicts(facts []LegacyOwnershipFact) []QuarantineEntry {
	type owners map[int64]struct{}
	grouped := make(map[string]owners)
	for _, fact := range facts {
		key := fact.ResourceType + ":" + fact.ResourceKey
		if grouped[key] == nil {
			grouped[key] = make(owners)
		}
		grouped[key][fact.OwnerUserID] = struct{}{}
	}
	var result []QuarantineEntry
	for key, ownerSet := range grouped {
		if len(ownerSet) < 2 {
			continue
		}
		digest := sha256.Sum256([]byte("legacy-ownership:" + key))
		result = append(result, QuarantineEntry{SourceTable: "legacy_ownership", SourceKey: "sha256:" + hex.EncodeToString(digest[:]), ReasonCode: ReasonOwnerConflict})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].SourceKey < result[j].SourceKey })
	return result
}

func legalOrganizationEdge(parent, child string) bool {
	return (parent == "manufacturer" && child == "agent") ||
		(parent == "agent" && child == "distributor") ||
		(parent == "distributor" && child == "customer") ||
		(child == "service_partner" && (parent == "manufacturer" || parent == "agent" || parent == "distributor"))
}

type OrganizationBackfillStore interface {
	LoadCheckpoint(ctx context.Context, jobName, mappingDigest string) (int, error)
	ApplyBatch(ctx context.Context, jobName, mappingDigest string, after int, operations []BackfillOperation) (int, error)
}

type BackfillResult struct {
	Applied    int `json:"applied"`
	Checkpoint int `json:"checkpoint"`
}

func ExecuteOrganizationBackfill(ctx context.Context, store OrganizationBackfillStore, mappingDigest string, operations []BackfillOperation, batchSize int) (BackfillResult, error) {
	if mappingDigest == "" {
		return BackfillResult{}, fmt.Errorf("mapping digest is required")
	}
	if batchSize <= 0 {
		return BackfillResult{}, fmt.Errorf("batch size must be positive")
	}
	checkpoint, err := store.LoadCheckpoint(ctx, organizationBackfillJob, mappingDigest)
	if err != nil {
		return BackfillResult{}, fmt.Errorf("load organization backfill checkpoint: %w", err)
	}
	if checkpoint < 0 || checkpoint > len(operations) {
		return BackfillResult{}, fmt.Errorf("checkpoint %d is outside plan of %d operations", checkpoint, len(operations))
	}
	result := BackfillResult{Checkpoint: checkpoint}
	for checkpoint < len(operations) {
		end := checkpoint + batchSize
		if end > len(operations) {
			end = len(operations)
		}
		next, err := store.ApplyBatch(ctx, organizationBackfillJob, mappingDigest, checkpoint, operations[checkpoint:end])
		if err != nil {
			return result, fmt.Errorf("apply organization backfill batch after %d: %w", checkpoint, err)
		}
		if next != end {
			return result, fmt.Errorf("store returned non-contiguous checkpoint %d, expected %d", next, end)
		}
		result.Applied += next - checkpoint
		checkpoint = next
		result.Checkpoint = checkpoint
	}
	return result, nil
}

func equalStrings(a, b []string) bool {
	ac, bc := sortedCopy(a), sortedCopy(b)
	if len(ac) != len(bc) {
		return false
	}
	for i := range ac {
		if ac[i] != bc[i] {
			return false
		}
	}
	return true
}

func sortedCopy(values []string) []string {
	result := append([]string(nil), values...)
	sort.Strings(result)
	return result
}

func copyQuotaDefaults(input map[string]int64) map[string]int64 {
	if len(input) == 0 {
		return nil
	}
	result := make(map[string]int64, len(input))
	for key, value := range input {
		result[key] = value
	}
	return result
}
