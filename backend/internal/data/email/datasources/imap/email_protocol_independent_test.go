package imap

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"runtime"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/emersion/go-imap/v2/imapclient"
)

func independentSession(t *testing.T, respond func(net.Conn, string)) (*EmailIMAPSession, context.Context) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	client, server := net.Pipe()
	guard := NewEmailIMAPConnectionGuard(client)
	session := &EmailIMAPSession{guard: guard, ctx: ctx, cancel: cancel, unsolicited: make(chan *imapclient.FetchMessageData, 1)}
	session.stop = context.AfterFunc(ctx, func() { _ = guard.Close() })
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer server.Close()
		if _, err := io.WriteString(server, "* OK [CAPABILITY IMAP4rev1] fixture\r\n"); err != nil {
			return
		}
		line, err := bufio.NewReader(server).ReadString('\n')
		if err == nil {
			respond(server, line)
		}
	}()
	session.client = imapclient.New(guard, &imapclient.Options{UnilateralDataHandler: &imapclient.UnilateralDataHandler{Fetch: session.unilateral}})
	t.Cleanup(func() {
		cancel()
		_ = server.Close()
		_ = session.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("scripted protocol peer did not stop")
		}
	})
	if err := session.client.WaitGreeting(); err != nil {
		t.Fatal(err)
	}
	return session, ctx
}

func TestIndependentClientStreamsBODYBeforeUIDButRejectsForeignIdentity(t *testing.T) {
	for _, returnedUID := range []int{17, 18} {
		t.Run(fmt.Sprint(returnedUID), func(t *testing.T) {
			session, ctx := independentSession(t, func(peer net.Conn, command string) {
				tag := strings.Fields(command)[0]
				_, _ = fmt.Fprintf(peer, "* 1 FETCH (BODY[] {4}\r\nmail UID %d RFC822.SIZE 4 INTERNALDATE \"18-Sep-2026 00:00:00 +0000\")\r\n%s OK fetched\r\n", returnedUID, tag)
			})
			var staged strings.Builder
			message, err := session.Fetch(ctx, 17, func(message m.EmailMessage) error {
				_, err := io.Copy(&staged, message.Reader)
				return err
			})
			if returnedUID == 17 && (err != nil || staged.String() != "mail" || message.UID != 17 || message.InternalDate.IsZero()) {
				t.Fatalf("lawful BODY-before-UID failed: body=%q result=%+v err=%v", staged.String(), message, err)
			}
			if returnedUID != 17 && err == nil {
				t.Fatal("foreign UID was accepted after quarantined body streaming")
			}
		})
	}
}

func TestIndependentDiscoveryRejectsUnboundedESEARCHBeforeExpansion(t *testing.T) {
	for _, values := range []string{"1:4294967295", "1:*", "0", "1001", "1:99999999999999999999"} {
		t.Run(values, func(t *testing.T) {
			session, ctx := independentSession(t, func(peer net.Conn, command string) {
				tag := strings.Fields(command)[0]
				_, _ = fmt.Fprintf(peer, "* ESEARCH (TAG %q) UID ALL %s\r\n%s OK searched\r\n", tag, values, tag)
			})
			before := time.Now()
			values, err := session.Discover(ctx, 1, 1000, time.Now())
			if err == nil || len(values.UIDs) != 0 {
				t.Fatalf("unsafe search result expanded/accepted: %v %v", values, err)
			}
			if time.Since(before) > time.Second {
				t.Fatal("invalid finite range was not rejected promptly")
			}
		})
	}
}

func TestIndependentFetchWaitsForTaggedAcknowledgment(t *testing.T) {
	session, lifetime := independentSession(t, func(peer net.Conn, command string) {
		_, _ = io.WriteString(peer, "* 1 FETCH (UID 17 RFC822.SIZE 4 INTERNALDATE \"18-Sep-2026 00:00:00 +0000\" BODY[] {4}\r\nmail)\r\n")
		_, _ = io.Copy(io.Discard, peer)
	})
	ctx, cancel := context.WithTimeout(lifetime, 100*time.Millisecond)
	defer cancel()
	_, err := session.Fetch(ctx, 17, func(message m.EmailMessage) error {
		_, err := io.Copy(io.Discard, message.Reader)
		return err
	})
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("unacknowledged FETCH was not cancelled: %v", err)
	}
}

