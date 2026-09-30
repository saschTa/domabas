package models

import "time"

type IdentityRole string
type IdentityPermission string

const (
	Admin                          IdentityRole       = "admin"
	User                           IdentityRole       = "user"
	Viewer                         IdentityRole       = "viewer"
	RealtimeConnect                IdentityPermission = "realtime:connect"
	EmailManage                    IdentityPermission = "email:manage"
	PaperlessImport                IdentityPermission = "paperless:import"
	ActivityReadOwn                IdentityPermission = "activity:read:own"
	DocumentsJobsRead              IdentityPermission = "documents:jobs:read"
	DocumentsReindex               IdentityPermission = "documents:reindex"
	InvoicesRead                   IdentityPermission = "invoices:read"
	DocumentsRead                  IdentityPermission = "documents:read"
	DocumentsCreate                IdentityPermission = "documents:create"
	UsersManage                    IdentityPermission = "users:manage"
	SystemUsersManage              IdentityPermission = "system:users:manage"
	DocumentsUpload                IdentityPermission = "documents:upload"
	DocumentsUpdate                IdentityPermission = "documents:update"
	DocumentsThumbnailsRead        IdentityPermission = "documents:thumbnails:read"
	DocumentsDownload              IdentityPermission = "documents:download"
	DocumentsSearch                IdentityPermission = "documents:search"
	DocumentsRetry                 IdentityPermission = "documents:retry"
	DocumentsUnlock                IdentityPermission = "documents:unlock"
	DocumentsOCRRead               IdentityPermission = "documents:ocr:read"
	DocumentsOCRUpdate             IdentityPermission = "documents:ocr:update"
	DocumentsDelete                IdentityPermission = "documents:delete"
	SystemDocumentProcessingManage IdentityPermission = "system:document-processing:manage"
	SystemPaperlessManage          IdentityPermission = "system:paperless:manage"
	ChatUse                        IdentityPermission = "chat:use"
	SystemChatManage               IdentityPermission = "system:chat:manage"
	SystemWorkloadsManage          IdentityPermission = "system:workloads:manage"
)

type IdentityPrincipal struct {
	UserID, Email, AccountID, AccountName, SessionDigest string
	Role                                                 IdentityRole
	SystemRole                                           IdentityRole
	IsOwner                                              bool
	Claims                                               []IdentityPermission
	Permissions                                          []IdentityPermission
	MustChangePassword                                   bool
	CredentialRevision                                   int64
	SessionExpiresAt                                     *time.Time
}

type IdentityCredentials struct {
	Principal    IdentityPrincipal
	PasswordHash string
	Enabled      bool
}

type IdentitySession struct {
	Token     string
	ExpiresAt *time.Time
	Identity  IdentityPrincipal
}

type IdentitySessionRecord struct {
	Digest    string
	ExpiresAt *time.Time
	CreatedAt time.Time
}

type IdentityRegistration struct {
	AccountID, UserID, AccountName, Email, PasswordHash string
	CreatedAt                                           time.Time
	Session                                             IdentitySessionRecord
	ExpectedSetupEligible, ConsumeSetup                 bool
	SystemRole                                          IdentityRole
}

type IdentityMember struct {
	ID, Email                   string
	Role                        IdentityRole
	IsOwner                     bool
	Claims, Permissions         []IdentityPermission
	Enabled, MustChangePassword bool
}

type IdentityNewMember struct {
	ID, AccountID, Email, PasswordHash string
	Role                               IdentityRole
	Claims                             []IdentityPermission
	CreatedAt                          time.Time
	PersonalAccountName                string
	PersonalRole                       IdentityRole
	PersonalOwner                      bool
}

type IdentityMemberPage struct {
	Items []IdentityMember
	Total int64
}

type IdentityValidationError string

type IdentityClaim struct {
	ID           IdentityPermission
	Label, Scope string
	Roles        []IdentityRole
}
type IdentityMembership struct {
	AccountID, AccountName string
	Role                   IdentityRole
	IsOwner                bool
	Claims, Permissions    []IdentityPermission
}
type IdentityMembershipPage struct {
	Items []IdentityMembership
	Total int64
}
type IdentityInvitation struct {
	ID, Email, AccountID, IssuerID, Digest string
	Role                                   IdentityRole
	Claims                                 []IdentityPermission
	CreatedAt, ExpiresAt                   time.Time
	AcceptedAt, RevokedAt                  *time.Time
}
type IdentityIssuedInvitation struct {
	Invitation IdentityInvitation
	Code       string
}
type IdentityInvitationPage struct {
	Items []IdentityInvitation
	Total int64
}
type SystemUser struct {
	ID, Email string
	Role      IdentityRole
	CreatedAt time.Time
}
type SystemUserPage struct {
	Items      []SystemUser
	Total      int64
	AdminCount int64
}
