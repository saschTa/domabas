package routes

import (
	"net/http"
	"net/url"
	"strconv"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	"github.com/oapi-codegen/runtime/types"
)

func validPageQuery(r *http.Request, outcomes bool) bool {
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		return false
	}
	for name, values := range query {
		if len(values) != 1 || values[0] == "" {
			return false
		}
		switch name {
		case "activeOnly":
			if outcomes {
				return false
			}
			if _, err := strconv.ParseBool(values[0]); err != nil {
				return false
			}
		case "limit":
			value, err := strconv.Atoi(values[0])
			if err != nil || value < 1 || value > 100 {
				return false
			}
		case "cursor":
			if len(values[0]) > 4096 {
				return false
			}
		case "status":
			if outcomes {
				switch values[0] {
				case "imported", "duplicate", "failed":
				default:
					return false
				}
			} else {
				switch values[0] {
				case "queued", "running", "succeeded", "partial", "failed", "cancelled":
				default:
					return false
				}
			}
		default:
			return false
		}
	}
	return true
}

func (s *validatedPaperlessServer) ListPaperlessRuns(w http.ResponseWriter, r *http.Request, params contract.ListPaperlessRunsParams) {
	if !validPageQuery(r, false) {
		transport.WriteError(w, 400, "invalid_pagination", "Invalid pagination parameters.")
		return
	}
	s.ServerInterface.ListPaperlessRuns(w, r, params)
}

func (s *validatedPaperlessServer) ListPaperlessOutcomes(w http.ResponseWriter, r *http.Request, id types.UUID, params contract.ListPaperlessOutcomesParams) {
	if !validPageQuery(r, true) {
		transport.WriteError(w, 400, "invalid_pagination", "Invalid pagination parameters.")
		return
	}
	s.ServerInterface.ListPaperlessOutcomes(w, r, id, params)
}
