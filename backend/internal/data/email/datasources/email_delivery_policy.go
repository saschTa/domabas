package datasources

import "time"

const (
	emailExecutionStartWindow    = 23*time.Hour + 59*time.Minute
	emailExecutionStartPermit    = 5 * time.Second
	emailExecutionCheckInterval  = 10 * time.Second
	emailExecutionCheckLease     = 15 * time.Second
	emailActivityMaximumLease    = 120 * time.Second
	emailExecutionClockAllowance = time.Minute
)
