//go:build e2e

package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type crossProcessRealtimeFrame struct {
	kind   string
	topics []string
	at     time.Time
	err    error
}

type crossProcessRealtimeProbe struct {
	t      *testing.T
	frames <-chan crossProcessRealtimeFrame
}

func newCrossProcessRealtimeProbe(t *testing.T, base, token string, spec *openapi3.T) *crossProcessRealtimeProbe {
	t.Helper()
	ctx, cancel := context.WithCancel(t.Context())
	dialCtx, dialCancel := context.WithTimeout(ctx, 5*time.Second)
	defer dialCancel()
	connection, response, err := websocket.Dial(dialCtx, "ws"+strings.TrimPrefix(base, "http")+"/api/v1/realtime", &websocket.DialOptions{
		Subprotocols: []string{"domabas.realtime.v1"}, HTTPHeader: http.Header{"Origin": []string{base}},
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		cancel()
		status := 0
		if response != nil {
			status = response.StatusCode
			if response.Body != nil {
				_ = response.Body.Close()
			}
		}
		t.Fatalf("open realtime transport: status %d: %v", status, err)
	}
	connection.SetReadLimit(512)
	frames := make(chan crossProcessRealtimeFrame, 128)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			messageType, data, err := connection.Read(ctx)
			frame := crossProcessRealtimeFrame{at: time.Now(), err: err}
			if err == nil {
				var value map[string]any
				if messageType != websocket.MessageText || len(data) > 512 {
					frame.err = fmt.Errorf("unexpected realtime message type or size")
				} else if err := json.Unmarshal(data, &value); err != nil {
					frame.err = fmt.Errorf("decode realtime envelope: %w", err)
				} else {
					frame.kind, _ = value["type"].(string)
					schema := map[string]string{"ready": "RealtimeReady", "invalidate": "RealtimeInvalidation", "resync": "RealtimeResync", "heartbeat": "RealtimeHeartbeat"}[frame.kind]
					if schema == "" || spec.Components.Schemas[schema] == nil {
						frame.err = fmt.Errorf("realtime message has no canonical schema")
					} else if err := spec.Components.Schemas[schema].Value.VisitJSON(value); err != nil {
						frame.err = fmt.Errorf("realtime message violates canonical schema: %w", err)
					} else if topics, ok := value["topics"].([]any); ok {
						for _, topic := range topics {
							frame.topics = append(frame.topics, topic.(string))
						}
					}
				}
			}
			select {
			case frames <- frame:
			case <-ctx.Done():
				return
			}
			if frame.err != nil {
				return
			}
		}
	}()
	t.Cleanup(func() {
		cancel()
		_ = connection.CloseNow()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Error("realtime test reader did not stop")
		}
	})
	if connection.Subprotocol() != "domabas.realtime.v1" {
		t.Fatal("realtime subprotocol was not negotiated")
	}
	auth, err := json.Marshal(map[string]any{"type": "authenticate", "version": 1, "token": token})
	if err != nil {
		t.Fatal(err)
	}
	if err := connection.Write(dialCtx, websocket.MessageText, auth); err != nil {
		t.Fatalf("authenticate realtime transport: %v", err)
	}
	probe := &crossProcessRealtimeProbe{t: t, frames: frames}
	frame := probe.next(5 * time.Second)
	if frame.err != nil || frame.kind != "ready" || !slices.Contains(frame.topics, "documents") {
		t.Fatal("realtime connection did not provide the authorized initial baseline")
	}
	return probe
}

func (p *crossProcessRealtimeProbe) next(timeout time.Duration) crossProcessRealtimeFrame {
	p.t.Helper()
	select {
	case frame := <-p.frames:
		return frame
	case <-time.After(timeout):
		p.t.Fatal("realtime acceptance deadline exceeded")
	}
	return crossProcessRealtimeFrame{}
}

