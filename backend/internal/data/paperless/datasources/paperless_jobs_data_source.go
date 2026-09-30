package datasources

import (
	"context"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"slices"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	d "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type PaperlessResourceScheduler interface {
	Reserve(context.Context, pgx.Tx, string, string, []string) (bool, error)
}

type PaperlessJobsDataSource struct {
	scheduler PaperlessResourceScheduler
	db        *postgres.PostgresDatabase
	key       cipher.AEAD
	queue     string
}

func NewPaperlessJobsDataSource(db *postgres.PostgresDatabase, key, queue string, scheduler PaperlessResourceScheduler) (*PaperlessJobsDataSource, error) {
	vault, err := credentialCipher(key)
	if err != nil {
		return nil, err
	}
	return &PaperlessJobsDataSource{db: db, key: vault, queue: queue, scheduler: scheduler}, nil
}
func (s *PaperlessJobsDataSource) actorTx(ctx context.Context, a d.DocumentActor, fn func(pgx.Tx) error) error {
	return s.authorizedTx(ctx, a, pgx.TxOptions{}, fn)
}
func (s *PaperlessJobsDataSource) readTx(ctx context.Context, a d.DocumentActor, fn func(pgx.Tx) error) error {
	return s.authorizedTx(ctx, a, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, fn)
}
func (s *PaperlessJobsDataSource) authorizedTx(ctx context.Context, a d.DocumentActor, options pgx.TxOptions, fn func(pgx.Tx) error, claims ...string) error {
	return pgx.BeginTxFunc(ctx, s.db, options, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		return fn(tx)
	})
}
func (s *PaperlessJobsDataSource) Create(ctx context.Context, a d.DocumentActor, id string, c m.PaperlessConnection) (m.PaperlessRun, error) {
	server, err := normalizeServerURL(c.ServerURL)
	if err != nil {
		return m.PaperlessRun{}, err
	}
	c.ServerURL = server
	nonce := make([]byte, s.key.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return m.PaperlessRun{}, err
	}
	aad := []byte(id + "/" + a.AccountID + "/" + a.UserID)
	encrypted := s.key.Seal(nonce, nonce, []byte(c.Token), aad)
	hash := sha256.Sum256([]byte(c.ServerURL + "\x00" + c.Token))
	err = s.actorTx(ctx, a, func(tx pgx.Tx) error {
		var singleton bool
		if err := tx.QueryRow(ctx, "SELECT singleton FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&singleton); err != nil {
			return err
		}
		var existing []byte
		err := tx.QueryRow(ctx, "SELECT request_hash FROM paperless_runs WHERE id=$1 AND account_id=$2 AND owner_id=$3", id, a.AccountID, a.UserID).Scan(&existing)
		if err == nil {
			if !slices.Equal(existing, hash[:]) {
				return d.ErrConflict
			}
			return nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		var count int
		if err := tx.QueryRow(ctx, "SELECT count(*) FROM paperless_runs WHERE NOT execution_closed").Scan(&count); err != nil {
			return err
		}
		if count >= c.MaximumUnclosedRuns {
			return m.ErrBusy
		}
		_, err = tx.Exec(ctx, "INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,encrypted_token,task_queue) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", id, a.AccountID, a.UserID, a.CredentialRevision, c.ServerURL, hash[:], encrypted, s.queue)
		var constraint *pgconn.PgError
		if errors.As(err, &constraint) && constraint.Code == "23505" {
			return d.ErrConflict
		}
		return err
	})
	if err != nil {
		return m.PaperlessRun{}, err
	}
	return s.Get(ctx, a, id)
}
func readRun(ctx context.Context, tx pgx.Tx, id string, includeOutcomes bool) (m.PaperlessRun, error) {
	var r m.PaperlessRun
	err := tx.QueryRow(ctx, `SELECT r.id,r.server_url,r.state,r.stage,r.failure_code,r.cancel_requested,r.created_at,r.updated_at,
 (SELECT count(*) FROM paperless_items WHERE run_id=r.id),
 (SELECT count(*) FROM paperless_items WHERE run_id=r.id AND status='imported'),
 (SELECT count(*) FROM paperless_items WHERE run_id=r.id AND status='duplicate'),
 (SELECT count(*) FROM paperless_items WHERE run_id=r.id AND status='failed')
 FROM paperless_runs r WHERE r.id=$1`, id).Scan(&r.ID, &r.ServerURL, &r.State, &r.Stage, &r.FailureCode, &r.CancelRequested, &r.CreatedAt, &r.UpdatedAt, &r.Discovered, &r.Imported, &r.Duplicates, &r.Failed)
	if err != nil {
		return r, err
	}
	r.Outcomes = []m.PaperlessOutcome{}
	if !includeOutcomes {
		return r, nil
	}
	rows, err := tx.Query(ctx, "SELECT source_id,title,status,failure_code,COALESCE(document_id::text,'') FROM paperless_items WHERE run_id=$1 AND status<>'pending' ORDER BY source_id DESC LIMIT 100", id)
	if err != nil {
		return r, err
	}
	defer rows.Close()
	for rows.Next() {
		var o m.PaperlessOutcome
		if err = rows.Scan(&o.SourceID, &o.Title, &o.Status, &o.FailureCode, &o.DocumentID); err != nil {
			return r, err
		}
		r.Outcomes = append(r.Outcomes, o)
	}
	return r, rows.Err()
}
func (s *PaperlessJobsDataSource) Get(ctx context.Context, a d.DocumentActor, id string) (m.PaperlessRun, error) {
	var result m.PaperlessRun
	err := s.readTx(ctx, a, func(tx pgx.Tx) error {
		var owned string
		if err := tx.QueryRow(ctx, "SELECT id FROM paperless_runs WHERE id=$1 AND account_id=$2 AND owner_id=$3", id, a.AccountID, a.UserID).Scan(&owned); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return d.ErrNotFound
			}
			return err
		}
		var err error
		result, err = readRun(ctx, tx, id, true)
		return err
	})
	return result, err
}
func (s *PaperlessJobsDataSource) RunFacts(ctx context.Context, id string) (m.PaperlessRunFacts, error) {
	var facts m.PaperlessRunFacts
	err := s.db.QueryRow(ctx, "SELECT state,stage,cancel_requested,first_start_at IS NOT NULL,updated_at FROM paperless_runs WHERE id=$1", id).Scan(&facts.State, &facts.Stage, &facts.Cancelled, &facts.Started, &facts.UpdatedAt)
	return facts, err
}
func (s *PaperlessJobsDataSource) Cancel(ctx context.Context, a d.DocumentActor, id string, command m.PaperlessTerminalCommand) (m.PaperlessRun, error) {
	err := s.actorTx(ctx, a, func(tx pgx.Tx) error {
		var singleton bool
		if err := tx.QueryRow(ctx, "SELECT singleton FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&singleton); err != nil {
			return err
		}
		if !command.Apply {
			return nil
		}
		tag, err := tx.Exec(ctx, `UPDATE paperless_runs SET cancel_requested=$4,state=$5,stage=$6,encrypted_token=CASE WHEN $7 THEN NULL ELSE encrypted_token END,execution_closed=execution_closed OR $8,updated_at=clock_timestamp() WHERE id=$1 AND account_id=$2 AND owner_id=$3 AND state=$9 AND stage=$10 AND cancel_requested=$11 AND (first_start_at IS NOT NULL)=$12 AND updated_at=$13`, id, a.AccountID, a.UserID, command.Cancel, command.State, command.Stage, command.ClearCredential, command.CloseExecution, command.Expected.State, command.Expected.Stage, command.Expected.Cancelled, command.Expected.Started, command.Expected.UpdatedAt)
		if err == nil && tag.RowsAffected() != 1 {
			return d.ErrConflict
		}
		return err
	})
	if err != nil {
		return m.PaperlessRun{}, err
	}
	return s.Get(ctx, a, id)
}
func (s *PaperlessJobsDataSource) Next(ctx context.Context) (*m.PaperlessExecution, error) {
	var e m.PaperlessExecution
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var locked bool
		if err := tx.QueryRow(ctx, "SELECT singleton FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&locked); err != nil {
			return err
		}
		var started bool
		if err := tx.QueryRow(ctx, `SELECT p.id,p.task_queue,p.first_start_at IS NOT NULL FROM paperless_runs p LEFT JOIN scheduler_requests q ON q.workflow_id='domabas-paperless-'||p.id::text AND q.state='waiting' WHERE NOT p.execution_closed AND ((p.first_start_at IS NULL AND p.state IN ('queued','running') AND NOT p.cancel_requested) OR (p.first_start_at IS NOT NULL AND p.next_check_at<=clock_timestamp())) ORDER BY (p.first_start_at IS NOT NULL) DESC,q.sequence NULLS LAST,p.next_check_at,p.created_at,p.id LIMIT 1 FOR UPDATE OF p`).Scan(&e.ID, &e.TaskQueue, &started); err != nil {
			return err
		}
		if !started {
			if s.scheduler == nil {
				return errors.New("Paperless resource scheduler is not configured")
			}
			admitted, err := s.scheduler.Reserve(ctx, tx, "domabas-paperless-"+e.ID, "paperless", nil)
			if err != nil {
				return err
			}
			if !admitted {
				e.ID = ""
				return nil
			}
		}
		return tx.QueryRow(ctx, `UPDATE paperless_runs SET first_start_at=COALESCE(first_start_at,clock_timestamp()),next_check_at=clock_timestamp()+interval '10 seconds' WHERE id=$1 RETURNING first_start_at`, e.ID).Scan(&e.FirstStart)
	})
	if errors.Is(err, pgx.ErrNoRows) || err == nil && e.ID == "" {
		return nil, nil
	}
	return &e, err
}
func (s *PaperlessJobsDataSource) WorkIdentity(ctx context.Context, id string) (d.DocumentActor, error) {
	var actor d.DocumentActor
	err := s.db.QueryRow(ctx, "SELECT account_id,owner_id,credential_revision FROM paperless_runs WHERE id=$1", id).Scan(&actor.AccountID, &actor.UserID, &actor.CredentialRevision)
	return actor, err
}
func (s *PaperlessJobsDataSource) Work(ctx context.Context, id string, command m.PaperlessWorkCommand) (m.PaperlessWork, error) {
	var w m.PaperlessWork
	var encrypted []byte
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, "SELECT account_id,owner_id,credential_revision FROM paperless_runs WHERE id=$1", id).Scan(&w.Actor.AccountID, &w.Actor.UserID, &w.Actor.CredentialRevision); err != nil {
			return err
		}
		var limit int
		if err := tx.QueryRow(ctx, "SELECT retrieval_concurrency FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&limit); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, "SELECT id,server_url,state,stage,cancel_requested,updated_at FROM paperless_runs WHERE id=$1 FOR UPDATE", id).Scan(&w.Run.ID, &w.Run.ServerURL, &w.Run.State, &w.Run.Stage, &w.Run.CancelRequested, &w.Run.UpdatedAt); err != nil {
			return err
		}
		if w.Run.State != command.Expected.State || w.Run.Stage != command.Expected.Stage || w.Run.CancelRequested != command.Expected.Cancelled {
			return d.ErrConflict
		}
		if !command.Active {
			return nil
		}
		if _, err := tx.Exec(ctx, "UPDATE paperless_runs SET state=$2,stage=$3,updated_at=clock_timestamp() WHERE id=$1", id, command.State, command.Stage); err != nil {
			return err
		}
		w.Run.State, w.Run.Stage = command.State, command.Stage
		if err := tx.QueryRow(ctx, "SELECT page,encrypted_token FROM paperless_runs WHERE id=$1", id).Scan(&w.Page, &encrypted); err != nil {
			return err
		}
		if command.Retrieve {
			if err := s.claimRetrievals(ctx, tx, id, limit, command.Retrieval, &w); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return w, err
	}
	if len(encrypted) == 0 {
		return w, nil
	}
	if s.key == nil || len(encrypted) < s.key.NonceSize() {
		return w, m.PaperlessFailure{Code: "credentials_unavailable"}
	}
	token, err := s.key.Open(nil, encrypted[:s.key.NonceSize()], encrypted[s.key.NonceSize():], []byte(id+"/"+w.Actor.AccountID+"/"+w.Actor.UserID))
	if err != nil {
		return w, m.PaperlessFailure{Code: "credentials_unavailable"}
	}
	w.Connection = m.PaperlessConnection{ServerURL: w.Run.ServerURL, Token: string(token)}
	w.Actor.ImportRunID = id
	return w, nil
}
func (s *PaperlessJobsDataSource) PageFacts(ctx context.Context, id string) (m.PaperlessPageFacts, error) {
	var facts m.PaperlessPageFacts
	err := s.db.QueryRow(ctx, `SELECT page,source_total,cancel_requested,(SELECT count(*) FROM paperless_items WHERE run_id=r.id),(SELECT COALESCE(max(source_id),0) FROM paperless_items WHERE run_id=r.id) FROM paperless_runs r WHERE id=$1 AND state='running'`, id).Scan(&facts.Page, &facts.Total, &facts.Cancelled, &facts.Count, &facts.Previous)
	return facts, err
}
func (s *PaperlessJobsDataSource) RecordPage(ctx context.Context, id string, command m.PaperlessPageCommand) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var current m.PaperlessPageFacts
		if err := tx.QueryRow(ctx, `SELECT page,source_total,cancel_requested,(SELECT count(*) FROM paperless_items WHERE run_id=r.id),(SELECT COALESCE(max(source_id),0) FROM paperless_items WHERE run_id=r.id) FROM paperless_runs r WHERE id=$1 AND state='running' FOR UPDATE`, id).Scan(&current.Page, &current.Total, &current.Cancelled, &current.Count, &current.Previous); err != nil {
			return err
		}
		expected := command.Expected
		sameTotal := (current.Total == nil && expected.Total == nil) || (current.Total != nil && expected.Total != nil && *current.Total == *expected.Total)
		if current.Page != expected.Page || current.Cancelled != expected.Cancelled || current.Count != expected.Count || current.Previous != expected.Previous || !sameTotal {
			return d.ErrConflict
		}
		for _, item := range command.Page.Items {
			if _, err := tx.Exec(ctx, "INSERT INTO paperless_items(run_id,source_id,title) VALUES($1,$2,$3)", id, item.ID, item.Title); err != nil {
				return err
			}
		}
		_, err := tx.Exec(ctx, "UPDATE paperless_runs SET page=page+1,source_total=$2,stage=$3,updated_at=clock_timestamp() WHERE id=$1", id, command.Page.Total, command.Stage)
		return err
	})
}
func (s *PaperlessJobsDataSource) RecordOutcome(ctx context.Context, id string, o m.PaperlessOutcome) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var locked string
		if err := tx.QueryRow(ctx, "SELECT id FROM paperless_runs WHERE id=$1 FOR UPDATE", id).Scan(&locked); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, "UPDATE paperless_items SET status=$3,failure_code=$4,document_id=NULLIF($5,'')::uuid,claim_token=NULL,claim_deadline=NULL,claim_recover_after=NULL WHERE run_id=$1 AND source_id=$2 AND status='pending' AND claim_token=NULLIF($6,'')::uuid AND claim_deadline>clock_timestamp()", id, o.SourceID, o.Status, o.FailureCode, o.DocumentID, o.ClaimToken)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			var completed bool
			if err := tx.QueryRow(ctx, "SELECT status<>'pending' FROM paperless_items WHERE run_id=$1 AND source_id=$2", id, o.SourceID).Scan(&completed); err != nil {
				return err
			}
			if !completed {
				return d.ErrStaleJob
			}
		}
		_, err = tx.Exec(ctx, "UPDATE paperless_runs SET updated_at=clock_timestamp() WHERE id=$1", id)
		return err
	})
}
func (s *PaperlessJobsDataSource) Finish(ctx context.Context, id string, command m.PaperlessTerminalCommand) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE paperless_runs SET state=$2,stage=$3,failure_code=$4,encrypted_token=CASE WHEN $5 THEN NULL ELSE encrypted_token END,updated_at=clock_timestamp() WHERE id=$1 AND state=$6 AND stage=$7 AND cancel_requested=$8 AND updated_at=$9`, id, command.State, command.Stage, command.Code, command.ClearCredential, command.Expected.State, command.Expected.Stage, command.Expected.Cancelled, command.Expected.UpdatedAt)
		if err == nil && tag.RowsAffected() != 1 {
			return d.ErrConflict
		}
		return err
	})
}
func (s *PaperlessJobsDataSource) Closed(ctx context.Context, id string) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var locked bool
		if err := tx.QueryRow(ctx, "SELECT singleton FROM paperless_admission WHERE singleton FOR UPDATE").Scan(&locked); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, "UPDATE paperless_runs SET execution_closed=true WHERE id=$1 AND state NOT IN ('queued','running')", id)
		if err != nil || tag.RowsAffected() != 1 {
			return err
		}
		return nil
	})
}
