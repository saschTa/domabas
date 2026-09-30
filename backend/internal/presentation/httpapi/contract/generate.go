package contract

//go:generate go tool oapi-codegen -config ../../../../../contracts/backend/oapi-codegen.yaml ../../../../../contracts/backend/openapi.yaml
//go:generate bun --no-env-file ../../../../../scripts/generation/generated-comments.ts api.gen.go
//go:generate gofmt -w api.gen.go