func TestIndependentFetchCancelsStalledLiteralUsingOperationContext(t *testing.T) {
	session, lifetime := independentSession(t, func(peer net.Conn, command string) {
		_, _ = io.WriteString(peer, "* 1 FETCH (UID 17 RFC822.SIZE 1024 INTERNALDATE \"18-Sep-2026 00:00:00 +0000\" BODY[] {1024}\r\npart")
		_, _ = io.Copy(io.Discard, peer)
	})
	ctx, cancel := context.WithTimeout(lifetime, 100*time.Millisecond)
	defer cancel()
	started := time.Now()
	_, err := session.Fetch(ctx, 17, func(message m.EmailMessage) error {
		_, err := io.Copy(io.Discard, message.Reader)
		return err
	})
	if err == nil || time.Since(started) > time.Second {
		t.Fatalf("operation cancellation failed to stop stalled literal promptly: elapsed=%v err=%v", time.Since(started), err)
	}
}

func TestIndependentGuardBoundsAggregateFramesTokensAndLiterals(t *testing.T) {
	cases := []struct {
		name, input string
	}{
		{"frames", strings.Repeat("* OK alive\r\n", 4097)},
		{"connection_tokens", strings.Repeat("* OK a b c d e f g h i j\r\n", 3000)},
		{"single_frame_tokens", "* SEARCH " + strings.Repeat("1 ", 4097) + "\r\n"},
		{"many_literals", "* LIST (" + strings.Repeat("{0}\r\n", 129) + ")\r\n"},
		{"nonliteral_frame", "* OK " + strings.Repeat("a ", 33000) + "\r\n"},
		{"nested_lists", "* X " + strings.Repeat("(", 33) + strings.Repeat(")", 33) + "\r\n"},
		{"quoted_string", "* OK \"" + strings.Repeat("x", 8193) + "\"\r\n"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, server := net.Pipe()
			defer client.Close()
			go func() { defer server.Close(); _, _ = io.WriteString(server, tc.input) }()
			_, err := io.Copy(io.Discard, NewEmailIMAPConnectionGuard(client))
			if !errors.Is(err, ErrProtocolLimit) {
				t.Fatalf("missing %s bound: %v", tc.name, err)
			}
		})
	}
}

func TestIndependentClientRejectsNonBODYLiteralBeforeConsumer(t *testing.T) {
	session, ctx := independentSession(t, func(peer net.Conn, command string) {
		_, _ = io.WriteString(peer, "* 1 FETCH (UID 17 ENVELOPE {20971520}\r\n")
		_, _ = io.Copy(io.Discard, peer)
	})
	called := false
	_, err := session.Fetch(ctx, 17, func(message m.EmailMessage) error { called = true; return nil })
	if err == nil || called {
		t.Fatalf("untrusted allocated attribute reached body consumer: called=%v err=%v", called, err)
	}
}

type independentRepeatedByte byte

func (r independentRepeatedByte) Read(buffer []byte) (int, error) {
	for index := range buffer {
		buffer[index] = byte(r)
	}
	return len(buffer), nil
}

func TestIndependentMaximumBODYStreamsWithoutWholeLiteralAllocation(t *testing.T) {
	const literalBytes = 100 << 20
	session, ctx := independentSession(t, func(peer net.Conn, command string) {
		tag := strings.Fields(command)[0]
		if _, err := fmt.Fprintf(peer, "* 1 FETCH (BODY[] {%d}\r\n", literalBytes); err != nil {
			return
		}
		if _, err := io.CopyN(peer, independentRepeatedByte('m'), literalBytes); err != nil {
			return
		}
		_, _ = fmt.Fprintf(peer, " UID 17 RFC822.SIZE %d INTERNALDATE \"18-Sep-2026 00:00:00 +0000\")\r\n%s OK fetched\r\n", literalBytes, tag)
	})
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	var copied int64
	_, err := session.Fetch(ctx, 17, func(message m.EmailMessage) error {
		var err error
		copied, err = io.Copy(io.Discard, message.Reader)
		return err
	})
	runtime.ReadMemStats(&after)
	if err != nil || copied != literalBytes {
		t.Fatalf("maximum supported literal did not stream: bytes=%d err=%v", copied, err)
	}
	if allocated := after.TotalAlloc - before.TotalAlloc; allocated > 8<<20 {
		t.Fatalf("streaming one literal allocated %d bytes; body-sized buffering returned", allocated)
	}
}
