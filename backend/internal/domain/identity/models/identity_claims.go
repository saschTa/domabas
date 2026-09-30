package models

func ClaimCatalog() []IdentityClaim {
	return []IdentityClaim{
		{ID: ChatUse, Label: "Use private AI chat", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: SystemChatManage, Label: "Configure AI chat", Scope: "system", Roles: []IdentityRole{Admin}},
		{ID: SystemWorkloadsManage, Label: "Configure workload resources", Scope: "system", Roles: []IdentityRole{Admin}},
		{ID: InvoicesRead, Label: "Read invoices", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: PaperlessImport, Label: "Import from Paperless", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: RealtimeConnect, Label: "Receive live updates", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: DocumentsRead, Label: "Read documents", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: DocumentsCreate, Label: "Create documents", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsUpload, Label: "Upload documents", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsUpdate, Label: "Edit document metadata", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsThumbnailsRead, Label: "Read document thumbnails", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: DocumentsDownload, Label: "Download document originals", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: DocumentsSearch, Label: "Search documents", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: DocumentsUnlock, Label: "Unlock password-protected PDFs", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsRetry, Label: "Retry document processing", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsOCRRead, Label: "Read document OCR", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
		{ID: DocumentsOCRUpdate, Label: "Correct document OCR", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsDelete, Label: "Delete documents", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: DocumentsJobsRead, Label: "Read document jobs", Scope: "namespace", Roles: []IdentityRole{Admin}},
		{ID: DocumentsReindex, Label: "Reindex document originals", Scope: "namespace", Roles: []IdentityRole{Admin}},
		{ID: UsersManage, Label: "Manage namespace members", Scope: "namespace", Roles: []IdentityRole{Admin}},
		{ID: SystemUsersManage, Label: "Manage system users", Scope: "system", Roles: []IdentityRole{Admin}},
		{ID: SystemDocumentProcessingManage, Label: "Configure document processing", Scope: "system", Roles: []IdentityRole{Admin}},
		{ID: SystemPaperlessManage, Label: "Configure Paperless retrieval", Scope: "system", Roles: []IdentityRole{Admin}},
		{ID: EmailManage, Label: "Manage personal email accounts", Scope: "namespace", Roles: []IdentityRole{Admin, User}},
		{ID: ActivityReadOwn, Label: "Read personal activity", Scope: "namespace", Roles: []IdentityRole{Admin, User, Viewer}},
	}
}

func ValidateClaims(claims []IdentityPermission) error {
	if len(claims) > 32 {
		return IdentityValidationError("at most 32 claims are allowed")
	}
	known := make(map[IdentityPermission]bool)
	for _, claim := range ClaimCatalog() {
		known[claim.ID] = claim.Scope == "namespace"
	}
	seen := make(map[IdentityPermission]bool)
	for _, claim := range claims {
		if len(claim) > 64 || !known[claim] || seen[claim] {
			return IdentityValidationError("claims must be unique known namespace claims")
		}
		seen[claim] = true
	}
	return nil
}
