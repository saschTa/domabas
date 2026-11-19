package jobs

import "context"

type inferencePermitKey struct{}
type InferencePermit func(context.Context, string, func(context.Context) error) error

func WithInferencePermit(ctx context.Context, permit InferencePermit) context.Context {
	return context.WithValue(ctx, inferencePermitKey{}, permit)
}

func RunInference(ctx context.Context, endpoint string, work func(context.Context) error) error {
	if permit, ok := ctx.Value(inferencePermitKey{}).(InferencePermit); ok {
		return permit(ctx, endpoint, work)
	}
	return work(ctx)
}
