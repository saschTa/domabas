package routes

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"unicode/utf8"

	domain "github.com/domabas/domabas/backend/internal/domain/identity/models"
	"github.com/domabas/domabas/backend/internal/presentation/identity/models"
)

func validateFields(body []byte, fields ...string) (map[string]json.RawMessage, error) {
	if !utf8.Valid(body) {
		return nil, domain.IdentityValidationError("request body must be valid UTF-8")
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return nil, domain.IdentityValidationError("request body must be an object")
	}
	result := make(map[string]json.RawMessage, len(fields))
	allowed := make(map[string]bool, len(fields))
	for _, field := range fields {
		allowed[field] = true
	}
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nil, domain.IdentityValidationError("request body is invalid")
		}
		key, ok := token.(string)
		if !ok || !allowed[key] {
			return nil, domain.IdentityValidationError("request contains an unknown field")
		}
		if _, ok := result[key]; ok {
			return nil, domain.IdentityValidationError("duplicate fields are not allowed")
		}
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return nil, domain.IdentityValidationError("request body is invalid")
		}
		if bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return nil, domain.IdentityValidationError("request fields cannot be null")
		}
		result[key] = value
	}
	if _, err := decoder.Token(); err != nil {
		return nil, domain.IdentityValidationError("request body is invalid")
	}
	if _, err := decoder.Token(); err != io.EOF {
		return nil, domain.IdentityValidationError("request body must contain exactly one object")
	}
	for _, field := range fields {
		if _, ok := result[field]; !ok {
			return nil, domain.IdentityValidationError(fmt.Sprintf("%s is required", field))
		}
	}
	return result, nil
}
func decodeFields(body []byte, operation string) (string, error) {
	var fields []string
	switch operation {
	case "register":
		fields = []string{"accountName", "email", "password"}
	case "login":
		fields = []string{"email", "password"}
	case "password":
		fields = []string{"currentPassword", "newPassword"}
	case "create_member":
		fields = []string{"email", "password", "role", "claims"}
	case "update_member":
		fields = []string{"role", "enabled", "claims"}
	case "create_invitation":
		fields = []string{"email", "role", "claims"}
	case "accept_invitation":
		fields = []string{"code"}
	case "switch_account":
		fields = []string{"accountId"}
	case "system_role":
		fields = []string{"role"}
	}
	raw, err := validateFields(body, fields...)
	if err != nil {
		return "", err
	}
	values := make(map[string]string)
	var claims []string
	for field, value := range raw {
		if field == "claims" {
			if err := json.Unmarshal(value, &claims); err != nil {
				return "", domain.IdentityValidationError("claims must be an array of strings")
			}
			continue
		}
		if field == "enabled" {
			var enabled bool
			if err := json.Unmarshal(value, &enabled); err != nil {
				return "", domain.IdentityValidationError("enabled must be a boolean")
			}
			continue
		}
		var decoded string
		if err := json.Unmarshal(value, &decoded); err != nil {
			return "", domain.IdentityValidationError("request fields must be strings")
		}
		values[field] = decoded
	}
	email := ""
	if value, ok := values["email"]; ok {
		email, err = domain.NormalizeEmail(value)
		if err != nil {
			return "", err
		}
	}
	switch operation {
	case "register":
		err = (models.IdentityRegistrationRequest{AccountName: values["accountName"], Email: email, Password: values["password"]}).Validate()
	case "login":
		err = (models.IdentityLoginRequest{Email: email, Password: values["password"]}).Validate()
	case "password":
		err = (models.IdentityPasswordRequest{CurrentPassword: values["currentPassword"], NewPassword: values["newPassword"]}).Validate("")
	case "create_member":
		err = (models.IdentityCreateMemberRequest{Email: email, Password: values["password"], Role: values["role"], Claims: claims}).Validate()
	case "update_member":
		err = (models.IdentityUpdateMemberRequest{Role: values["role"], Claims: claims}).Validate()
	case "create_invitation":
		err = (models.IdentityInvitationRequest{Email: email, Role: values["role"], Claims: claims}).Validate()
	case "switch_account":
		err = (models.IdentitySwitchAccountRequest{AccountID: values["accountId"]}).Validate()
	case "system_role":
		err = (models.IdentitySystemRoleRequest{Role: values["role"]}).Validate()
	}
	return email, err
}
