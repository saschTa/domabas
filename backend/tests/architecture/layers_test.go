package architecture_test

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

const internalPrefix = "github.com/domabas/domabas/backend/internal/"

func TestProductionImportsRespectLayerBoundaries(t *testing.T) {
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
		for _, violation := range boundaryViolations(filepath.ToSlash(relative), file) {
			t.Errorf("%s: %s", relative, violation)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

type packageBoundary struct{ layer, owner, role string }

func classifyPackage(path string) packageBoundary {
	parts := strings.Split(path, "/")
	if strings.HasSuffix(parts[len(parts)-1], ".go") {
		parts = parts[:len(parts)-1]
	}
	if len(parts) == 0 {
		return packageBoundary{}
	}
	result := packageBoundary{layer: parts[0]}
	if len(parts) < 2 {
		return result
	}
	switch result.layer {
	case "bootstrap", "domain":
		result.owner = parts[1]
	case "data":
		if parts[1] == "postgres" || parts[1] == "temporal" {
			result.role = parts[1]
			return result
		}
		result.owner = parts[1]
	case "presentation":
		if parts[1] == "httpapi" {
			result.role = "httpapi"
			if len(parts) > 2 {
				result.role = parts[2]
			}
			return result
		}
		result.owner = parts[1]
	}
	if len(parts) > 2 {
		result.role = parts[2]
	}
	return result
}

func locationViolation(location packageBoundary) string {
	switch location.layer {
	case "domain":
		if location.owner == "" || !oneOf(location.role, "models", "interfaces", "services", "workflows") {
			return "domain code belongs in its owner's models, interfaces, services or workflows packages"
		}
	case "data":
		if location.owner == "" {
			if !oneOf(location.role, "postgres", "temporal") {
				return "shared data packages need explicit infrastructure ownership"
			}
		} else if !oneOf(location.role, "models", "repos", "datasources", "security", "temporal") {
			return "domain data code needs an explicit adapter role"
		}
	case "presentation":
		if location.owner == "" {
			if !oneOf(location.role, "httpapi", "contract", "routing", "transport") {
				return "shared HTTP packages need explicit composition or helper ownership"
			}
		} else if !oneOf(location.role, "models", "handlers", "routes") {
			return "domain presentation code needs an explicit adapter role"
		}
	case "bootstrap", "config", "testdb":
	default:
		return "unrecognized backend layer: " + location.layer
	}
	return ""
}

func oneOf(value string, options ...string) bool {
	for _, option := range options {
		if value == option {
			return true
		}
	}
	return false
}

func boundaryViolations(relative string, file *ast.File) []string {
	location := classifyPackage(relative)
	if violation := locationViolation(location); violation != "" {
		return []string{violation}
	}
	var violations []string
	for _, spec := range file.Imports {
		importPath, err := strconv.Unquote(spec.Path.Value)
		if err != nil {
			violations = append(violations, fmt.Sprintf("invalid import path: %v", err))
			continue
		}
		if violation := importViolation(location, importPath); violation != "" {
			violations = append(violations, violation+": "+importPath)
		}
	}
	return violations
}

func importViolation(source packageBoundary, importPath string) string {
	if source.layer == "data" && source.role == "models" && (importPath == internalPrefix+"data/postgres" || strings.HasPrefix(importPath, internalPrefix+"data/postgres/")) && !(importPath == internalPrefix+"data/postgres/generated/model" || strings.HasPrefix(importPath, internalPrefix+"data/postgres/generated/model/")) {
		return "data models may use generated row records, not shared storage implementations"
	}
	queryBuilder := strings.HasPrefix(importPath, "github.com/go-jet/jet/") || importPath == internalPrefix+"data/postgres/generated/table" || strings.HasPrefix(importPath, internalPrefix+"data/postgres/generated/table/")
	if queryBuilder && !(source.layer == "data" && oneOf(source.role, "postgres", "datasources")) {
		return "Jet and generated database query builders belong in data sources"
	}
	generatedDatabase := strings.HasPrefix(importPath, internalPrefix+"data/postgres/generated/")
	if strings.HasPrefix(importPath, "github.com/go-jet/jet/") || generatedDatabase {
		if source.layer != "data" || !oneOf(source.role, "postgres", "models", "repos", "datasources") {
			return "Jet and generated database models belong in data persistence adapters"
		}
	}
	if strings.HasPrefix(importPath, "go.temporal.io/") {
		if source.layer == "domain" && source.role == "workflows" {
			if !oneOf(importPath, "go.temporal.io/sdk/workflow", "go.temporal.io/sdk/temporal") {
				return "domain workflows use only deterministic Temporal workflow and error APIs"
			}
			return ""
		}
		if source.layer != "bootstrap" && !(source.layer == "data" && source.role == "temporal") {
			return "Temporal SDK belongs in Temporal adapters or composition"
		}
	}
	if !strings.HasPrefix(importPath, internalPrefix) {
		if source.layer == "domain" && source.role == "workflows" {
			if !oneOf(importPath, "errors", "fmt", "time", "strings", "strconv", "math", "math/bits", "sort", "slices", "cmp", "unicode", "unicode/utf8") {
				return "domain workflows cannot import I/O or external infrastructure"
			}
			return ""
		}
		if source.layer == "domain" && (strings.Contains(strings.Split(importPath, "/")[0], ".") || strings.HasPrefix(importPath, "net/http") || strings.HasPrefix(importPath, "database/") || importPath == "os") {
			return "core imports infrastructure"
		}
		if (strings.HasPrefix(importPath, "github.com/jackc/pgx/") || strings.HasPrefix(importPath, "database/")) && !oneOf(source.layer, "data", "bootstrap", "testdb") {
			return "SQL dependencies belong in data adapters or composition"
		}
		return ""
	}
	dependency := classifyPackage(strings.TrimPrefix(importPath, internalPrefix))
	if violation := locationViolation(dependency); violation != "" {
		return "dependency uses an unsupported package layout"
	}
	switch source.layer {
	case "bootstrap":
		return bootstrapImportViolation(source, dependency)
	case "domain":
		return coreImportViolation(source, dependency)
	case "data":
		return dataImportViolation(source, dependency)
	case "presentation":
		return presentationImportViolation(source, dependency)
	case "config":
		if dependency.layer != "config" {
			return "configuration cannot depend on domain implementations"
		}
	case "testdb":
		if dependency.layer != "testdb" && !(dependency.layer == "data" && dependency.owner == "" && dependency.role == "postgres") {
			return "test database helpers cannot depend on domain implementations"
		}
	}
	return ""
}

func bootstrapImportViolation(source, dependency packageBoundary) string {
	if source.owner == "" {
		return ""
	}
	if dependency.layer == "bootstrap" && dependency.owner != source.owner {
		return "domain containers cannot import root bootstrap or sibling containers"
	}
	if dependency.owner != "" && dependency.owner != source.owner {
		if dependency.layer != "domain" || dependency.role != "models" {
			return "domain containers cannot construct foreign domain implementations or ports"
		}
	}
	if dependency.layer == "presentation" && dependency.owner == "" && dependency.role == "httpapi" {
		return "domain containers cannot import root HTTP composition"
	}
	return ""
}

func coreImportViolation(source, dependency packageBoundary) string {
	if source.role == "workflows" {
		if dependency.layer == "domain" && dependency.role == "models" {
			return ""
		}
		return "domain workflows consume only core values, not services or other adapters"
	}
	if dependency.layer != "domain" {
		return "core cannot import adapters or composition"
	}
	if dependency.role == "models" {
		return ""
	}
	if dependency.role == "workflows" {
		return "pure core cannot import workflow adapters"
	}
	if dependency.owner != source.owner {
		return "foreign domain interfaces and services must be consumed through local service ports"
	}
	if source.role == "models" || (source.role == "interfaces" && dependency.role == "services") {
		return "core models and interfaces cannot depend on implementation roles"
	}
	return ""
}

func dataImportViolation(source, dependency packageBoundary) string {
	if dependency.layer == "domain" {
		if source.owner == "" {
			return "shared data infrastructure cannot depend on business domains"
		}
		if source.role == "temporal" && dependency.owner == source.owner && dependency.role == "workflows" {
			return ""
		}
		if dependency.role == "models" && source.role != "models" {
			if source.owner == dependency.owner || oneOf(source.role, "repos", "datasources", "temporal") {
				return ""
			}
		}
		if dependency.role == "interfaces" && dependency.owner == source.owner && oneOf(source.role, "repos", "security") {
			return ""
		}
		return "data adapters cannot import core services or foreign core ports"
	}
	if source.role == "temporal" && source.owner != "" {
		if dependency.layer == "data" && dependency.owner == source.owner && dependency.role == "temporal" {
			return ""
		}
		return "domain Temporal activities and dispatchers use injected ports, not concrete adapters"
	}
	if dependency.layer != "data" {
		return "data adapters cannot import another implementation layer"
	}
	if source.owner == "" {
		if dependency.owner != "" || source.role != dependency.role {
			return "shared data infrastructure cannot import domain adapters or sibling infrastructure"
		}
		return ""
	}
	if dependency.owner == "" {
		if dependency.role != "postgres" || source.role == "security" {
			return "domain data adapters may borrow only relevant shared storage infrastructure"
		}
		return ""
	}
	if dependency.owner != source.owner {
		if oneOf(source.role, "repos", "datasources") && dependency.role == "models" {
			return ""
		}
		return "cross-domain data joins use value records and injected ports, not foreign concrete adapters"
	}
	if source.role == "models" && dependency.role != "models" {
		return "data models cannot import adapter implementations"
	}
	if dependency.role == "temporal" && source.role != "temporal" {
		return "data persistence and security adapters cannot import Temporal implementations"
	}
	return ""
}

func presentationImportViolation(source, dependency packageBoundary) string {
	if dependency.layer == "domain" && dependency.role == "models" {
		if source.owner == "" && source.role != "httpapi" && !(source.role == "transport" && dependency.owner == "identity") {
			return "shared HTTP helpers only use identity values for transport guards"
		}
		return ""
	}
	if dependency.layer != "presentation" {
		return "presentation consumes service ports and core values, not implementation layers"
	}
	if source.owner == "" {
		if source.role == "httpapi" {
			if dependency.owner == "" || oneOf(dependency.role, "handlers", "routes") {
				return ""
			}
			return "root HTTP composes domain HTTP handlers and routes only"
		}
		if dependency.owner != "" || dependency.role == "httpapi" {
			return "shared HTTP helpers cannot import domain modules or root composition"
		}
		return ""
	}
	if dependency.owner == "" {
		if dependency.role == "httpapi" {
			return "domain presentation cannot import root composition or a foreign transport"
		}
		return ""
	}
	if source.owner != dependency.owner {
		return "domain presentation cannot import sibling domain presentation"
	}
	if source.role == "models" && dependency.role != "models" {
		return "presentation models cannot import handlers or routes"
	}
	if source.role == "handlers" && dependency.role == "routes" {
		return "handlers cannot import route registration"
	}
	return ""
}
