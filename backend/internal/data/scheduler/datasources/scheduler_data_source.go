package datasources

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"net/url"
	"slices"
	"strconv"
	"strings"

	"github.com/domabas/domabas/backend/internal/data/postgres"
	r "github.com/domabas/domabas/backend/internal/data/scheduler/models"
	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
	"github.com/jackc/pgx/v5"
)

type SchedulerDataSource struct {
	db           *postgres.PostgresDatabase
	queueSize    int
	ollamaOrigin string
}

func NewSchedulerDataSource(db *postgres.PostgresDatabase, ollamaQueueSize int, ollamaOrigin string) *SchedulerDataSource {
	return &SchedulerDataSource{db: db, queueSize: ollamaQueueSize, ollamaOrigin: schedulerOrigin(ollamaOrigin)}
}

func schedulerOrigin(raw string) string {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || u.ForceQuery || strings.ContainsAny(raw, "\\\r\n") {
		return ""
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme != "http" && scheme != "https" {
		return ""
	}
	host := strings.TrimSuffix(strings.ToLower(u.Hostname()), ".")
	port := u.Port()
	if port != "" {
		value, err := strconv.Atoi(port)
		if err != nil || value < 1 || value > 65535 {
			return ""
		}
		port = strconv.Itoa(value)
	}
	if scheme == "http" && port == "80" || scheme == "https" && port == "443" {
		port = ""
	}
	if port != "" {
		host = net.JoinHostPort(host, port)
	} else if strings.Contains(host, ":") {
		host = "[" + host + "]"
	}
	return scheme + "://" + host
}

func (s *SchedulerDataSource) ResourceID(provider string) string {
	if provider == "ollama" {
		return "ollama"
	}
	origin := schedulerOrigin(provider)
	if origin == "" {
		return ""
	}
	if origin == s.ollamaOrigin {
		return "ollama"
	}
	digest := sha256.Sum256([]byte(origin))
	return "external:" + hex.EncodeToString(digest[:])
}

func schedulerLock(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `SELECT singleton FROM scheduler_settings WHERE singleton FOR UPDATE`)
	return err
}

func validSchedulerPipeline(pipeline string) bool {
	return slices.Contains([]string{"document_ingestion", "document_ai", "document_thumbnail", "chat", "email", "paperless"}, pipeline)
}

func (s *SchedulerDataSource) resourceRequirements(providers []string) ([]string, []r.SchedulerResourceRecord, error) {
	references := make([]m.SchedulerProviderResource, len(providers))
	for i, provider := range providers {
		references[i] = m.SchedulerProviderResource{ID: s.ResourceID(provider), Origin: schedulerOrigin(provider)}
	}
	resources, defaults, err := m.SchedulerResourceRequirements(references)
	return resources, schedulerResourceRecordsMapper(defaults), err
}

