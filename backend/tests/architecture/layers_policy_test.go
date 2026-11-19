package architecture_test

import (
	"go/parser"
	"go/token"
	"strconv"
	"strings"
	"testing"
)

func TestBoundaryPolicy(t *testing.T) {
	tests := []struct{ name, path, dependency, want string }{
		{"sibling container", "bootstrap/identity/container.go", "bootstrap/document", "cannot import root bootstrap or sibling"},
		{"root from nested container", "bootstrap/document/wiring/container.go", "bootstrap", "cannot import root bootstrap or sibling"},
		{"foreign service from container", "bootstrap/identity/container.go", "domain/document/services", "cannot construct foreign"},
		{"foreign data from container", "bootstrap/identity/container.go", "data/document/repos", "cannot construct foreign"},
		{"foreign source from container", "bootstrap/identity/container.go", "data/document/datasources", "cannot construct foreign"},
		{"foreign HTTP from container", "bootstrap/identity/container.go", "presentation/document/handlers", "cannot construct foreign"},
		{"root HTTP from container", "bootstrap/document/container.go", "presentation/httpapi", "cannot import root HTTP"},
		{"service constructs data", "domain/document/services/service.go", "data/document/repos", "core cannot import adapters"},
		{"model imports own service", "domain/document/models/document.model.go", "domain/document/services", "models and interfaces cannot depend"},
		{"model imports own interface", "domain/document/models/document.model.go", "domain/document/interfaces", "models and interfaces cannot depend"},
		{"interface imports own service", "domain/document/interfaces/repository.go", "domain/document/services", "models and interfaces cannot depend"},
		{"foreign service from service", "domain/identity/services/service.go", "domain/document/services/nested", "local service ports"},
		{"foreign renamed repository from service", "domain/identity/services/service.go", "domain/document/interfaces", "local service ports"},
		{"own repository port", "domain/document/services/service.go", "domain/document/interfaces", ""},
		{"own nested service", "domain/document/services/service.go", "domain/document/services/validation", ""},
		{"foreign service value models", "domain/identity/interfaces/document.go", "domain/document/models", ""},
		{"model nested values", "domain/identity/models/identity.model.go", "domain/identity/models/userroles", ""},
		{"model HTTP dependency", "domain/document/models/document.model.go", "net/http", "core imports infrastructure"},
		{"service SQL dependency", "domain/document/services/service.go", "database/sql", "core imports infrastructure"},
		{"service external dependency", "domain/document/services/service.go", "github.com/google/uuid", "core imports infrastructure"},
		{"model environment dependency", "domain/identity/models/identity.model.go", "os", "core imports infrastructure"},
		{"data imports core service", "data/document/repos/document.repo.go", "domain/document/services", "cannot import core services"},
		{"data imports foreign core port", "data/identity/repos/identity.repo.go", "domain/document/interfaces", "cannot import core services"},
		{"data implements own port", "data/document/repos/document.repo.go", "domain/document/interfaces", ""},
		{"security implements own port", "data/identity/security/passwords.go", "domain/identity/interfaces", ""},
		{"security reads own values", "data/identity/security/authorizer.go", "domain/identity/models", ""},
		{"security cannot consume foreign values", "data/identity/security/authorizer.go", "domain/document/models", "cannot import core services"},
		{"data cannot import HTTP", "data/document/repos/document.repo.go", "presentation/document/handlers", "another implementation layer"},
		{"data cannot import bootstrap", "data/document/datasources/document.pg.go", "bootstrap/document", "another implementation layer"},
		{"source shared schema join", "data/document/datasources/document.pg.go", "data/postgres/generated/table", ""},
		{"repository foreign data values", "data/document/repos/document.repo.go", "data/identity/models", ""},
		{"source foreign data values", "data/document/datasources/document.pg.go", "data/identity/models/nested", ""},
		{"source foreign concrete repository", "data/document/datasources/document.pg.go", "data/identity/repos", "not foreign concrete adapters"},
		{"repository foreign concrete source", "data/document/repos/document.repo.go", "data/identity/datasources", "not foreign concrete adapters"},
		{"data models cannot join domains", "data/document/models/document.pg.model.go", "data/identity/models", "not foreign concrete adapters"},
		{"security cannot join domains", "data/identity/security/authorizer.go", "data/document/models", "not foreign concrete adapters"},
		{"data model cannot import own source", "data/document/models/document.pg.model.go", "data/document/datasources", "models cannot import adapter"},
		{"data model cannot import core ports", "data/document/models/document.pg.model.go", "domain/document/interfaces", "cannot import core services"},
		{"shared pool cannot import domain adapters", "data/postgres/datasource.go", "data/document/datasources", "shared data infrastructure"},
		{"shared pool cannot import core values", "data/postgres/datasource.go", "domain/document/models", "shared data infrastructure"},
		{"source borrows pool capability", "data/document/datasources/document.pg.go", "data/postgres", ""},
		{"data model uses generated rows", "data/document/models/document.pg.model.go", "data/postgres/generated/model", ""},
		{"data model cannot access shared pool", "data/document/models/document.pg.model.go", "data/postgres", "not shared storage implementations"},
		{"data model cannot execute shared queries", "data/document/models/document.pg.model.go", "data/postgres/generated/table", "not shared storage implementations"},
		{"Jet from root bootstrap", "bootstrap/app.go", "github.com/go-jet/jet/v2/postgres", "Jet and generated database"},
		{"Jet from security", "data/identity/security/passwords.go", "github.com/go-jet/jet/v2/postgres", "Jet and generated database"},
		{"Jet from data models", "data/document/models/document.pg.model.go", "github.com/go-jet/jet/v2/postgres", "query builders belong in data sources"},
		{"Jet from repository", "data/document/repos/document.repo.go", "github.com/go-jet/jet/v2/postgres", "query builders belong in data sources"},
		{"query table from repository", "data/document/repos/document.repo.go", "data/postgres/generated/table", "query builders belong in data sources"},
		{"generated rows from container", "bootstrap/document/container.go", "data/postgres/generated/model", "Jet and generated database"},
		{"generated rows from HTTP", "presentation/document/models/request.model.go", "data/postgres/generated/model", "Jet and generated database"},
		{"HTTP cannot construct storage", "presentation/httpapi/handler.go", "data/postgres", "presentation consumes service ports"},
		{"HTTP cannot import own service", "presentation/document/handlers/handler.go", "domain/document/services", "presentation consumes service ports"},
		{"HTTP cannot acquire own repository", "presentation/document/handlers/handler.go", "domain/document/interfaces", "presentation consumes service ports"},
		{"HTTP foreign core values", "presentation/document/handlers/service.go", "domain/identity/models", ""},
		{"sibling HTTP domain", "presentation/identity/handlers/handler.go", "presentation/document/handlers", "sibling domain presentation"},
		{"nested sibling HTTP domain", "presentation/identity/routes/nested/routes.go", "presentation/document/models/nested", "sibling domain presentation"},
		{"HTTP model imports handler", "presentation/document/models/request.model.go", "presentation/document/handlers", "models cannot import handlers"},
		{"HTTP model imports route", "presentation/identity/models/request.model.go", "presentation/identity/routes", "models cannot import handlers"},
		{"HTTP handler imports route", "presentation/identity/handlers/handler.go", "presentation/identity/routes", "handlers cannot import route"},
		{"domain imports root HTTP", "presentation/document/routes/routes.go", "presentation/httpapi", "cannot import root composition"},
		{"shared routing imports domain", "presentation/httpapi/routing/router.go", "presentation/document/routes", "shared HTTP helpers"},
		{"nested shared transport imports domain", "presentation/httpapi/transport/json/helpers.go", "presentation/identity/handlers", "shared HTTP helpers"},
		{"generated contract imports domain", "presentation/httpapi/contract/api.gen.go", "presentation/document/models", "shared HTTP helpers"},
		{"shared transport imports root", "presentation/httpapi/transport/json.go", "presentation/httpapi", "shared HTTP helpers"},
		{"shared guard identity values", "presentation/httpapi/transport/guard.go", "domain/identity/models", ""},
		{"shared routing cannot depend on business values", "presentation/httpapi/routing/router.go", "domain/document/models", "only use identity values"},
		{"generated HTTP cannot depend on core values", "presentation/httpapi/contract/api.gen.go", "domain/identity/models", "only use identity values"},
		{"shared transport cannot depend on document values", "presentation/httpapi/transport/json.go", "domain/document/models", "only use identity values"},
		{"root HTTP composes handlers", "presentation/httpapi/handler.go", "presentation/document/handlers", ""},
		{"root HTTP composes routes", "presentation/httpapi/router.go", "presentation/identity/routes", ""},
		{"root HTTP composes shared helpers", "presentation/httpapi/router.go", "presentation/httpapi/routing", ""},
		{"own HTTP request values", "presentation/document/handlers/handler.go", "presentation/document/models", ""},
		{"own HTTP model generated boundary", "presentation/identity/models/response.model.go", "presentation/httpapi/contract", ""},
		{"own HTTP registration transport", "presentation/identity/routes/routes.go", "presentation/httpapi/transport", ""},
		{"own HTTP registration handlers", "presentation/document/routes/routes.go", "presentation/document/handlers", ""},
		{"HTTP pgx dependency", "presentation/document/handlers/handler.go", "github.com/jackc/pgx/v5", "SQL dependencies belong"},
		{"own source pgx dependency", "data/document/datasources/document.pg.go", "github.com/jackc/pgx/v5", ""},
		{"worker rejects external orchestration SDK", "bootstrap/app.go", "go.temporal.io/sdk/worker", "workers must run natively"},
		{"core cannot depend on native executor", "domain/chat/services/chat.go", "data/jobs", "core cannot import adapters"},
		{"configuration helper dependency", "config/config.go", "config/values", ""},
		{"configuration domain escape", "config/config.go", "domain/document/services", "configuration cannot depend"},
		{"test helper domain escape", "testdb/database.go", "data/document/repos", "test database helpers"},
		{"root composes containers", "bootstrap/app.go", "bootstrap/document", ""},
		{"root composes services", "bootstrap/app.go", "domain/identity/services", ""},
		{"own container source", "bootstrap/document/container.go", "data/document/datasources", ""},
		{"own container service", "bootstrap/identity/container.go", "domain/identity/services", ""},
		{"legacy application import rejected", "bootstrap/document/container.go", "application/document", "unsupported package layout"},
		{"legacy domain import rejected", "domain/document/services/service.go", "domain/document", "unsupported package layout"},
		{"legacy HTTP domain import rejected", "presentation/httpapi/handler.go", "presentation/httpapi/document", "unsupported package layout"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			dependency := test.dependency
			if oneOf(strings.Split(dependency, "/")[0], "domain", "data", "presentation", "bootstrap", "application", "config", "testdb") {
				dependency = internalPrefix + dependency
			}
			assertPolicy(t, test.path, "package fixture\nimport "+strconv.Quote(dependency), test.want)
		})
	}
}