func (p *crossProcessRealtimeProbe) documents(timeout time.Duration) crossProcessRealtimeFrame {
	p.t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		frame := p.next(time.Until(deadline))
		if frame.err != nil {
			p.t.Fatalf("realtime reader failed: %v", frame.err)
		}
		if frame.kind == "invalidate" && slices.Contains(frame.topics, "documents") {
			return frame
		}
	}
}

func (p *crossProcessRealtimeProbe) settle() {
	p.t.Helper()
	quiet := time.NewTimer(500 * time.Millisecond)
	defer quiet.Stop()
	deadline := time.NewTimer(5 * time.Second)
	defer deadline.Stop()
	for {
		select {
		case frame := <-p.frames:
			if frame.err != nil {
				p.t.Fatalf("realtime settle failed: %v", frame.err)
			}
			quiet.Reset(500 * time.Millisecond)
		case <-quiet.C:
			return
		case <-deadline.C:
			p.t.Fatal("realtime notifications never settled")
		}
	}
}

func (p *crossProcessRealtimeProbe) expectClose(code websocket.StatusCode, since time.Time) {
	p.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		frame := p.next(time.Until(deadline))
		if frame.err == nil {
			continue
		}
		if (code != 0 && websocket.CloseStatus(frame.err) != code) || frame.at.Sub(since) > 5*time.Second {
			p.t.Fatalf("realtime close code/latency: %d after %s, expected %d within five seconds", websocket.CloseStatus(frame.err), frame.at.Sub(since), code)
		}
		return
	}
}

