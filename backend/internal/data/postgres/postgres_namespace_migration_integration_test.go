//go:build integration

package postgres

import (
	"fmt"
	"testing"
	"testing/fstest"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/google/uuid"
)

func beforeNamespaceMigration(t *testing.T) *PostgresDataSource {
	t.Helper()
	source := migrationSource(t, testdb.New(t))
	files := fstest.MapFS{}
	for _, name := range []string{"001_documents.sql", "002_identity.sql"} {
		contents, err := migrations.ReadFile("migrations/" + name)
		if err != nil {
			t.Fatal(err)
		}
		files["migrations/"+name] = &fstest.MapFile{Data: contents}
	}
	if err := source.migrate(t.Context(), files); err != nil {
		t.Fatal(err)
	}
	return source
}

func namespaceSnapshot(t *testing.T, source *PostgresDataSource, query string) string {
	t.Helper()
	var snapshot string
	if err := source.pool.QueryRow(t.Context(), query).Scan(&snapshot); err != nil {
		t.Fatal(err)
	}
	return snapshot
}

func TestNamespaceMigrationPreservesRetainedAuthorityAndLibraries(t *testing.T) {
	source := beforeNamespaceMigration(t)
	first, orphan := uuid.New(), uuid.New()
	stamp := time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)
	for _, account := range []uuid.UUID{first, orphan} {
		migrationSQL(t, source, "INSERT INTO accounts(id,name,created_at) VALUES($1,$2,$3)", account, "Retained library", stamp)
	}
	type oldMember struct {
		id, account uuid.UUID
		role        string
		enabled     bool
	}
	members := []oldMember{
		{uuid.New(), first, "owner", false},
		{uuid.New(), first, "owner", true},
		{uuid.New(), first, "owner", true},
		{uuid.New(), first, "editor", true},
		{uuid.New(), first, "viewer", false},
		{uuid.New(), orphan, "owner", false},
	}
	for index, member := range members {
		created := stamp.Add(time.Duration(index) * time.Hour)
		migrationSQL(t, source, `INSERT INTO users(id,email,password_hash,credential_revision,must_change_password,created_at) VALUES($1,$2,$3,$4,$5,$6)`, member.id, fmt.Sprintf("retained-%d@example.test", index), fmt.Sprintf("retained-hash-%d", index), index+1, index%2 == 0, created)
		migrationSQL(t, source, `INSERT INTO memberships(account_id,user_id,role,enabled) VALUES($1,$2,$3,$4)`, member.account, member.id, member.role, member.enabled)
		migrationSQL(t, source, `INSERT INTO sessions(digest,account_id,user_id,credential_revision,expires_at,created_at) VALUES($1,$2,$3,$4,$5,$6)`, fmt.Sprintf("%064x", index+1), member.account, member.id, index+1, stamp.AddDate(50, 0, 0), created)
	}
	for _, account := range []any{first, orphan, nil} {
		migrationSQL(t, source, `INSERT INTO documents(id,title,description,created_at,account_id) VALUES($1,'Retained title','Retained content',$2,$3)`, uuid.New(), stamp, account)
	}
	queries := map[string]string{
		"documents": `SELECT jsonb_agg(jsonb_build_array(id,title,description,created_at,account_id) ORDER BY id)::text FROM documents`,
		"sessions":  `SELECT jsonb_agg(to_jsonb(s) ORDER BY digest)::text FROM sessions s`,
		"users":     `SELECT jsonb_agg(jsonb_build_array(id,email,password_hash,credential_revision,must_change_password,created_at) ORDER BY id)::text FROM users`,
		"history":   `SELECT jsonb_agg(to_jsonb(m) ORDER BY version)::text FROM schema_migrations m WHERE version IN ('001_documents.sql','002_identity.sql')`,
	}
	before := make(map[string]string)
	for name, query := range queries {
		before[name] = namespaceSnapshot(t, source, query)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	for name, query := range queries {
		if after := namespaceSnapshot(t, source, query); after != before[name] {
			t.Errorf("namespace migration changed retained %s", name)
		}
	}
	for index, member := range members {
		var personal uuid.UUID
		var systemRole, oldRole, personalRole string
		var enabled, owner, personalEnabled, personalOwner bool
		var claims []string
		if err := source.pool.QueryRow(t.Context(), `SELECT u.personal_account_id,u.system_role,m.role,m.enabled,m.is_owner,m.claims,p.role,p.enabled,p.is_owner FROM users u JOIN memberships m ON m.user_id=u.id AND m.account_id=$2 JOIN memberships p ON p.user_id=u.id AND p.account_id=u.personal_account_id WHERE u.id=$1`, member.id, member.account).Scan(&personal, &systemRole, &oldRole, &enabled, &owner, &claims, &personalRole, &personalEnabled, &personalOwner); err != nil {
			t.Fatal(err)
		}
		expectedRole := map[string]string{"owner": "admin", "editor": "user", "viewer": "viewer"}[member.role]
		if systemRole != "user" || oldRole != expectedRole || enabled != member.enabled || owner != (member.role == "owner") || len(claims) != 0 {
			t.Errorf("retained member %d lost authority/flags or gained system access", index)
		}
		if personalRole != "admin" || !personalEnabled || !personalOwner {
			t.Errorf("retained member %d lacks enabled personal ownership", index)
		}
		if index == 1 {
			if personal != first {
				t.Error("earliest enabled owner did not retain its personal library")
			}
		} else if personal == first || personal == orphan {
			t.Errorf("retained member %d incorrectly reused an existing library", index)
		}
	}
	var eligible bool
	var accounts, memberships, users, personalAccounts int
	if err := source.pool.QueryRow(t.Context(), `SELECT (SELECT bootstrap_eligible FROM identity_setup), (SELECT count(*) FROM accounts), (SELECT count(*) FROM memberships), count(*), count(DISTINCT personal_account_id) FROM users`).Scan(&eligible, &accounts, &memberships, &users, &personalAccounts); err != nil {
		t.Fatal(err)
	}
	if eligible || accounts != 7 || memberships != 11 || users != 6 || personalAccounts != 6 {
		t.Fatalf("retained setup mismatch: eligible=%v accounts=%d memberships=%d users=%d personal=%d", eligible, accounts, memberships, users, personalAccounts)
	}
	if _, err := source.pool.Exec(t.Context(), `UPDATE users SET personal_account_id=$1 WHERE id=$2`, uuid.New(), members[0].id); err == nil {
		t.Error("personal selection without a matching membership was accepted")
	}
	for name, value := range map[string]string{
		"null element": `ARRAY[NULL]::text[]`,
		"nested":       `ARRAY[['documents:read','documents:create']]::text[]`,
		"oversized":    `array_fill('documents:read'::text,ARRAY[33])`,
		"long id":      `ARRAY[repeat('x',65)]::text[]`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := source.pool.Exec(t.Context(), `UPDATE memberships SET claims=`+value+` WHERE user_id=$1 AND account_id=$2`, members[1].id, first); err == nil {
				t.Fatal("invalid stored claim array was accepted")
			}
		})
	}
}

