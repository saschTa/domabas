package routes

import (
	"bytes"
	"io"
	"net/http"
	"time"

	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
	identity "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/document/models"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/routing"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/oapi-codegen/runtime/types"
)

func groups(guard *transport.HTTPIdentityGuard) []routing.HTTPRouteGroup {
	permissions := map[string][]identity.IdentityPermission{
		"GET /api/v1/documents":                    {identity.DocumentsRead},
		"POST /api/v1/documents":                   {identity.DocumentsCreate},
		"GET /api/v1/documents/{id}":               {identity.DocumentsRead},
		"PATCH /api/v1/documents/{id}":             {identity.DocumentsUpdate},
		"POST /api/v1/documents/upload":            {identity.DocumentsUpload},
		"POST /api/v1/documents/search":            {identity.DocumentsSearch},
		"GET /api/v1/documents/vocabulary":         {identity.DocumentsRead, identity.DocumentsSearch},
		"GET /api/v1/documents/{id}/thumbnail":     {identity.DocumentsThumbnailsRead, identity.DocumentsDownload},
		"GET /api/v1/documents/{id}/content":       {identity.DocumentsDownload},
		"GET /api/v1/documents/{id}/processing":    {identity.DocumentsRead},
		"GET /api/v1/documents/{id}/email-links":   {identity.DocumentsRead},
		"GET /api/v1/documents/{id}/email-parents": {identity.DocumentsRead},
		"POST /api/v1/documents/{id}/ai/retry":     {identity.DocumentsRetry},
		"POST /api/v1/documents/{id}/unlock":       {identity.DocumentsUnlock},
		"POST /api/v1/documents/{id}/retry":        {identity.DocumentsRetry},
		"DELETE /api/v1/documents/{id}":            {identity.DocumentsRead, identity.DocumentsDelete},
		"GET /api/v1/documents/{id}/ocr":           {identity.DocumentsRead, identity.DocumentsOCRRead},
		"PUT /api/v1/documents/{id}/ocr":           {identity.DocumentsRead, identity.DocumentsOCRRead, identity.DocumentsOCRUpdate},
	}
	return []routing.HTTPRouteGroup{
		{Prefix: "/api/v1/document-processing", Middleware: []routing.HTTPMiddleware{guard.RequireAny(identity.DocumentsJobsRead, identity.DocumentsReindex)}},
		{Prefix: "/api/v1/document-jobs", Middleware: []routing.HTTPMiddleware{guard.Require(identity.DocumentsJobsRead)}},
		{Prefix: "/api/v1/document-reindex-batches", Middleware: []routing.HTTPMiddleware{reindexAuthority(guard)}},
		{Prefix: "/api/v1/system/document-reindex-batches", Middleware: []routing.HTTPMiddleware{guard.Require(identity.SystemDocumentProcessingManage)}},
		{Prefix: "/api/v1/documents", Middleware: []routing.HTTPMiddleware{guard.ByPatternAll(permissions)}, Children: []routing.HTTPRouteGroup{
			{Prefix: "/upload", Timeout: 120 * time.Second},
			{Prefix: "/search", Timeout: 30 * time.Second},
			{Prefix: "/{id}", Children: []routing.HTTPRouteGroup{{Prefix: "/content", Timeout: 120 * time.Second}, {Prefix: "/unlock", Timeout: 120 * time.Second}}},
		}}, {Prefix: "/api/v1/system/document-processing", Middleware: []routing.HTTPMiddleware{guard.Require(identity.SystemDocumentProcessingManage)}}}
}

type validatedDocumentServer struct {
	contract.ServerInterface
	uploads chan struct{}
}

func Register(server contract.ServerInterface, guard *transport.HTTPIdentityGuard) (contract.ServerInterface, []routing.HTTPRouteGroup) {
	return &validatedDocumentServer{ServerInterface: server, uploads: make(chan struct{}, 4)}, groups(guard)
}

func (server *validatedDocumentServer) validate(w http.ResponseWriter, r *http.Request, operation string) bool {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return false
	}
	if err := models.ValidateObject(body, operation); err != nil {
		transport.WriteError(w, 400, "invalid_request", err.Error())
		return false
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	return true
}
func (server *validatedDocumentServer) UpdateDocument(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if server.validate(w, r, "update") {
		server.ServerInterface.UpdateDocument(w, r, id)
	}
}
func (server *validatedDocumentServer) SearchDocuments(w http.ResponseWriter, r *http.Request) {
	if server.validate(w, r, "search") {
		server.ServerInterface.SearchDocuments(w, r)
	}
}
func (server *validatedDocumentServer) ListDocuments(w http.ResponseWriter, r *http.Request, params contract.ListDocumentsParams) {
	if values, present := r.URL.Query()["cursor"]; present && (len(values) != 1 || values[0] == "") {
		transport.WriteError(w, 400, "invalid_request", "cursor must be a single nonempty value")
		return
	}
	server.ServerInterface.ListDocuments(w, r, params)
}
func (server *validatedDocumentServer) UpdateDocumentProcessingConfiguration(w http.ResponseWriter, r *http.Request) {
	if server.validate(w, r, "configuration") {
		server.ServerInterface.UpdateDocumentProcessingConfiguration(w, r)
	}
}

