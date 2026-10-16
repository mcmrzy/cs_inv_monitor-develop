package model

import (
	"fmt"
	"strconv"
	"strings"
)

// OTACommandTaskID identifies an execution attempt, while the upgrade ID remains
// the database record ID. Redelivery within an attempt uses the same token.
func OTACommandTaskID(id int64, retryCount int) string {
	idText := strconv.FormatInt(id, 10)
	if retryCount > 0 {
		return idText + "-r" + strconv.Itoa(retryCount)
	}
	return idText
}

// ParseOTACommandTaskID accepts legacy numeric IDs as attempt zero. Explicit
// malformed tokens must never fall back to another active upgrade.
func ParseOTACommandTaskID(token string) (int64, int, error) {
	idText, retryText, hasRetry := strings.Cut(token, "-r")
	id, err := strconv.ParseInt(idText, 10, 64)
	if err != nil || id <= 0 || strconv.FormatInt(id, 10) != idText {
		return 0, 0, fmt.Errorf("invalid OTA task ID")
	}
	retryCount := 0
	if hasRetry {
		// retry_count is a PostgreSQL integer, including on 64-bit servers.
		parsedRetry, parseErr := strconv.ParseInt(retryText, 10, 32)
		if parseErr != nil || parsedRetry <= 0 || strconv.FormatInt(parsedRetry, 10) != retryText {
			return 0, 0, fmt.Errorf("invalid OTA task attempt")
		}
		retryCount = int(parsedRetry)
	}
	return id, retryCount, nil
}
