package architecture_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strings"
	"testing"
)

func TestProductionNamesAndWorkflowLayout(t *testing.T) {
	root := filepath.Join("..", "..", "internal")
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if strings.Contains(relative, "/generated/") || strings.Contains(relative, "/contract/") || strings.HasPrefix(relative, "testdb/") {
			return nil
		}
		file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
		if err != nil {
			return err
		}
		for _, violation := range namingViolations(relative, file) {
			t.Errorf("%s: %s", relative, violation)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

func namingViolations(path string, file *ast.File) []string {
	var violations []string
	if oneOf(filepath.Base(path), "service.go", "datasource.go", "data_source.go", "repository.go", "handler.go", "container.go", "mapper.go", "mapping.go", "workflow.go", "dispatcher.go", "activity.go", "activities.go", "source.go", "remote.go", "local.go", "config.go", "models.go", "types.go") {
		violations = append(violations, "implementation filenames must identify their owner and purpose")
	}
	ast.Inspect(file, func(node ast.Node) bool {
		switch value := node.(type) {
		case *ast.TypeSpec:
			if oneOf(value.Name.Name, "Service", "Repository", "DataSource", "Handler", "Container", "Options", "Source", "Local", "Remote", "Jobs", "Activities", "Dispatcher", "Page", "Record", "Result", "Work", "Metadata", "WorkflowInput", "WorkflowResult", "PageInput", "Mapper", "Config", "Router", "Group", "Guard", "Permission", "Claim", "Actor", "Run", "Failure", "Provider", "Settings", "Subject", "Connection", "connection", "parser", "scanner", "cursor", "cache", "bucket", "limiter") {
				violations = append(violations, "type names must identify their owner and purpose: "+value.Name.Name)
			}
		case *ast.FuncDecl:
			if value.Recv == nil && value.Name.Name == "New" {
				violations = append(violations, "constructors must name the type they construct")
			}
			if value.Recv == nil && strings.HasPrefix(value.Name.Name, "new") && len(value.Name.Name) > 3 && ast.IsExported(value.Name.Name[3:]) && value.Type.Results != nil && len(value.Type.Results.List) > 0 {
				result := value.Type.Results.List[0].Type
				if pointer, ok := result.(*ast.StarExpr); ok {
					result = pointer.X
				}
				if named, ok := result.(*ast.Ident); ok {
					expected := "new" + strings.ToUpper(named.Name[:1]) + named.Name[1:]
					if !strings.HasPrefix(value.Name.Name, expected) {
						violations = append(violations, "private constructors must name the type they construct: "+value.Name.Name)
					}
				}
			}
			if strings.Contains(value.Name.Name, "Mapper") && !strings.HasSuffix(path, ".mapper.go") {
				violations = append(violations, "mapping helpers belong in explicit .mapper.go files")
			}

		}
		return true
	})
	return violations
}

func TestNamingPolicy(t *testing.T) {
	tests := []struct {
		name, path, source string
		valid              bool
	}{
		{"explicit service", "domain/document/services/document_service.go", "package services\ntype DocumentService struct{}\nfunc NewDocumentService() *DocumentService { return nil }", true},
		{"meaningful business value", "domain/document/models/document.model.go", "package models\ntype Document struct{}", true},
		{"generic type", "domain/document/services/document_service.go", "package services\ntype Service struct{}", false},
		{"generic filename", "domain/document/services/service.go", "package services\ntype DocumentService struct{}", false},
		{"generic constructor", "data/document/repos/document_repository.go", "package repos\nfunc New() {}", false},
		{"generic private constructor", "data/identity/security/casbin_identity_authorizer.go", "package security\nfunc newAuthorizer() *CasbinIdentityAuthorizer { return nil }", false},
		{"explicit private constructor", "data/identity/security/casbin_identity_authorizer.go", "package security\nfunc newCasbinIdentityAuthorizer() *CasbinIdentityAuthorizer { return nil }", true},
		{"private type constructor", "presentation/identity/routes/identity_limiter.go", "package routes\nfunc newIdentityRateLimiter() *identityRateLimiter { return nil }", true},
		{"generic lifecycle constructor", "bootstrap/native_worker_lifecycle.go", "package bootstrap\nfunc newWorkerLifecycle() *nativeWorkerLifecycle { return nil }", false},
		{"explicit lifecycle constructor", "bootstrap/native_worker_lifecycle.go", "package bootstrap\nfunc newNativeWorkerLifecycle() *nativeWorkerLifecycle { return nil }", true},
		{"explicit mapper", "data/document/repos/document.mapper.go", "package repos\nfunc documentRecordMapper() {}", true},
		{"misplaced mapper", "data/document/repos/document_repository.go", "package repos\nfunc documentRecordMapper() {}", false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			file, err := parser.ParseFile(token.NewFileSet(), test.path, test.source, 0)
			if err != nil {
				t.Fatal(err)
			}
			violations := namingViolations(test.path, file)
			if (len(violations) == 0) != test.valid {
				t.Fatalf("violations = %v; valid = %t", violations, test.valid)
			}
		})
	}
}
