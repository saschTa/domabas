package postgres

import (
	"context"
	"crypto/sha256"
	"embed"
	"fmt"
	"io/fs"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
)

//go:embed migrations/*.sql
var migrations embed.FS

const originalMigrationChecksum = "5d031a8aff598b3ed35c11c463edfc5c8bad19326eaa53e5f32baa319712dfaa"

func readMigrations(files fs.FS) ([]postgresMigration, error) {
	entries, err := fs.ReadDir(files, "migrations")
	if err != nil {
		return nil, fmt.Errorf("read migrations: %w", err)
	}
	if len(entries) == 0 {
		return nil, fmt.Errorf("migration catalog is empty")
	}
	pattern := regexp.MustCompile(`^([0-9]{3})_[a-z][a-z0-9]*(?:_[a-z0-9]+)*\.sql$`)
	result := make([]postgresMigration, 0, len(entries))
	identities := make(map[int]bool)
	for _, entry := range entries {
		match := pattern.FindStringSubmatch(entry.Name())
		if entry.IsDir() || match == nil {
			return nil, fmt.Errorf("invalid migration filename %q", entry.Name())
		}
		number, _ := strconv.Atoi(match[1])
		if number == 0 || identities[number] {
			return nil, fmt.Errorf("invalid or duplicate migration number in %q", entry.Name())
		}
		identities[number] = true
		contents, err := fs.ReadFile(files, "migrations/"+entry.Name())
		if err != nil {
			return nil, fmt.Errorf("read migration %s: %w", entry.Name(), err)
		}
		result = append(result, postgresMigration{version: entry.Name(), number: number, sql: string(contents), checksum: fmt.Sprintf("%x", sha256.Sum256(contents))})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].number < result[j].number })
	return result, nil
}

func validateHistory(files []postgresMigration, applied []postgresAppliedMigration, legacy bool) error {
	if legacy {
		if len(files) == 0 || files[0].version != "001_documents.sql" || files[0].checksum != originalMigrationChecksum {
			return fmt.Errorf("legacy migration history requires the original 001_documents.sql")
		}
		if len(applied) > 1 || (len(applied) == 1 && applied[0].version != "001_documents.sql") {
			return fmt.Errorf("unrecognized legacy migration history")
		}
	}
	if len(applied) > len(files) {
		return fmt.Errorf("migration history contains unknown or missing files")
	}
	for index, row := range applied {
		if row.version != files[index].version {
			return fmt.Errorf("migration history is not a prefix of files at %s", row.version)
		}
		if !legacy && (row.checksum == nil || *row.checksum != files[index].checksum) {
			return fmt.Errorf("migration checksum mismatch for %s", row.version)
		}
	}
	return nil
}

func (source *PostgresDataSource) Migrate(ctx context.Context) error {
	return source.migrate(ctx, migrations)
}

func (source *PostgresDataSource) migrate(ctx context.Context, files fs.FS) error {
	ordered, err := readMigrations(files)
	if err != nil {
		return err
	}
	tx, err := source.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin migrations: %w", err)
	}
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(cleanup)
	}()
	if err := migrateTransaction(ctx, tx, ordered); err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit migrations: %w", err)
	}
	return nil
}

