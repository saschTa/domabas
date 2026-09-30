package imap

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"reflect"
	"strconv"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/domabas/domabas/backend/tests/imapfixture"
)

func imapFallbackAddresses() []net.IPAddr {
	return []net.IPAddr{{IP: net.ParseIP("2001:db8::1")}, {IP: net.ParseIP("192.0.2.2")}}
}

func imapFallbackGateway(t *testing.T) *EmailIMAPDataSource {
	t.Helper()
	gateway, err := NewEmailIMAPDataSource("", nil)
	if err != nil {
		t.Fatal(err)
	}
	gateway.lookupIPAddr = func(context.Context, string) ([]net.IPAddr, error) {
		return imapFallbackAddresses(), nil
	}
	return gateway
}

func TestIMAPFallbackUsesValidatedAddressesAndVerifiedHostname(t *testing.T) {
	for _, scenario := range []string{"refused", "stalled", "wrong_hostname"} {
		t.Run(scenario, func(t *testing.T) {
			directory := t.TempDir()
			if err := os.Chmod(directory, 0700); err != nil {
				t.Fatal(err)
			}
			fixture, err := imapfixture.Start(directory, "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = fixture.Close() })
			gateway, err := NewEmailIMAPDataSource(fixture.Ready.CAFile, nil)
			if err != nil {
				t.Fatal(err)
			}
			host := "localhost"
			if scenario == "wrong_hostname" {
				host = "different.example.test"
			}
			resolutions := 0
			gateway.lookupIPAddr = func(ctx context.Context, name string) ([]net.IPAddr, error) {
				resolutions++
				if name != host {
					t.Fatalf("resolved %q instead of configured hostname %q", name, host)
				}
				return imapFallbackAddresses(), nil
			}
			var attempts []string
			gateway.dialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
				attempts = append(attempts, address)
				if network != "tcp" {
					t.Fatalf("unexpected network %q", network)
				}
				if len(attempts) == 1 {
					if scenario == "stalled" {
						<-ctx.Done()
						return nil, ctx.Err()
					}
					return nil, errors.New("first candidate refused")
				}
				return (&net.Dialer{}).DialContext(ctx, network, net.JoinHostPort(fixture.Ready.Host, strconv.Itoa(fixture.Ready.Port)))
			}
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			session, err := gateway.Connect(ctx, m.EmailConnection{
				Host: host, Port: fixture.Ready.Port, Mailbox: fixture.Ready.Mailbox,
				Credentials: m.EmailCredentials{Username: fixture.Ready.Username, Password: fixture.Ready.Password},
			})
			if session != nil {
				t.Cleanup(func() { _ = session.Close() })
			}
			if scenario == "wrong_hostname" {
				var failure m.EmailFailure
				if !errors.As(err, &failure) || failure.Code != "tls_failed" || session != nil {
					t.Fatalf("fallback bypassed hostname validation: %v", err)
				}
			} else if err != nil || session.Info().UIDNext != 2 {
				t.Fatalf("second approved IP did not establish a mailbox session: %v", err)
			}
			port := strconv.Itoa(fixture.Ready.Port)
			expected := []string{net.JoinHostPort("2001:db8::1", port), net.JoinHostPort("192.0.2.2", port)}
			if resolutions != 1 || !reflect.DeepEqual(attempts, expected) {
				t.Fatalf("resolved %d times and dialed %v; expected one resolution and %v", resolutions, attempts, expected)
			}
		})
	}
}

func TestIMAPFallbackRejectsEntireUnsafeResolutionBeforeDialing(t *testing.T) {
	for _, denied := range []string{"127.0.0.1", "10.0.0.1", "169.254.169.254", "::", "224.0.0.1", "invalid"} {
		t.Run(denied, func(t *testing.T) {
			gateway := imapFallbackGateway(t)
			gateway.lookupIPAddr = func(context.Context, string) ([]net.IPAddr, error) {
				return []net.IPAddr{{IP: net.ParseIP("192.0.2.2")}, {IP: net.ParseIP(denied)}}, nil
			}
			gateway.dialContext = func(context.Context, string, string) (net.Conn, error) {
				t.Fatal("dialed before rejecting a disallowed DNS answer")
				return nil, nil
			}
			independentFailure(t, gateway, m.EmailConnection{Host: "mail.example.test", Port: 993}, "destination_not_allowed")
		})
	}
}