func TestForbiddenImportsCannotHideBehindNames(t *testing.T) {
	tests := []struct{ path, dependency string }{
		{"domain/identity/services/nested/service.go", "domain/document/interfaces"},
		{"domain/identity/services/nested/service.go", "domain/document/services/nested"},
		{"domain/document/models/nested/value.model.go", "domain/document/interfaces"},
		{"domain/document/interfaces/repository.go", "domain/document/services"},
		{"data/document/repos/nested/source.go", "data/identity/datasources"},
		{"data/document/datasources/document.pg.go", "data/identity/repos"},
		{"data/document/repos/document.repo.go", "domain/identity/interfaces"},
		{"presentation/document/handlers/handler.go", "domain/document/services"},
		{"presentation/document/handlers/handler.go", "domain/document/interfaces"},
		{"presentation/httpapi/transport/guard.go", "presentation/identity/handlers"},
		{"data/postgres/nested/storage.go", "data/identity/repos"},
		{"bootstrap/document/wiring/container.go", "bootstrap/identity"},
	}
	for _, test := range tests {
		for _, alias := range []string{"", "renamed ", ". ", "_ "} {
			t.Run(test.path+"/"+test.dependency+"/"+alias, func(t *testing.T) {
				source := "package fixture\nimport " + alias + strconv.Quote(internalPrefix+test.dependency)
				file, err := parser.ParseFile(token.NewFileSet(), test.path, source, 0)
				if err != nil {
					t.Fatal(err)
				}
				if len(boundaryViolations(test.path, file)) != 1 {
					t.Fatal("forbidden package import escaped ownership checks")
				}
			})
		}
	}
}

func TestConsumerOwnedCollaborationPorts(t *testing.T) {
	assertPolicy(t, "domain/identity/interfaces/documents.go", `package interfaces
import (
	"context"
	documents "github.com/domabas/domabas/backend/internal/domain/document/models"
)
type Documents interface { Get(context.Context, string, string) (documents.Document, error) }
`, "")
	assertPolicy(t, "data/document/repos/accounts.go", `package repos
import (
	"context"
	accounts "github.com/domabas/domabas/backend/internal/data/identity/models"
)
type AccountReader interface { Read(context.Context, string) (accounts.IdentityRecord, error) }
type Repository struct { accounts AccountReader }
`, "")
}

func assertPolicy(t *testing.T, path, source, want string) {
	t.Helper()
	file, err := parser.ParseFile(token.NewFileSet(), path, source, 0)
	if err != nil {
		t.Fatal(err)
	}
	violations := boundaryViolations(path, file)
	if want == "" {
		if len(violations) != 0 {
			t.Fatalf("valid dependency rejected: %v", violations)
		}
	} else if len(violations) != 1 || !strings.Contains(violations[0], want) {
		t.Fatalf("violations = %v; want one containing %q", violations, want)
	}
}
