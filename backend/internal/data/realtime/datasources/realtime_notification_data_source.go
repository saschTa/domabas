package datasources

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"sync"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/realtime/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type RealtimeNotificationSink interface {
	Notify(r.RealtimeSignal)
	Health(bool)
}
type RealtimeNotificationDataSource struct {
	config    *pgx.ConnConfig
	cancel    context.CancelFunc
	done      chan struct{}
	closeOnce sync.Once
}

func NewRealtimeNotificationDataSource(databaseURL string) (*RealtimeNotificationDataSource, error) {
	config, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse realtime database configuration: %w", err)
	}
	config.ConnectTimeout = 5 * time.Second
	return &RealtimeNotificationDataSource{config: config, done: make(chan struct{})}, nil
}
func (s *RealtimeNotificationDataSource) open(ctx context.Context) (*pgx.Conn, string, error) {
	conn, err := pgx.ConnectConfig(ctx, s.config.Copy())
	if err != nil {
		return nil, "", err
	}
	var schema string
	if err = conn.QueryRow(ctx, "SELECT current_schema()").Scan(&schema); err == nil {
		digest := md5.Sum([]byte(schema))
		channel := "domabas_rt_" + hex.EncodeToString(digest[:])
		_, err = conn.Exec(ctx, "LISTEN "+pgx.Identifier{channel}.Sanitize())
	}
	if err != nil {
		closeCtx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = conn.Close(closeCtx)
		return nil, "", err
	}
	return conn, schema, nil
}
func (s *RealtimeNotificationDataSource) Start(ctx context.Context, sink RealtimeNotificationSink) error {
	conn, schema, err := s.open(ctx)
	if err != nil {
		return fmt.Errorf("start realtime listener: %w", err)
	}
	lifetime, cancel := context.WithCancel(context.Background())
	s.cancel = cancel
	sink.Health(true)
	go s.run(lifetime, sink, conn, schema)
	return nil
}
func (s *RealtimeNotificationDataSource) run(ctx context.Context, sink RealtimeNotificationSink, conn *pgx.Conn, schema string) {
	defer close(s.done)
	defer sink.Health(false)
	delay := 500 * time.Millisecond
	for {
		if conn != nil {
			raw := conn.PgConn().Conn()
			interrupted := make(chan struct{})
			stop := context.AfterFunc(ctx, func() { defer close(interrupted); _ = raw.Close() })
			_ = s.receive(ctx, sink, conn, schema)
			if !stop() {
				<-interrupted
			}
			closeCtx, cancel := context.WithTimeout(context.Background(), time.Second)
			_ = conn.Close(closeCtx)
			cancel()
			conn = nil
			sink.Health(false)
		}
		if ctx.Err() != nil {
			return
		}
		timer := time.NewTimer(delay + time.Duration(rand.Int64N(int64(delay/4)+1)))
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
		openCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		var err error
		conn, schema, err = s.open(openCtx)
		cancel()
		if err != nil {
			delay = min(delay*2, 15*time.Second)
			continue
		}
		delay = 500 * time.Millisecond
		sink.Health(true)
	}
}
func (s *RealtimeNotificationDataSource) receive(ctx context.Context, sink RealtimeNotificationSink, conn *pgx.Conn, schema string) error {
	next := time.Now().Add(10 * time.Second)
	for {
		if !time.Now().Before(next) {
			probe, cancel := context.WithTimeout(ctx, 2*time.Second)
			var one int
			err := conn.QueryRow(probe, "SELECT 1").Scan(&one)
			cancel()
			if err != nil {
				return err
			}
			next = time.Now().Add(10 * time.Second)
		}
		wait, cancel := context.WithDeadline(ctx, next)
		notification, err := conn.WaitForNotification(wait)
		cancel()
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err != nil {
			if errors.Is(err, context.DeadlineExceeded) && !conn.IsClosed() {
				continue
			}
			return err
		}
		if signal, ok := decodeSignal(notification.Payload, schema); ok {
			sink.Notify(signal)
		}
	}
}
func decodeSignal(payload, schema string) (r.RealtimeSignal, bool) {
	var v r.RealtimeSignal
	if len(payload) > 512 {
		return v, false
	}
	d := json.NewDecoder(bytes.NewBufferString(payload))
	d.DisallowUnknownFields()
	if d.Decode(&v) != nil || d.Decode(new(any)) != io.EOF || v.Version != 1 || v.Schema != schema {
		return v, false
	}
	valid := func(value string) bool {
		parsed, err := uuid.Parse(value)
		return err == nil && parsed.String() == value
	}
	if v.AccountID != "" && !valid(v.AccountID) {
		return v, false
	}
	if v.UserID != "" && !valid(v.UserID) {
		return v, false
	}
	switch v.Kind {
	case "documents", "document_job", "batch", "account", "members":
		return v, v.AccountID != ""
	case "email", "paperless", "chat":
		return v, v.AccountID != "" && v.UserID != ""
	case "authority", "member_user":
		return v, v.UserID != ""
	case "configuration", "system_users":
		return v, v.AccountID == "" && v.UserID == ""
	default:
		return v, false
	}
}
func (s *RealtimeNotificationDataSource) Close() {
	s.closeOnce.Do(func() {
		if s.cancel != nil {
			s.cancel()
			<-s.done
		}
	})
}
