package models

type DocumentAuthorityRecord struct {
	Role               string
	Owner              bool
	Claims             []string
	SystemRole         string
	CredentialRevision int64
}
