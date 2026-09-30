package models

import (
	"context"
	"time"
)

type IdentitySessionRequest struct {
	Browser       bool
	Secure        bool
	HasCredential bool
	Token         string
	Now           time.Time
}

type identitySessionRequestKey struct{}

func WithSessionRequest(ctx context.Context, request IdentitySessionRequest) context.Context {
	return context.WithValue(ctx, identitySessionRequestKey{}, request)
}

func CurrentSessionRequest(ctx context.Context) IdentitySessionRequest {
	request, _ := ctx.Value(identitySessionRequestKey{}).(IdentitySessionRequest)
	return request
}
