package datasources

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/email/models"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type EmailResourceScheduler interface {
	Reserve(context.Context, pgx.Tx, string, string, []string) (bool, error)
}

type EmailDataSource struct {
	scheduler EmailResourceScheduler
	database  *postgres.PostgresDatabase
}

func NewEmailDataSource(database *postgres.PostgresDatabase, scheduler EmailResourceScheduler) *EmailDataSource {
	return &EmailDataSource{database: database, scheduler: scheduler}
}
func translate(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return m.ErrNotFound
	}
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		switch pg.Code {
		case "23505":
			return m.ErrConflict
		case "57014", "40001", "40P01", "55P03":
			return m.ErrUnavailable
		}
	}
	return err
}
func (s *EmailDataSource) tx(ctx context.Context, fn func(context.Context, pgx.Tx) error) error {
	return s.transaction(ctx, pgx.TxOptions{}, fn)
}
func (s *EmailDataSource) readTx(ctx context.Context, fn func(context.Context, pgx.Tx) error) error {
	return s.transaction(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, fn)
}
func (s *EmailDataSource) transaction(ctx context.Context, options pgx.TxOptions, fn func(context.Context, pgx.Tx) error) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	return translate(pgx.BeginTxFunc(ctx, s.database, options, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='4s'; SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		return fn(ctx, tx)
	}))
}

const providerColumns = `id::text,account_id::text,owner_id::text,label,host,port,mailbox,enabled,interval_minutes,max_age_days,page_size,revision,source_generation,credential_version,COALESCE(consent_revision,0),COALESCE(credential_key_id,''),credential_ciphertext,next_poll_at,COALESCE(last_run_id::text,''),COALESCE(last_failure_code,''),created_at,updated_at,COALESCE((SELECT r.status FROM email_runs r WHERE r.id=email_providers.last_run_id),''),COALESCE((SELECT r.id::text FROM email_runs r WHERE r.provider_id=email_providers.id AND r.status IN ('queued','running') LIMIT 1),''),(SELECT max(r.started_at) FROM email_runs r WHERE r.provider_id=email_providers.id)`

type emailRowScanner interface{ Scan(...any) error }

func scanProvider(row emailRowScanner) (r.EmailProviderRecord, error) {
	var result r.EmailProviderRecord
	p := &result.Provider
	err := row.Scan(&p.ID, &p.AccountID, &p.OwnerID, &p.Label, &p.Host, &p.Port, &p.Mailbox, &p.Enabled, &p.IntervalMinutes, &p.MaxAgeDays, &p.PageSize, &p.Revision, &p.SourceGeneration, &p.CredentialVersion, &p.ConsentRevision, &result.KeyID, &result.Ciphertext, &p.NextPollAt, &p.LastRunID, &p.LastFailureCode, &p.CreatedAt, &p.UpdatedAt, &p.LastRunStatus, &p.ActiveRunID, &p.LastAttemptAt)
	p.HasPassword = len(result.Ciphertext) > 0
	return result, err
}
func readProvider(ctx context.Context, tx pgx.Tx, a m.EmailActor, id string) (r.EmailProviderRecord, error) {
	return scanProvider(tx.QueryRow(ctx, `SELECT `+providerColumns+` FROM email_providers WHERE id=$1 AND account_id=$2 AND owner_id=$3 AND deleted_at IS NULL`, id, a.AccountID, a.UserID))
}
func lockProvider(ctx context.Context, tx pgx.Tx, a m.EmailActor, id string) (r.EmailProviderRecord, error) {
	return scanProvider(tx.QueryRow(ctx, `SELECT `+providerColumns+` FROM email_providers WHERE id=$1 AND account_id=$2 AND owner_id=$3 AND deleted_at IS NULL FOR UPDATE`, id, a.AccountID, a.UserID))
}
func (s *EmailDataSource) Get(ctx context.Context, a m.EmailActor, id string) (r.EmailProviderRecord, error) {
	var result r.EmailProviderRecord
	err := s.readTx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		result, err = readProvider(ctx, tx, a, id)
		return err
	})
	return result, err
}

type emailProviderCursor struct {
	ID string
	At time.Time
}