func TestNamespaceMigrationRequiresTrulyEmptyBusinessDataForBootstrap(t *testing.T) {
	for _, retained := range []string{"empty", "quarantined document", "account only"} {
		t.Run(retained, func(t *testing.T) {
			source := beforeNamespaceMigration(t)
			switch retained {
			case "quarantined document":
				migrationSQL(t, source, `INSERT INTO documents(id,title,description,created_at) VALUES($1,'Quarantined','Unowned',now())`, uuid.New())
			case "account only":
				migrationSQL(t, source, `INSERT INTO accounts(id,name) VALUES($1,'Retained account')`, uuid.New())
			}
			if err := source.Migrate(t.Context()); err != nil {
				t.Fatal(err)
			}
			var eligible bool
			if err := source.pool.QueryRow(t.Context(), `SELECT bootstrap_eligible FROM identity_setup`).Scan(&eligible); err != nil {
				t.Fatal(err)
			}
			if eligible != (retained == "empty") {
				t.Fatalf("bootstrap eligibility=%v for %s", eligible, retained)
			}
			if retained != "empty" {
				migrationSQL(t, source, `DELETE FROM documents`)
				migrationSQL(t, source, `DELETE FROM accounts`)
				if err := source.Migrate(t.Context()); err != nil {
					t.Fatal(err)
				}
				if err := source.pool.QueryRow(t.Context(), `SELECT bootstrap_eligible FROM identity_setup`).Scan(&eligible); err != nil || eligible {
					t.Fatalf("retained eligibility reset after emptiness: %v %v", eligible, err)
				}
			}
		})
	}
}
