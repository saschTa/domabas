package routes

import (
	"net/http"
	"net/url"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
)

func (s *validatedIdentityServer) GetPersonalActivity(w http.ResponseWriter, r *http.Request, params contract.GetPersonalActivityParams) {
	query, err := url.ParseQuery(r.URL.RawQuery)
	valid := err == nil
	for name, values := range query {
		if (name != "activeCursor" && name != "finishedCursor") || len(values) != 1 || values[0] == "" || len(values[0]) > 4096 {
			valid = false
		}
	}
	if !valid {
		transport.WriteError(w, 400, "invalid_request", "Invalid activity pagination parameters.")
		return
	}
	s.ServerInterface.GetPersonalActivity(w, r, params)
}
