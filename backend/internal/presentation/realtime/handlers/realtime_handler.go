package handlers

import (
	"bufio"
	"context"
	"encoding/base64"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/contract"
	"github.com/domabas/domabas/backend/internal/presentation/httpapi/transport"
	m "github.com/domabas/domabas/backend/internal/presentation/realtime/models"
)

type RealtimeHandler struct{ supervisor *RealtimeSupervisor }

func NewRealtimeHandler(supervisor *RealtimeSupervisor) *RealtimeHandler {
	return &RealtimeHandler{supervisor: supervisor}
}

type realtimeStreamResponse struct {
	supervisor *RealtimeSupervisor
	request    *http.Request
}

func (h *RealtimeHandler) OpenRealtime(ctx context.Context, _ contract.OpenRealtimeRequestObject) (contract.OpenRealtimeResponseObject, error) {
	return realtimeStreamResponse{supervisor: h.supervisor, request: m.Request(ctx)}, nil
}

type realtimeUpgradeWriter struct {
	http.ResponseWriter
	conn      net.Conn
	committed bool
	status    int
}
type realtimeSafeConnection struct{ net.Conn }

func (c *realtimeSafeConnection) Close() (err error) {
	defer func() {
		if recover() != nil {
			err = net.ErrClosed
		}
	}()
	return c.Conn.Close()
}

func (w *realtimeUpgradeWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }
func (w *realtimeUpgradeWriter) WriteHeader(status int) {
	if status == 101 {
		w.committed = true
		w.ResponseWriter.WriteHeader(status)
	} else {
		w.status = status
	}
}
func (w *realtimeUpgradeWriter) Write(body []byte) (int, error) {
	if !w.committed {
		return len(body), nil
	}
	return w.ResponseWriter.Write(body)
}
func (w *realtimeUpgradeWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	conn, b, err := http.NewResponseController(w.ResponseWriter).Hijack()
	if conn != nil {
		w.conn = &realtimeSafeConnection{conn}
	}
	return w.conn, b, err
}
func (r realtimeStreamResponse) VisitOpenRealtimeResponse(w http.ResponseWriter) (err error) {
	writer := &realtimeUpgradeWriter{ResponseWriter: w}
	var client *realtimeConnection
	defer func() {
		if recover() != nil && !writer.committed {
			transport.WriteError(w, 503, "unavailable", "live updates are unavailable")
		}
		err = nil
	}()
	defer func() {
		if client != nil {
			client.supervisor.release(client)
		}
	}()
	defer func() {
		if writer.conn != nil {
			_ = writer.conn.Close()
		}
	}()
	if r.supervisor == nil || r.request == nil {
		transport.WriteError(w, 503, "unavailable", "live updates are unavailable")
		return nil
	}
	var status int
	client, status = r.supervisor.reserve()
	if status != 0 {
		if status == 429 {
			w.Header().Set("Retry-After", "1")
		}
		transport.WriteError(w, status, "unavailable", "live updates are unavailable")
		return nil
	}
	if status = validateHandshake(r.request, r.supervisor.origins); status != 0 {
		transport.WriteError(w, status, "invalid_request", "WebSocket handshake is invalid")
		return nil
	}
	controller := http.NewResponseController(w)
	deadline := time.Now().Add(5 * time.Second)
	if controller.SetReadDeadline(deadline) != nil || controller.SetWriteDeadline(deadline) != nil {
		transport.WriteError(w, 503, "unavailable", "live updates are unavailable")
		return nil
	}
	interrupted := make(chan struct{})
	interruptHandshake := context.AfterFunc(client.ctx, func() {
		defer func() { _ = recover(); close(interrupted) }()
		_ = controller.SetReadDeadline(time.Now())
		_ = controller.SetWriteDeadline(time.Now())
	})
	var stopOnce sync.Once
	stopHandshake := func() {
		stopOnce.Do(func() {
			if !interruptHandshake() {
				<-interrupted
			}
		})
	}
	defer stopHandshake()
	stop := context.AfterFunc(r.request.Context(), func() { client.stop(1001) })
	defer stop()
	socket, acceptErr := websocket.Accept(writer, r.request, &websocket.AcceptOptions{Subprotocols: []string{"domabas.realtime.v1"}, InsecureSkipVerify: true, CompressionMode: websocket.CompressionDisabled})
	if acceptErr != nil {
		if !writer.committed {
			transport.WriteError(w, 400, "invalid_request", "WebSocket handshake is invalid")
		}
		return nil
	}
	client.socket = socket
	stopHandshake()
	if writer.conn == nil || writer.conn.SetDeadline(time.Time{}) != nil {
		_ = socket.CloseNow()
		return nil
	}
	client.serve(writer.conn)
	return nil
}
func headerToken(r *http.Request, header, token string) bool {
	for _, value := range r.Header.Values(header) {
		for _, part := range strings.Split(value, ",") {
			if strings.EqualFold(strings.TrimSpace(part), token) {
				return true
			}
		}
	}
	return false
}
func validateHandshake(r *http.Request, origins []string) int {
	if r.Method != "GET" || r.ProtoMajor != 1 || r.ProtoMinor < 1 || r.URL.RawQuery != "" || r.URL.ForceQuery || r.ContentLength != 0 || len(r.TransferEncoding) > 0 || !headerToken(r, "Connection", "upgrade") || !headerToken(r, "Upgrade", "websocket") {
		return 400
	}
	if values := r.Header.Values("Sec-WebSocket-Version"); len(values) != 1 || values[0] != "13" {
		return 400
	}
	keys := r.Header.Values("Sec-WebSocket-Key")
	if len(keys) != 1 {
		return 400
	}
	key, err := base64.StdEncoding.DecodeString(keys[0])
	if err != nil || len(key) != 16 || base64.StdEncoding.EncodeToString(key) != keys[0] {
		return 400
	}
	protocols := r.Header.Values("Sec-WebSocket-Protocol")
	if len(protocols) != 1 || protocols[0] != "domabas.realtime.v1" {
		return 400
	}
	values := r.Header.Values("Origin")
	if len(values) == 0 {
		return 0
	}
	if len(values) != 1 {
		return 403
	}
	origin, ok := canonicalOrigin(values[0])
	if !ok {
		return 403
	}
	for _, allowed := range origins {
		if normalized, ok := canonicalOrigin(allowed); ok && origin == normalized {
			return 0
		}
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	same, ok := canonicalOrigin(scheme + "://" + r.Host)
	if ok && same == origin {
		return 0
	}
	return 403
}
func canonicalOrigin(raw string) (string, bool) {
	if strings.ContainsAny(raw, "?#") || strings.TrimSpace(raw) != raw {
		return "", false
	}
	v, err := url.Parse(raw)
	if err != nil || v.User != nil || v.Opaque != "" || v.Host == "" || v.Path != "" || (v.Scheme != "http" && v.Scheme != "https") {
		return "", false
	}
	port := v.Port()
	if port == "" {
		if v.Scheme == "https" {
			port = "443"
		} else {
			port = "80"
		}
	}
	return v.Scheme + "://" + net.JoinHostPort(strings.ToLower(v.Hostname()), port), true
}