func TestRealtimeCrossProcessCommitRollbackWorkerRestartAndRevocation(t *testing.T) {
	databaseURL := testdb.New(t)
	environment := newServerEnvironment(t, databaseURL)
	name := "server"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	binary := filepath.Join(t.TempDir(), name)
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build realtime servers: %v\n%s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	baseA, stopA := startServer(t, binary, databaseURL, environment)
	baseB, _ := startServer(t, binary, databaseURL, environment)
	apiA := &ingestionAPI{t: t, baseURL: baseA, client: &http.Client{Timeout: 10 * time.Second}, spec: spec}
	apiB := &ingestionAPI{t: t, baseURL: baseB, client: &http.Client{Timeout: 10 * time.Second}, spec: spec}
	session := apiB.request("", "POST", "/api/v1/auth/register", `{"accountName":"Realtime cross process","email":"realtime@example.test","password":"Realtime integration password 2026!"}`, 201, "AuthSession")
	token := session["token"].(string)
	probe := newCrossProcessRealtimeProbe(t, baseA, token, spec)
	probe.settle()
	started := time.Now()
	document := apiB.request(token, "POST", "/api/v1/documents", `{"title":"Created on process B"}`, 201, "Document")
	id := document["id"].(string)
	frame := probe.documents(time.Second)
	if frame.at.Sub(started) > time.Second {
		t.Fatal("cross-process commit hint took more than one second")
	}
	if apiA.request(token, "GET", "/api/v1/documents/"+id, "", 200, "Document")["title"] != "Created on process B" {
		t.Fatal("hint preceded readable committed state")
	}
	probe.settle()
	db, err := pgx.Connect(t.Context(), databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close(context.Background())
	identity := session["identity"].(map[string]any)
	account := identity["account"].(map[string]any)["id"].(string)
	owner := identity["user"].(map[string]any)["id"].(string)
	run := uuid.NewString()
	if _, err := db.Exec(t.Context(), "INSERT INTO paperless_runs(id,account_id,owner_id,credential_revision,server_url,request_hash,task_queue,state,stage,execution_closed) VALUES($1,$2,$3,1,'https://example.test','test','realtime-test','succeeded','complete',true)", run, account, owner); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for {
		frame := probe.next(time.Until(deadline))
		if frame.err != nil {
			t.Fatal(frame.err)
		}
		if frame.kind == "invalidate" && slices.Contains(frame.topics, "paperless") {
			break
		}
	}
	page := apiA.request(token, "GET", "/api/v1/paperless-import/runs?activeOnly=true", "", 200, "PaperlessRunPage")
	if len(page["items"].([]any)) != 0 || len(page["counts"].(map[string]any)["groups"].([]any)) != 1 {
		t.Fatalf("Paperless active totals: %v", page)
	}
	conversation := uuid.NewString()
	if _, err := db.Exec(t.Context(), "INSERT INTO chat_conversations(id,account_id,owner_id,request_id) VALUES($1,$2,$3,$1)", conversation, account, owner); err != nil {
		t.Fatal(err)
	}
	deadline = time.Now().Add(3 * time.Second)
	for {
		frame := probe.next(time.Until(deadline))
		if frame.err != nil {
			t.Fatal(frame.err)
		}
		if frame.kind == "invalidate" && slices.Contains(frame.topics, "chat") {
			break
		}
	}
	probe.settle()
	tx, err := db.Begin(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(t.Context(), "UPDATE documents SET title=$1 WHERE id=$2", "Rolled back title", id); err != nil {
		_ = tx.Rollback(t.Context())
		t.Fatal(err)
	}
	if err := tx.Rollback(t.Context()); err != nil {
		t.Fatal(err)
	}
	quiet := time.NewTimer(750 * time.Millisecond)
	defer quiet.Stop()
rollbackSilence:
	for {
		select {
		case frame := <-probe.frames:
			if frame.err != nil {
				t.Fatal("realtime transport failed during rollback check")
			}
			if frame.kind == "invalidate" && slices.Contains(frame.topics, "documents") {
				t.Fatal("rolled-back document mutation emitted a hint")
			}
		case <-quiet.C:
			break rollbackSilence
		}
	}
	if apiA.request(token, "GET", "/api/v1/documents/"+id, "", 200, "Document")["title"] != "Created on process B" {
		t.Fatal("rollback changed the REST projection")
	}
	eml := []byte("From: sender@example.test\r\nTo: reader@example.test\r\nSubject: Realtime worker\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nRealtime transactional worker evidence.\r\n")
	uploaded := apiB.upload(token, "realtime.eml", eml, `{"title":"Realtime worker"}`, false, 202)
	uploadedID := uploaded["id"].(string)
	workerDeadline := time.Now().Add(90 * time.Second)
	for {
		probe.documents(time.Until(workerDeadline))
		processing := apiA.request(token, "GET", "/api/v1/documents/"+uploadedID+"/processing", "", 200, "DocumentProcessing")
		if processing["state"] == "failed" {
			t.Fatalf("realtime worker failed: %v", processing["failureCode"])
		}
		if processing["state"] == "ready" {
			if processing["extractionMethod"] != "mime" {
				t.Fatal("real worker did not report MIME extraction")
			}
			apiA.assertMatch(token, "transactional worker evidence", uploadedID)
			break
		}
	}
	probe.settle()
	shutdown := time.Now()
	stopA()
	shutdownCode := websocket.StatusGoingAway
	if runtime.GOOS == "windows" {
		shutdownCode = 0
	}
	probe.expectClose(shutdownCode, shutdown)
	apiB.request(token, "PATCH", "/api/v1/documents/"+id, `{"title":"Changed while subscriber was down"}`, 200, "Document")
	restartedA, _ := startServer(t, binary, databaseURL, environment)
	apiA.baseURL = restartedA
	reconnected := newCrossProcessRealtimeProbe(t, restartedA, token, spec)
	if apiA.request(token, "GET", "/api/v1/documents/"+id, "", 200, "Document")["title"] != "Changed while subscriber was down" {
		t.Fatal("reconnect baseline missed the disconnected interval")
	}
	reconnected.settle()
	revoked := time.Now()
	apiB.request(token, "DELETE", "/api/v1/auth/session", "", 204, "")
	reconnected.expectClose(websocket.StatusCode(4401), revoked)
}
