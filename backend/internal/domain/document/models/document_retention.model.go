package models

import "time"

type DocumentCleanupCompletion struct {
	Attempts    int
	NextAttempt time.Time
}

func PlanDocumentCleanup(lease DocumentCleanupLease, success bool, now time.Time) DocumentCleanupCompletion {
	if success {
		return DocumentCleanupCompletion{NextAttempt: now.Add(5 * time.Minute)}
	}
	seconds := min(300, 5*(1<<min(max(lease.Attempts, 0), 6)))
	return DocumentCleanupCompletion{Attempts: min(lease.Attempts+1, 8), NextAttempt: now.Add(time.Duration(seconds) * time.Second)}
}
