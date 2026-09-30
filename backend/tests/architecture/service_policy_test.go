package architecture_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestServicePolicyDoesNotReturnToPersistence(t *testing.T) {
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
		file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
		if err != nil {
			return err
		}
		for _, violation := range servicePolicyViolations(filepath.ToSlash(relative), file) {
			t.Errorf("%s: %s", relative, violation)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

func servicePolicyViolations(path string, file *ast.File) []string {
	location := classifyPackage(path)
	var violations []string
	if location.layer == "data" && oneOf(location.role, "datasources", "repos") && location.owner != "postgres" && location.owner != "temporal" {
		ast.Inspect(file, func(node ast.Node) bool {
			switch value := node.(type) {
			case *ast.SelectorExpr:
				if oneOf(value.Sel.Name, "IdentityAuthorizer", "IdentityAuthorityPolicy", "AllowsAuthority", "CanDelegate", "HasPermission", "ResolveAuthority", "ResolveBackgroundAuthority", "ValidateSession") {
					violations = append(violations, "authority decisions belong in services, not persistence")
				}
				for _, prefix := range []string{"PlanDocument", "PlanEmail", "PlanChat", "PlanPaperless", "PlanIdentity", "PlanInvoice"} {
					if strings.HasPrefix(value.Sel.Name, prefix) {
						violations = append(violations, "services must produce transition plans before persistence applies them")
						break
					}
				}
			case *ast.BasicLit:
				if value.Kind == token.STRING {
					literal, err := strconv.Unquote(value.Value)
					if err != nil {
						return true
					}
					for _, prefix := range []string{"documents:", "system:", "users:", "email:", "chat:", "paperless:", "invoices:", "activity:", "realtime:"} {
						if strings.HasPrefix(literal, prefix) && !strings.ContainsAny(literal, " \n\t") {
							violations = append(violations, "persistence must not select required claim strings")
							break
						}
					}
				}
			}
			return true
		})
	}
	if location.layer == "domain" && location.role == "services" {
		ast.Inspect(file, func(node ast.Node) bool {
			structure, ok := node.(*ast.StructType)
			if !ok {
				return true
			}
			for _, field := range structure.Fields.List {
				if len(field.Names) > 0 {
					continue
				}
				name := ""
				switch value := field.Type.(type) {
				case *ast.SelectorExpr:
					name = value.Sel.Name
				case *ast.Ident:
					name = value.Name
				}
				if strings.HasSuffix(name, "Repository") {
					violations = append(violations, "services must use named repository fields and explicit entry points")
				}
			}
			return true
		})
	}
	return violations
}

func TestServicePolicyChecksRecognizeBypassesAndAllowScopedCommands(t *testing.T) {
	cases := []struct {
		path, source string
		deny         bool
	}{
		{"data/document/datasources/document_source.go", `package datasources; func check(){policy.AllowsAuthority()}`, true},
		{"data/document/repos/document_repository.go", `package repos; const claim="documents:read"`, true},
		{"data/email/datasources/email_source.go", `package datasources; func check(){service.ResolveBackgroundAuthority()}`, true},
		{"data/email/datasources/email_source.go", `package datasources; type EmailDataSource struct{policy p.IdentityAuthorizer}`, true},
		{"data/document/datasources/document_source.go", `package datasources; func apply(){m.PlanDocumentExecutionRecovery()}`, true},
		{"domain/chat/services/chat_service.go", `package services; type ChatService struct{p.ChatRepository}`, true},
		{"domain/chat/services/chat_service.go", `package services; type ChatService struct{repository p.ChatRepository}`, false},
		{"data/document/datasources/document_source.go", `package datasources; func apply(){store.CompareRevision(expected)}`, false},
		{"data/identity/security/identity_policy.go", `package security; func check(){policy.AllowsAuthority()}`, false},
	}
	for _, test := range cases {
		file, err := parser.ParseFile(token.NewFileSet(), test.path, test.source, 0)
		if err != nil {
			t.Fatal(err)
		}
		got := servicePolicyViolations(test.path, file)
		if (len(got) > 0) != test.deny {
			t.Errorf("%s: %v", test.path, got)
		}
	}
}
