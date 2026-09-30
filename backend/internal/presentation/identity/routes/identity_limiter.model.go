package routes

import "time"

type identityRateLimitBucket struct {
	start, last time.Time
	count       int
}
