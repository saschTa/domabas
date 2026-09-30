package imap

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/domabas/domabas/backend/tests/imapfixture"
)

func TestVerifiedTLSFixtureStreamsOriginal(t *testing.T) {
	directory := t.TempDir()
	if err := os.Chmod(directory, 0700); err != nil {
		t.Fatal(err)
	}
	fixture, err := imapfixture.Start(directory, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer fixture.Close()
	gateway, err := NewEmailIMAPDataSource(fixture.Ready.CAFile, []string{"127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	session, err := gateway.Connect(ctx, m.EmailConnection{Host: fixture.Ready.Host, Port: fixture.Ready.Port, Mailbox: "INBOX", Credentials: m.EmailCredentials{Username: fixture.Ready.Username, Password: fixture.Ready.Password}})
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	if session.Info().UIDNext != 2 {
		t.Fatal(session.Info())
	}
	discovery, err := session.Discover(ctx, 1, 1, time.Now().Add(-time.Hour))
	if err != nil || len(discovery.UIDs) != 1 || discovery.UIDs[0] != 1 {
		t.Fatalf("UID discovery %v: %v", discovery.UIDs, err)
	}
	var original bytes.Buffer
	message, err := session.Fetch(ctx, 1, func(message m.EmailMessage) error { _, err := io.Copy(&original, message.Reader); return err })
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(original.String(), "searchable body") || message.UID != 1 || message.InternalDate.IsZero() {
		t.Fatalf("invalid streamed message %#v", message)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("close healthy session: %T %v", err, err)
	}
}

func TestConnectionOnlyClosesCleanly(t *testing.T) {
	directory := t.TempDir()
	if err := os.Chmod(directory, 0700); err != nil {
		t.Fatal(err)
	}
	fixture, err := imapfixture.Start(directory, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer fixture.Close()
	gateway, err := NewEmailIMAPDataSource(fixture.Ready.CAFile, []string{fixture.Ready.Host})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	session, err := gateway.Connect(ctx, m.EmailConnection{Host: fixture.Ready.Host, Port: fixture.Ready.Port, Mailbox: fixture.Ready.Mailbox, Credentials: m.EmailCredentials{Username: fixture.Ready.Username, Password: fixture.Ready.Password}})
	if err != nil {
		t.Fatal(err)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("close healthy connection: %T %v", err, err)
	}
}
func TestGuardRejectsUnsafeLiteralBeforeExposingPrefix(t *testing.T) {
	for _, prefix := range []string{"* 1 FETCH (ENVELOPE {70000}\r\n", "* 1 FETCH (BODYSTRUCTURE (BODY[] {70000}\r\n", "* 1 FETCH (BODY[TEXT] {70000}\r\n", "* OK BODY[] {70000}\r\n", "* 1 FETCH (BODY[] {99999999999999999999999999}\r\n"} {
		t.Run(prefix, func(t *testing.T) {
			client, server := net.Pipe()
			defer client.Close()
			guard := NewEmailIMAPConnectionGuard(client)
			guard.Body(1)
			go func() {
				defer server.Close()
				for _, value := range []byte(prefix) {
					if _, err := server.Write([]byte{value}); err != nil {
						return
					}
				}
			}()
			output, err := io.ReadAll(guard)
			if err == nil || len(output) != 0 {
				t.Fatalf("rejected prefix reached parser: %q, %v", output, err)
			}
		})
	}
}
func TestGuardAcceptsUIDAfterBodyAndRejectsWrongUID(t *testing.T) {
	for _, uid := range []int{1, 2} {
		t.Run(fmt.Sprint(uid), func(t *testing.T) {
			client, server := net.Pipe()
			defer client.Close()
			guard := NewEmailIMAPConnectionGuard(client)
			guard.Body(1)
			response := fmt.Sprintf("* 1 FETCH (BODY[] {4}\r\nmail UID %d RFC822.SIZE 4 INTERNALDATE \"18-Sep-2026 00:00:00 +0000\")\r\n", uid)
			go func() {
				defer server.Close()
				for _, value := range []byte(response) {
					if _, err := server.Write([]byte{value}); err != nil {
						return
					}
				}
			}()
			output, err := io.ReadAll(guard)
			if uid == 1 && (err != nil || string(output) != response) {
				t.Fatalf("valid late UID rejected: %v", err)
			}
			if uid == 2 && err == nil {
				t.Fatal("wrong UID accepted")
			}
		})
	}
}