func cursorFingerprint(a m.EmailActor, scope string, limit int) string {
	fingerprint, _ := pagination.Fingerprint(struct {
		Owner, Account, Scope string
		Limit                 int
	}{a.UserID, a.AccountID, scope, limit})
	return fingerprint
}
func decodeCursor(value string, a m.EmailActor, scope string, limit int) (emailProviderCursor, error) {
	c := emailProviderCursor{At: time.Date(9999, 1, 1, 0, 0, 0, 0, time.UTC), ID: "ffffffff-ffff-ffff-ffff-ffffffffffff"}
	if value == "" {
		return c, nil
	}
	fields, err := pagination.Decode(value, "email."+scope, cursorFingerprint(a, scope, limit), "newest")
	if err != nil || len(fields) != 2 || json.Unmarshal(fields["ID"], &c.ID) != nil || json.Unmarshal(fields["At"], &c.At) != nil || c.At.IsZero() {
		return c, m.EmailValidationError{Message: "invalid cursor"}
	}
	if _, err = uuid.Parse(c.ID); err != nil {
		return c, m.EmailValidationError{Message: "invalid cursor"}
	}
	return c, nil
}
func encodeCursor(a m.EmailActor, scope, id string, at time.Time, limit int) string {
	result, _ := pagination.Encode("email."+scope, cursorFingerprint(a, scope, limit), "newest", emailProviderCursor{ID: id, At: at})
	return result
}
func (s *EmailDataSource) List(ctx context.Context, a m.EmailActor, limit int, value string) ([]r.EmailProviderRecord, string, error) {
	c, err := decodeCursor(value, a, "providers", limit)
	if err != nil {
		return nil, "", err
	}
	if limit < 1 || limit > 50 {
		return nil, "", m.EmailValidationError{Message: "limit must be 1 to 50"}
	}
	result := []r.EmailProviderRecord{}
	next := ""
	err = s.readTx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+providerColumns+` FROM email_providers WHERE owner_id=$1 AND account_id=$2 AND deleted_at IS NULL AND (created_at,id)<($3,$4) ORDER BY created_at DESC,id DESC LIMIT $5`, a.UserID, a.AccountID, c.At, c.ID, limit+1)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			record, err := scanProvider(rows)
			if err != nil {
				return err
			}
			result = append(result, record)
		}
		return rows.Err()
	})
	if len(result) > limit {
		result = result[:limit]
		last := result[len(result)-1].Provider
		next = encodeCursor(a, "providers", last.ID, last.CreatedAt, limit)
	}
	return result, next, err
}
func (s *EmailDataSource) Create(ctx context.Context, a m.EmailActor, write r.EmailProviderWrite) (r.EmailProviderRecord, error) {
	var result r.EmailProviderRecord
	input := write.Input
	err := s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		revision := a.CredentialRevision
		var err error
		if err = providerCollision(ctx, tx, a, input.ID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended(current_database()||':'||current_schema()||':email-provider-owner:'||$1,0))`, a.UserID); err != nil {
			return err
		}
		var count int
		if err = tx.QueryRow(ctx, "SELECT count(*) FROM email_providers WHERE owner_id=$1 AND deleted_at IS NULL", a.UserID).Scan(&count); err != nil {
			return err
		}
		if count >= input.MaximumProviders {
			return m.EmailValidationError{Message: "at most 20 email providers are allowed"}
		}
		tag, err := tx.Exec(ctx, `INSERT INTO email_providers(id,account_id,owner_id,label,host,port,mailbox,enabled,interval_minutes,max_age_days,page_size,consent_revision,credential_key_id,credential_ciphertext) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,CASE WHEN $8 THEN $12::bigint ELSE NULL END,$13,$14) ON CONFLICT(id) DO NOTHING`, input.ID, a.AccountID, a.UserID, input.Label, input.Host, input.Port, input.Mailbox, input.Enabled, input.IntervalMinutes, input.MaxAgeDays, input.PageSize, revision, write.KeyID, write.Ciphertext)
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return providerCollision(ctx, tx, a, input.ID)
		}
		result, err = readProvider(ctx, tx, a, input.ID)
		return err
	})
	return result, err
}
func providerCollision(ctx context.Context, tx pgx.Tx, actor m.EmailActor, id string) error {
	var owned bool
	err := tx.QueryRow(ctx, `SELECT account_id=$2 AND owner_id=$3 AND deleted_at IS NULL FROM email_providers WHERE id=$1`, id, actor.AccountID, actor.UserID).Scan(&owned)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if owned {
		return m.ErrConflict
	}
	return m.ErrNotFound
}
func (s *EmailDataSource) Update(ctx context.Context, a m.EmailActor, write r.EmailProviderWrite) (r.EmailProviderRecord, error) {
	var result r.EmailProviderRecord
	input := write.Input
	err := s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		revision := a.CredentialRevision
		var err error
		current, err := lockProvider(ctx, tx, a, input.ID)
		if err != nil {
			return err
		}
		if current.Provider.Revision != write.SnapshotProviderRevision || current.Provider.CredentialVersion != write.SnapshotCredentialVersion || current.Provider.ConsentRevision != write.SnapshotConsentRevision {
			return m.ErrConflict
		}
		if write.Noop {
			result = current
			return nil
		}
		_, err = tx.Exec(ctx, `UPDATE email_providers SET label=$2,host=$3,port=$4,mailbox=$5,enabled=$6,interval_minutes=$7,max_age_days=$8,page_size=$9,revision=revision+1,source_generation=source_generation+CASE WHEN $10 THEN 1 ELSE 0 END,credential_version=credential_version+CASE WHEN $11 THEN 1 ELSE 0 END,credential_key_id=CASE WHEN $11 THEN $12 ELSE credential_key_id END,credential_ciphertext=CASE WHEN $11 THEN $13 ELSE credential_ciphertext END,consent_revision=CASE WHEN $14 THEN $15 ELSE consent_revision END,next_poll_at=clock_timestamp(),updated_at=clock_timestamp(),last_failure_code=NULL WHERE id=$1`, input.ID, input.Label, input.Host, input.Port, input.Mailbox, input.Enabled, input.IntervalMinutes, input.MaxAgeDays, input.PageSize, write.SourceChanged, write.CredentialChanged, write.KeyID, write.Ciphertext, write.RenewConsent, revision)
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE email_runs SET status=$2,failure_code=$3,attempt_token=NULL,attempt_deadline=NULL,finished_at=clock_timestamp() WHERE provider_id=$1 AND status IN ('queued','running')`, input.ID, write.SupersededState, write.SupersededCode); err != nil {
			return err
		}
		result, err = readProvider(ctx, tx, a, input.ID)
		return err
	})
	return result, err
}
func (s *EmailDataSource) Delete(ctx context.Context, a m.EmailActor, id string, expected int64) error {
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		current, err := lockProvider(ctx, tx, a, id)
		if err != nil {
			return err
		}
		if current.Provider.Revision != expected {
			return m.ErrConflict
		}
		if _, err = tx.Exec(ctx, `UPDATE email_providers SET enabled=false,deleted_at=clock_timestamp(),revision=revision+1,credential_key_id=NULL,credential_ciphertext=NULL,updated_at=clock_timestamp() WHERE id=$1`, id); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE email_runs SET status='cancelled',failure_code='provider_deleted',attempt_token=NULL,attempt_deadline=NULL,finished_at=clock_timestamp() WHERE provider_id=$1 AND status IN ('queued','running')`, id)
		return err
	})
}
func (s *EmailDataSource) BeginTest(ctx context.Context, a m.EmailActor, admission m.EmailTestAdmission) (string, error) {
	token := uuid.NewString()
	err := s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `INSERT INTO email_test_limits(owner_id,lease_token,lease_until,next_allowed_at) VALUES($1,$2,clock_timestamp()+$3::interval,clock_timestamp()+$4::interval) ON CONFLICT(owner_id) DO UPDATE SET lease_token=EXCLUDED.lease_token,lease_until=EXCLUDED.lease_until,next_allowed_at=EXCLUDED.next_allowed_at WHERE email_test_limits.lease_until<=clock_timestamp() AND email_test_limits.next_allowed_at<=clock_timestamp()`, a.UserID, token, admission.Lease.String(), admission.Pacing.String())
		if err == nil && tag.RowsAffected() != 1 {
			return m.ErrRateLimited
		}
		return err
	})
	return token, err
}
func (s *EmailDataSource) EndTest(ctx context.Context, a m.EmailActor, token string) error {
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE email_test_limits SET lease_until=clock_timestamp() WHERE owner_id=$1 AND lease_token=$2`, a.UserID, token)
		return err
	})
}
func (s *EmailDataSource) RotationCandidates(ctx context.Context, active string, limit int) ([]r.EmailProviderRecord, error) {
	result := []r.EmailProviderRecord{}
	err := s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT `+providerColumns+` FROM email_providers WHERE deleted_at IS NULL AND credential_key_id<>$1 ORDER BY updated_at,id LIMIT $2`, active, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			record, err := scanProvider(rows)
			if err != nil {
				return err
			}
			result = append(result, record)
		}
		return rows.Err()
	})
	return result, err
}
func (s *EmailDataSource) Rotate(ctx context.Context, old r.EmailProviderRecord, key string, ciphertext []byte) error {
	return s.tx(ctx, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE email_providers SET credential_key_id=$2,credential_ciphertext=$3 WHERE id=$1 AND credential_version=$4 AND credential_key_id=$5 AND credential_ciphertext=$6 AND deleted_at IS NULL`, old.Provider.ID, key, ciphertext, old.Provider.CredentialVersion, old.KeyID, old.Ciphertext)
		return err
	})
}