func (server *validatedDocumentServer) GetDocumentModelContext(w http.ResponseWriter, r *http.Request, params contract.GetDocumentModelContextParams) {
	if validProcessingQuery(w, r, "model") {
		server.ServerInterface.GetDocumentModelContext(w, r, params)
	}
}
func (server *validatedDocumentServer) UploadDocument(w http.ResponseWriter, r *http.Request) {
	select {
	case server.uploads <- struct{}{}:
		defer func() { <-server.uploads }()
	default:
		w.Header().Set("Retry-After", "1")
		transport.WriteError(w, 429, "overloaded", "upload capacity is temporarily busy")
		return
	}
	const maximum = domain.MaxFileBytes + (64 << 10)
	if r.ContentLength > maximum {
		transport.WriteError(w, 413, "body_too_large", "upload exceeds the request limit")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maximum)
	server.ServerInterface.UploadDocument(w, r.WithContext(models.WithUploadBody(r.Context(), r.Body)))
}
func (server *validatedDocumentServer) RetryDocument(w http.ResponseWriter, r *http.Request, id types.UUID) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1))
	if err != nil || len(body) != 0 {
		transport.WriteError(w, 400, "invalid_request", "retry does not accept a body")
		return
	}
	server.ServerInterface.RetryDocument(w, r, id)
}

func (server *validatedDocumentServer) CreateDocument(w http.ResponseWriter, r *http.Request) {
	body, ok := transport.ReadJSON(w, r)
	if !ok {
		return
	}
	if err := validateJSON(body); err != nil {
		transport.WriteError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	server.ServerInterface.CreateDocument(w, r)
}

func (server *validatedDocumentServer) CreateDocumentReindexBatch(w http.ResponseWriter, r *http.Request) {
	if server.validate(w, r, "reindex") {
		server.ServerInterface.CreateDocumentReindexBatch(w, r)
	}
}

func (server *validatedDocumentServer) CreateSystemDocumentReindexBatch(w http.ResponseWriter, r *http.Request) {
	if server.validate(w, r, "reindex") {
		server.ServerInterface.CreateSystemDocumentReindexBatch(w, r)
	}
}

func reindexAuthority(guard *transport.HTTPIdentityGuard) routing.HTTPMiddleware {
	return func(next http.Handler) http.Handler {
		read := guard.RequireAny(identity.DocumentsJobsRead, identity.DocumentsReindex)(next)
		write := guard.Require(identity.DocumentsReindex)(next)
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodPost {
				write.ServeHTTP(w, r)
			} else {
				read.ServeHTTP(w, r)
			}
		})
	}
}

func validProcessingQuery(w http.ResponseWriter, r *http.Request, allowed ...string) bool {
	known := map[string]bool{}
	for _, name := range allowed {
		known[name] = true
	}
	for name, values := range r.URL.Query() {
		if !known[name] || len(values) != 1 || values[0] == "" {
			transport.WriteError(w, 400, "invalid_request", "processing query values must be known, unique and nonempty")
			return false
		}
	}
	return true
}
func (server *validatedDocumentServer) ListDocumentJobs(w http.ResponseWriter, r *http.Request, p contract.ListDocumentJobsParams) {
	if validProcessingQuery(w, r, "limit", "cursor", "status", "documentId", "pipeline", "activeOnly") {
		server.ServerInterface.ListDocumentJobs(w, r, p)
	}
}
func (server *validatedDocumentServer) GetDocumentEmailLinks(w http.ResponseWriter, r *http.Request, id types.UUID, p contract.GetDocumentEmailLinksParams) {
	if validProcessingQuery(w, r, "limit", "cursor") {
		server.ServerInterface.GetDocumentEmailLinks(w, r, id, p)
	}
}
func (server *validatedDocumentServer) GetDocumentEmailParents(w http.ResponseWriter, r *http.Request, id types.UUID, p contract.GetDocumentEmailParentsParams) {
	if validProcessingQuery(w, r, "limit", "cursor") {
		server.ServerInterface.GetDocumentEmailParents(w, r, id, p)
	}
}
func (server *validatedDocumentServer) ListDocumentReindexBatches(w http.ResponseWriter, r *http.Request, p contract.ListDocumentReindexBatchesParams) {
	if validProcessingQuery(w, r, "limit", "cursor", "activeOnly") {
		server.ServerInterface.ListDocumentReindexBatches(w, r, p)
	}
}
func (server *validatedDocumentServer) ListSystemDocumentReindexBatches(w http.ResponseWriter, r *http.Request, p contract.ListSystemDocumentReindexBatchesParams) {
	if validProcessingQuery(w, r, "limit", "cursor", "activeOnly") {
		server.ServerInterface.ListSystemDocumentReindexBatches(w, r, p)
	}
}

func (server *validatedDocumentServer) RetryDocumentAI(w http.ResponseWriter, r *http.Request, id types.UUID) {
	if server.validate(w, r, "reindex") {
		server.ServerInterface.RetryDocumentAI(w, r, id)
	}
}

func (server *validatedDocumentServer) UnlockDocument(w http.ResponseWriter, r *http.Request, id types.UUID) {
	select {
	case server.uploads <- struct{}{}:
		defer func() { <-server.uploads }()
	default:
		transport.WriteError(w, 429, "overloaded", "document capacity is temporarily busy")
		return
	}
	if server.validate(w, r, "unlock") {
		server.ServerInterface.UnlockDocument(w, r, id)
	}
}