func TestIMAPFallbackReportsAllAddressFailuresWithinOneBudget(t *testing.T) {
	gateway := imapFallbackGateway(t)
	var deadlines []time.Time
	gateway.dialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
		deadline, ok := ctx.Deadline()
		if !ok {
			t.Fatal("dial has no connection deadline")
		}
		deadlines = append(deadlines, deadline)
		return nil, errors.New("candidate refused")
	}
	started := time.Now()
	_, err := gateway.Connect(t.Context(), m.EmailConnection{Host: "mail.example.test", Port: 993})
	var failure m.EmailFailure
	if !errors.As(err, &failure) || failure.Code != "connection_failed" || !failure.Retryable {
		t.Fatalf("all-address failure lost retryable connection outcome: %v", err)
	}
	if len(deadlines) != 2 || !deadlines[0].Before(deadlines[1]) || deadlines[1].Sub(started) > 10*time.Second+100*time.Millisecond {
		t.Fatalf("connection budget was not divided among candidates: %v", deadlines)
	}
}

func TestIMAPFallbackHonorsCallerDeadlineAcrossStalledCandidates(t *testing.T) {
	gateway := imapFallbackGateway(t)
	attempts := 0
	ctx, cancel := context.WithTimeout(t.Context(), 200*time.Millisecond)
	defer cancel()
	callerDeadline, _ := ctx.Deadline()
	gateway.dialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
		attempts++
		deadline, ok := ctx.Deadline()
		if !ok || deadline.After(callerDeadline) || attempts == 1 && !deadline.Before(callerDeadline) {
			t.Fatalf("attempt %d did not share the caller deadline", attempts)
		}
		<-ctx.Done()
		return nil, ctx.Err()
	}
	started := time.Now()
	_, err := gateway.Connect(ctx, m.EmailConnection{Host: "mail.example.test", Port: 993})
	if !errors.Is(err, context.DeadlineExceeded) || attempts != 2 || time.Since(started) > time.Second {
		t.Fatalf("fallback exceeded the shared deadline: attempts=%d elapsed=%v err=%v", attempts, time.Since(started), err)
	}
}

func TestIMAPFallbackStopsAfterCancellation(t *testing.T) {
	for _, stage := range []string{"before_resolution", "resolution", "dial", "connected"} {
		t.Run(stage, func(t *testing.T) {
			gateway := imapFallbackGateway(t)
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			if stage == "before_resolution" {
				cancel()
			}
			gateway.lookupIPAddr = func(context.Context, string) ([]net.IPAddr, error) {
				if stage == "before_resolution" {
					t.Fatal("resolved after cancellation")
				}
				if stage == "resolution" {
					cancel()
					return nil, ctx.Err()
				}
				return imapFallbackAddresses(), nil
			}
			attempts := 0
			var peer net.Conn
			gateway.dialContext = func(context.Context, string, string) (net.Conn, error) {
				attempts++
				if stage == "resolution" || attempts > 1 {
					t.Fatal("dialed after cancellation")
				}
				cancel()
				if stage == "connected" {
					var raw net.Conn
					raw, peer = net.Pipe()
					t.Cleanup(func() { _ = raw.Close(); _ = peer.Close() })
					return raw, nil
				}
				return nil, ctx.Err()
			}
			session, err := gateway.Connect(ctx, m.EmailConnection{Host: "mail.example.test", Port: 993})
			if !errors.Is(err, context.Canceled) || session != nil {
				t.Fatalf("cancellation returned a mailbox or wrong error: %v", err)
			}
			if peer != nil {
				_ = peer.SetReadDeadline(time.Now().Add(time.Second))
				if _, err := peer.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
					t.Fatalf("cancelled connection was not closed: %v", err)
				}
			}
		})
	}
}
