//go:build integration

package postgres

import (
	"context"
	"net/url"
	"strings"
	"sync"
	"testing"
	"testing/fstest"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
)

func migrationSource(t *testing.T, databaseURL string) *PostgresDataSource {
	t.Helper()
	source, err := NewPostgresDataSource(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(source.Close)
	return source
}

func migrationSQL(t *testing.T, source *PostgresDataSource, sql string, args ...any) {
	t.Helper()
	if _, err := source.pool.Exec(t.Context(), sql, args...); err != nil {
		t.Fatal(err)
	}
}

func migrationFiles(t *testing.T, extra map[string]string) fstest.MapFS {
	t.Helper()
	original, err := migrations.ReadFile("migrations/001_documents.sql")
	if err != nil {
		t.Fatal(err)
	}
	files := fstest.MapFS{"migrations/001_documents.sql": {Data: original}}
	for name, sql := range extra {
		files["migrations/"+name] = &fstest.MapFile{Data: []byte(sql)}
	}
	return files
}

func legacyLedger(t *testing.T, source *PostgresDataSource, applied bool) time.Time {
	t.Helper()
	migrationSQL(t, source, `CREATE TABLE schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`)
	stamp := time.Date(2020, 2, 3, 4, 5, 6, 0, time.UTC)
	if applied {
		files := migrationFiles(t, nil)
		migrationSQL(t, source, string(files["migrations/001_documents.sql"].Data))
		migrationSQL(t, source, `INSERT INTO schema_migrations VALUES ('001_documents.sql', $1)`, stamp)
		migrationSQL(t, source, `INSERT INTO documents VALUES ('00000000-0000-4000-8000-000000000001', 'retained', 'data', $1)`, stamp)
	}
	return stamp
}

func TestMigrationFreshRepeatedAndConcurrentSources(t *testing.T) {
	databaseURL := testdb.New(t)
	var workers sync.WaitGroup
	for range 3 {
		source := migrationSource(t, databaseURL)
		workers.Go(func() {
			if err := source.Migrate(t.Context()); err != nil {
				t.Errorf("migrate: %v", err)
			}
		})
	}
	workers.Wait()
	source := migrationSource(t, databaseURL)
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := source.pool.QueryRow(t.Context(), `SELECT count(*) FROM schema_migrations WHERE checksum = $1`, originalMigrationChecksum).Scan(&count); err != nil || count != 1 {
		t.Fatalf("history count %d: %v", count, err)
	}
}

func TestMigrationLegacyUpgradePreservesRecords(t *testing.T) {
	for _, applied := range []bool{false, true} {
		t.Run(map[bool]string{false: "empty", true: "applied"}[applied], func(t *testing.T) {
			source := migrationSource(t, testdb.New(t))
			stamp := legacyLedger(t, source, applied)
			if err := source.Migrate(t.Context()); err != nil {
				t.Fatal(err)
			}
			if err := source.Migrate(t.Context()); err != nil {
				t.Fatal(err)
			}
			if applied {
				var recorded time.Time
				var title string
				if err := source.pool.QueryRow(t.Context(), `SELECT applied_at FROM schema_migrations WHERE version = '001_documents.sql'`).Scan(&recorded); err != nil || !recorded.Equal(stamp) {
					t.Fatalf("legacy timestamp changed: %v %v", recorded, err)
				}
				if err := source.pool.QueryRow(t.Context(), `SELECT title FROM documents`).Scan(&title); err != nil || title != "retained" {
					t.Fatalf("legacy data changed: %s %v", title, err)
				}
			}
		})
	}
}

func TestMigrationRejectsCorruptHistory(t *testing.T) {
	cases := map[string]string{
		"checksum": `UPDATE schema_migrations SET checksum = 'changed'`,
		"unknown":  `INSERT INTO schema_migrations(version, checksum) VALUES ('002_unknown.sql', 'unknown')`,
		"renamed":  `UPDATE schema_migrations SET version = '001_renamed.sql' WHERE version = '001_documents.sql'`,
		"null":     `ALTER TABLE schema_migrations ALTER COLUMN checksum DROP NOT NULL; UPDATE schema_migrations SET checksum = NULL`,
	}
	for name, corrupt := range cases {
		t.Run(name, func(t *testing.T) {
			source := migrationSource(t, testdb.New(t))
			if err := source.Migrate(t.Context()); err != nil {
				t.Fatal(err)
			}
			migrationSQL(t, source, corrupt)
			if err := source.Migrate(t.Context()); err == nil {
				t.Fatal("accepted corrupt history")
			}
		})
	}
	for name, sql := range map[string]string{
		"unknown legacy":      `INSERT INTO schema_migrations VALUES ('002_unknown.sql', now())`,
		"nullable timestamp":  `ALTER TABLE schema_migrations ALTER COLUMN applied_at DROP NOT NULL`,
		"wrong default":       `ALTER TABLE schema_migrations ALTER COLUMN applied_at SET DEFAULT '2020-01-01'::timestamptz`,
		"missing primary key": `ALTER TABLE schema_migrations DROP CONSTRAINT schema_migrations_pkey`,
		"extra column":        `ALTER TABLE schema_migrations ADD COLUMN unexpected text`,
	} {
		t.Run(name, func(t *testing.T) {
			source := migrationSource(t, testdb.New(t))
			legacyLedger(t, source, false)
			migrationSQL(t, source, sql)
			if err := source.Migrate(t.Context()); err == nil {
				t.Fatal("accepted incompatible legacy ledger")
			}
		})
	}
}

func TestMigrationRejectsChangedMissingAndOutOfOrderFiles(t *testing.T) {
	source := migrationSource(t, testdb.New(t))
	files := migrationFiles(t, map[string]string{"003_later.sql": "CREATE TABLE later (id integer)"})
	if err := source.migrate(t.Context(), files); err != nil {
		t.Fatal(err)
	}
	for name, candidate := range map[string]fstest.MapFS{
		"missing":          migrationFiles(t, nil),
		"changed":          migrationFiles(t, map[string]string{"003_later.sql": "CREATE TABLE later (id bigint)"}),
		"inserted earlier": migrationFiles(t, map[string]string{"002_earlier.sql": "CREATE TABLE earlier (id integer)", "003_later.sql": "CREATE TABLE later (id integer)"}),
	} {
		t.Run(name, func(t *testing.T) {
			if err := source.migrate(t.Context(), candidate); err == nil {
				t.Fatal("accepted inconsistent migration files")
			}
		})
	}
}

func TestMigrationRollbackAndRetry(t *testing.T) {
	for _, legacy := range []bool{false, true} {
		t.Run(map[bool]string{false: "fresh", true: "legacy"}[legacy], func(t *testing.T) {
			source := migrationSource(t, testdb.New(t))
			if legacy {
				legacyLedger(t, source, true)
			}
			files := migrationFiles(t, map[string]string{"002_failure.sql": "CREATE TABLE rolled_back (id integer); SELECT missing_column FROM rolled_back"})
			if err := source.migrate(t.Context(), files); err == nil {
				t.Fatal("bad DDL succeeded")
			}
			var exists bool
			if err := source.pool.QueryRow(t.Context(), `SELECT to_regclass('rolled_back') IS NOT NULL`).Scan(&exists); err != nil || exists {
				t.Fatalf("DDL did not roll back: %v %v", exists, err)
			}
			if legacy {
				if err := source.pool.QueryRow(t.Context(), `SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'schema_migrations' AND column_name = 'checksum')`).Scan(&exists); err != nil || exists {
					t.Fatalf("legacy upgrade did not roll back: %v %v", exists, err)
				}
			}
			files["migrations/002_failure.sql"].Data = []byte("CREATE TABLE rolled_back (id integer)")
			if err := source.migrate(t.Context(), files); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestMigrationLockCancellationAndRetry(t *testing.T) {
	source := migrationSource(t, testdb.New(t))
	tx, err := source.pool.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(context.Background())
	if _, err := tx.Exec(t.Context(), `SELECT pg_advisory_xact_lock(684019283)`); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 75*time.Millisecond)
	defer cancel()
	if err := source.Migrate(ctx); err == nil {
		t.Fatal("lock wait ignored cancellation")
	}
	if err := tx.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
}

func TestMigrationSearchPathDoesNotAdoptLaterLedger(t *testing.T) {
	first, _ := url.Parse(testdb.New(t))
	second, _ := url.Parse(testdb.New(t))
	later := migrationSource(t, second.String())
	legacyLedger(t, later, true)
	query := first.Query()
	query.Set("search_path", query.Get("search_path")+","+second.Query().Get("search_path"))
	first.RawQuery = query.Encode()
	source := migrationSource(t, first.String())
	if err := source.Migrate(t.Context()); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := source.pool.QueryRow(t.Context(), `SELECT count(*) FROM documents`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("read later schema data: %d %v", count, err)
	}
	if err := later.pool.QueryRow(t.Context(), `SELECT count(*) FROM documents`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("later schema data changed: %d %v", count, err)
	}
	query.Set("search_path", "domabas_missing_"+strings.ReplaceAll(time.Now().Format("150405.000000000"), ".", ""))
	first.RawQuery = query.Encode()
	if err := migrationSource(t, first.String()).Migrate(t.Context()); err == nil {
		t.Fatal("accepted missing current schema")
	}
}
