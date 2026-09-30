package models

import (
	"encoding/hex"
	"strings"
	"time"
)

const PaperlessMaximumUnclosedRuns = 100

type PaperlessRetrievalPolicy struct {
	OperationTimeout time.Duration
	RecoveryTimeout  time.Duration
}

func DefaultPaperlessRetrievalPolicy() PaperlessRetrievalPolicy {
	return PaperlessRetrievalPolicy{OperationTimeout: time.Minute, RecoveryTimeout: 2 * time.Minute}
}

func ValidatePaperlessStart(id string, connection PaperlessConnection) error {
	if !validPaperlessRequestID(id) {
		return PaperlessFailure{Code: "invalid_request"}
	}
	if len(connection.Token) < 1 || len(connection.Token) > 256 {
		return PaperlessFailure{Code: "invalid_request"}
	}
	for _, ch := range connection.Token {
		if ch < 33 || ch > 126 {
			return PaperlessFailure{Code: "invalid_request"}
		}
	}
	return nil
}

func validPaperlessRequestID(id string) bool {
	if len(id) == 45 && strings.EqualFold(id[:9], "urn:uuid:") {
		id = id[9:]
	}
	if len(id) == 38 && id[0] == '{' && id[37] == '}' {
		id = id[1:37]
	}
	if len(id) == 36 {
		if id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
			return false
		}
		id = id[:8] + id[9:13] + id[14:18] + id[19:23] + id[24:]
	}
	if len(id) != 32 {
		return false
	}
	decoded, err := hex.DecodeString(id)
	if err != nil {
		return false
	}
	for _, value := range decoded {
		if value != 0 {
			return true
		}
	}
	return false
}
