package models

import (
	"encoding/json"
	"net/http"

	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
)

type IdentityErrorResponse struct {
	status int
	body   contract.Error
	cookie *http.Cookie
}

func NewIdentityErrorResponse(status int, code, message string) IdentityErrorResponse {
	return IdentityErrorResponse{status: status, body: contract.Error{Code: code, Message: message}}
}

func (r IdentityErrorResponse) write(w http.ResponseWriter) error {
	if r.cookie != nil {
		http.SetCookie(w, r.cookie)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(r.status)
	return json.NewEncoder(w).Encode(r.body)
}
func (r IdentityErrorResponse) WithCookie(cookie *http.Cookie) IdentityErrorResponse {
	r.cookie = cookie
	return r
}
func (r IdentityErrorResponse) VisitRestoreSessionResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitRegisterResponse(w http.ResponseWriter) error { return r.write(w) }
func (r IdentityErrorResponse) VisitLoginResponse(w http.ResponseWriter) error    { return r.write(w) }
func (r IdentityErrorResponse) VisitCurrentIdentityResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitGetPersonalActivityResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitLogoutResponse(w http.ResponseWriter) error { return r.write(w) }
func (r IdentityErrorResponse) VisitChangePasswordResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitCreateAccountUserResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitUpdateAccountUserResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitListAccountUsersResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitListAccountsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitSwitchAccountResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitListClaimsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitCreateInvitationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitListInvitationsResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitRevokeInvitationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitAcceptInvitationResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitListSystemUsersResponse(w http.ResponseWriter) error {
	return r.write(w)
}
func (r IdentityErrorResponse) VisitUpdateSystemUserResponse(w http.ResponseWriter) error {
	return r.write(w)
}