func migrateTransaction(ctx context.Context, tx pgx.Tx, files []postgresMigration) error {
	if _, err := tx.Exec(ctx, `SELECT pg_catalog.pg_advisory_xact_lock(684019283)`); err != nil {
		return fmt.Errorf("lock migrations: %w", err)
	}
	var schema *string
	if err := tx.QueryRow(ctx, `SELECT pg_catalog.current_schema()`).Scan(&schema); err != nil {
		return fmt.Errorf("resolve migration schema: %w", err)
	}
	if schema == nil {
		return fmt.Errorf("migration search_path has no existing schema")
	}
	if _, err := tx.Exec(ctx, `SELECT pg_catalog.set_config('search_path', $1, true)`, pgx.Identifier{*schema}.Sanitize()); err != nil {
		return fmt.Errorf("pin migration schema: %w", err)
	}
	legacy, err := prepareLedger(ctx, tx, *schema)
	if err != nil {
		return err
	}
	query := `SELECT version, checksum FROM schema_migrations ORDER BY version`
	if legacy {
		query = `SELECT version, NULL::text FROM schema_migrations ORDER BY version`
	}
	rows, err := tx.Query(ctx, query)
	if err != nil {
		return fmt.Errorf("read migration history: %w", err)
	}
	applied, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (postgresAppliedMigration, error) {
		var value postgresAppliedMigration
		err := row.Scan(&value.version, &value.checksum)
		return value, err
	})
	if err != nil {
		return fmt.Errorf("scan migration history: %w", err)
	}
	if err := validateHistory(files, applied, legacy); err != nil {
		return err
	}
	if legacy {
		if _, err := tx.Exec(ctx, `ALTER TABLE schema_migrations ADD COLUMN checksum text`); err != nil {
			return fmt.Errorf("upgrade migration ledger: %w", err)
		}
		if _, err := tx.Exec(ctx, `UPDATE schema_migrations SET checksum = $1`, originalMigrationChecksum); err != nil {
			return fmt.Errorf("adopt legacy checksum: %w", err)
		}
		if _, err := tx.Exec(ctx, `ALTER TABLE schema_migrations ALTER COLUMN checksum SET NOT NULL`); err != nil {
			return fmt.Errorf("require migration checksums: %w", err)
		}
	}
	for _, file := range files[len(applied):] {
		if _, err := tx.Exec(ctx, file.sql); err != nil {
			return fmt.Errorf("apply migration %s: %w", file.version, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations(version, checksum) VALUES ($1, $2)`, file.version, file.checksum); err != nil {
			return fmt.Errorf("record migration %s: %w", file.version, err)
		}
	}
	return nil
}

func prepareLedger(ctx context.Context, tx pgx.Tx, schema string) (bool, error) {
	var kind string
	err := tx.QueryRow(ctx, `SELECT c.relkind::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND c.relname = 'schema_migrations'`, schema).Scan(&kind)
	if err == pgx.ErrNoRows {
		_, err = tx.Exec(ctx, `CREATE TABLE schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now(), checksum text NOT NULL)`)
		if err != nil {
			return false, fmt.Errorf("create migration ledger: %w", err)
		}
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("inspect migration ledger: %w", err)
	}
	if kind != "r" {
		return false, fmt.Errorf("incompatible migration ledger: expected a table")
	}
	rows, err := tx.Query(ctx, `SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod), a.attnotnull, coalesce(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '')
		FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid = a.attrelid JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
		LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
		WHERE n.nspname = $1 AND c.relname = 'schema_migrations' AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum`, schema)
	if err != nil {
		return false, fmt.Errorf("inspect migration columns: %w", err)
	}
	columns, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (postgresLedgerColumn, error) {
		var value postgresLedgerColumn
		err := row.Scan(&value.name, &value.kind, &value.required, &value.defaultValue)
		return value, err
	})
	if err != nil {
		return false, fmt.Errorf("scan migration columns: %w", err)
	}
	if len(columns) < 2 || len(columns) > 3 || columns[0] != (postgresLedgerColumn{"version", "text", true, ""}) || columns[1] != (postgresLedgerColumn{"applied_at", "timestamp with time zone", true, "now()"}) {
		return false, fmt.Errorf("incompatible migration ledger columns")
	}
	if len(columns) == 3 && columns[2] != (postgresLedgerColumn{"checksum", "text", true, ""}) {
		return false, fmt.Errorf("incompatible migration checksum column")
	}
	var primaryKey bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint p JOIN pg_catalog.pg_class c ON c.oid = p.conrelid JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND c.relname = 'schema_migrations' AND p.contype = 'p' AND p.conkey = ARRAY[1]::smallint[] AND NOT p.condeferrable)`, schema).Scan(&primaryKey); err != nil {
		return false, fmt.Errorf("inspect migration primary key: %w", err)
	}
	if !primaryKey {
		return false, fmt.Errorf("incompatible migration ledger primary key")
	}
	return len(columns) == 2, nil
}
