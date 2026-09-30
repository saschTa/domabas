package models

import (
	"context"
	"net/http"
)

type realtimeRequestKey struct{}

func WithRequest(ctx context.Context, r *http.Request) context.Context {
	return context.WithValue(ctx, realtimeRequestKey{}, r)
}
func Request(ctx context.Context) *http.Request {
	r, _ := ctx.Value(realtimeRequestKey{}).(*http.Request)
	return r
}