func (s *SchedulerDataSource) requirements(ctx context.Context, tx pgx.Tx, providers []string) ([]string, error) {
	resources, defaults, err := s.resourceRequirements(providers)
	if err != nil {
		return nil, err
	}
	for _, resource := range defaults {
		id := resource.ID
		var exists bool
		var count int
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM scheduler_resources WHERE id=$1),(SELECT count(*) FROM scheduler_resources)`, id).Scan(&exists, &count); err != nil {
			return nil, err
		}
		if !exists {
			if count >= m.SchedulerMaximumResources {
				return nil, m.SchedulerValidationError{Message: "workload provider resource limit reached"}
			}
			if _, err := tx.Exec(ctx, `INSERT INTO scheduler_resources(id,label,origin,concurrency_limit) VALUES($1,$2,$2,$3)`, id, resource.Label, resource.Limit); err != nil {
				return nil, err
			}
			if _, err := tx.Exec(ctx, `UPDATE scheduler_settings SET revision=revision+1 WHERE singleton`); err != nil {
				return nil, err
			}
		}
	}
	return resources, nil
}

func (s *SchedulerDataSource) Reserve(ctx context.Context, tx pgx.Tx, workflowID, pipeline string, providers []string) (bool, error) {
	if workflowID == "" || len(workflowID) > 512 || !validSchedulerPipeline(pipeline) {
		return false, m.SchedulerValidationError{Message: "invalid workload identity"}
	}
	if err := schedulerLock(ctx, tx); err != nil {
		return false, fmt.Errorf("lock workload scheduler: %w", err)
	}
	if err := prepareSchedulerAdmission(ctx, tx); err != nil {
		return false, err
	}
	return s.reservePrepared(ctx, tx, workflowID, pipeline, providers)
}

func prepareSchedulerAdmission(ctx context.Context, tx pgx.Tx) error {
	if _, err := tx.Exec(ctx, "SET LOCAL jit=off"); err != nil {
		return err
	}
	var initialized bool
	if err := tx.QueryRow(ctx, `SELECT initialized FROM scheduler_settings WHERE singleton`).Scan(&initialized); err != nil {
		return err
	}
	if !initialized {
		return errors.New("workload scheduler has not initialized retained ownership")
	}
	return reconcileScheduler(ctx, tx)
}

func (s *SchedulerDataSource) ReserveFirst(ctx context.Context, tx pgx.Tx, pipeline string, candidates []m.SchedulerAdmissionCandidate) (string, error) {
	if !validSchedulerPipeline(pipeline) || len(candidates) > m.SchedulerMaximumAdmissionCandidates {
		return "", m.SchedulerValidationError{Message: "invalid workload candidates"}
	}
	seen := make(map[string]bool, len(candidates))
	for _, candidate := range candidates {
		if candidate.WorkflowID == "" || len(candidate.WorkflowID) > 512 || seen[candidate.WorkflowID] {
			return "", m.SchedulerValidationError{Message: "invalid workload identity"}
		}
		seen[candidate.WorkflowID] = true
	}
	if len(candidates) == 0 {
		return "", nil
	}
	var singleton bool
	err := tx.QueryRow(ctx, "SELECT singleton FROM scheduler_settings WHERE singleton FOR UPDATE SKIP LOCKED").Scan(&singleton)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("try workload scheduler: %w", err)
	}
	if err = prepareSchedulerAdmission(ctx, tx); err != nil {
		return "", err
	}
	for _, candidate := range candidates {
		admitted, err := s.reservePrepared(ctx, tx, candidate.WorkflowID, pipeline, candidate.Providers)
		if err != nil {
			return "", err
		}
		if admitted {
			return candidate.WorkflowID, nil
		}
	}
	return "", nil
}

func (s *SchedulerDataSource) reservePrepared(ctx context.Context, tx pgx.Tx, workflowID, pipeline string, providers []string) (bool, error) {
	resources, err := s.requirements(ctx, tx, providers)
	if err != nil {
		return false, err
	}
	if err = putSchedulerRequest(ctx, tx, workflowID, pipeline, resources, false); err != nil {
		return false, err
	}
	var state string
	if err = tx.QueryRow(ctx, `SELECT state FROM scheduler_requests WHERE workflow_id=$1`, workflowID).Scan(&state); err != nil {
		return false, err
	}
	if state == "active" {
		return true, nil
	}
	if state == "released" {
		return false, nil
	}
	var blocked bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM scheduler_requests WHERE state='active' AND blocks_admission)`).Scan(&blocked); err != nil {
		return false, err
	}
	if blocked {
		return false, nil
	}
	var fits, older bool
	if err = tx.QueryRow(ctx, `WITH active_usage AS (
 SELECT rr.resource_id,count(*) AS active FROM scheduler_requests q
 JOIN scheduler_request_resources rr ON rr.workflow_id=q.workflow_id WHERE q.state='active' GROUP BY rr.resource_id
), usage AS (
 SELECT r.id,r.concurrency_limit,COALESCE(a.active,0) AS active
 FROM scheduler_resources r LEFT JOIN active_usage a ON a.resource_id=r.id
), feasible AS (
 SELECT q.workflow_id,q.sequence FROM scheduler_requests q WHERE q.state='waiting'
 AND NOT EXISTS(SELECT 1 FROM scheduler_request_resources rr JOIN usage u ON u.id=rr.resource_id
 WHERE rr.workflow_id=q.workflow_id AND u.active>=u.concurrency_limit)
)
SELECT EXISTS(SELECT 1 FROM feasible WHERE workflow_id=$1),EXISTS(SELECT 1 FROM feasible WHERE sequence<(SELECT sequence FROM scheduler_requests WHERE workflow_id=$1))`, workflowID).Scan(&fits, &older); err != nil {
		return false, err
	}
	if !m.SchedulerCanAdmit(state, blocked, fits, older) {
		return false, nil
	}
	_, err = tx.Exec(ctx, `UPDATE scheduler_requests SET state='active',admitted_at=clock_timestamp() WHERE workflow_id=$1`, workflowID)
	return err == nil, err
}

func putSchedulerRequest(ctx context.Context, tx pgx.Tx, workflowID, pipeline string, resources []string, active bool) error {
	state := "waiting"
	if active {
		state = "active"
	}
	tag, err := tx.Exec(ctx, `INSERT INTO scheduler_requests(workflow_id,pipeline,state,admitted_at) VALUES($1,$2,$3,CASE WHEN $3='active' THEN clock_timestamp() END) ON CONFLICT(workflow_id) DO NOTHING`, workflowID, pipeline, state)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		var existingPipeline string
		var existingResources []string
		var blocksAdmission bool
		if err := tx.QueryRow(ctx, `SELECT pipeline,ARRAY(SELECT resource_id FROM scheduler_request_resources WHERE workflow_id=$1 ORDER BY resource_id),blocks_admission AND state='active' FROM scheduler_requests WHERE workflow_id=$1`, workflowID).Scan(&existingPipeline, &existingResources, &blocksAdmission); err != nil {
			return err
		}
		if existingPipeline != pipeline || !blocksAdmission && !slices.Equal(existingResources, resources) {
			return errors.New("workload resource requirements changed after acceptance")
		}
		return nil
	}
	for _, resource := range resources {
		if _, err := tx.Exec(ctx, `INSERT INTO scheduler_request_resources(workflow_id,resource_id) VALUES($1,$2)`, workflowID, resource); err != nil {
			return err
		}
	}
	return nil
}
