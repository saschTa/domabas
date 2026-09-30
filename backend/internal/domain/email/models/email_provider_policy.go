package models

import "time"

const MaximumEmailProviders = 20

type EmailTestAdmission struct {
	Lease, Pacing time.Duration
}

func DefaultEmailTestAdmission() EmailTestAdmission {
	return EmailTestAdmission{Lease: 15 * time.Second, Pacing: 5 * time.Second}
}

func EmailConsentState(provider EmailProvider, credentialRevision int64) string {
	if !provider.Enabled {
		return "disabled"
	}
	if provider.ConsentRevision != credentialRevision {
		return "renewal_required"
	}
	return "valid"
}
