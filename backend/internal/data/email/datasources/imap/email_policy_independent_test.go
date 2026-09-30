package imap

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/domabas/domabas/backend/tests/imapfixture"
)

func independentFailure(t *testing.T, gateway *EmailIMAPDataSource, connection m.EmailConnection, code string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	session, err := gateway.Connect(ctx, connection)
	if session != nil {
		session.Close()
	}
	var failure m.EmailFailure
	if !errors.As(err, &failure) || failure.Code != code {
		t.Fatalf("expected %s, got %v", code, err)
	}
}

func TestIndependentDestinationPolicyRequiresExplicitPrivateAndLiteralHosts(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "::1", "10.0.0.1", "169.254.169.254", "8.8.8.8"} {
		t.Run(host, func(t *testing.T) {
			gateway, err := NewEmailIMAPDataSource("", nil)
			if err != nil {
				t.Fatal(err)
			}
			independentFailure(t, gateway, m.EmailConnection{Host: host, Port: 993}, "destination_not_allowed")
		})
	}
	for _, host := range []string{"0.0.0.0", "::", "224.0.0.1", "ff02::1"} {
		t.Run("explicit_"+host, func(t *testing.T) {
			gateway, err := NewEmailIMAPDataSource("", []string{host})
			if err != nil {
				t.Fatal(err)
			}
			independentFailure(t, gateway, m.EmailConnection{Host: host, Port: 993}, "destination_not_allowed")
		})
	}
	gateway, err := NewEmailIMAPDataSource("", []string{"allowed.example.test"})
	if err != nil {
		t.Fatal(err)
	}
	independentFailure(t, gateway, m.EmailConnection{Host: "excluded.example.test", Port: 993}, "destination_not_allowed")
}

func TestIndependentPrivateTLSRequiresTrustedCAAndPreservesHostnameVerification(t *testing.T) {
	directory := t.TempDir()
	if err := os.Chmod(directory, 0700); err != nil {
		t.Fatal(err)
	}
	fixture, err := imapfixture.Start(directory, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = fixture.Close() })
	connection := m.EmailConnection{Host: fixture.Ready.Host, Port: fixture.Ready.Port, Mailbox: fixture.Ready.Mailbox, Credentials: m.EmailCredentials{Username: fixture.Ready.Username, Password: fixture.Ready.Password}}
	gateway, err := NewEmailIMAPDataSource(fixture.Ready.CAFile, []string{fixture.Ready.Host})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
	defer cancel()
	session, err := gateway.Connect(ctx, connection)
	if err != nil {
		t.Fatalf("explicit private host with trusted CA rejected: %v", err)
	}
	if err = session.Close(); err != nil {
		t.Fatal(err)
	}
	untrusted, err := NewEmailIMAPDataSource("", []string{fixture.Ready.Host})
	if err != nil {
		t.Fatal(err)
	}
	independentFailure(t, untrusted, connection, "tls_failed")
	otherDirectory := t.TempDir()
	if err := os.Chmod(otherDirectory, 0700); err != nil {
		t.Fatal(err)
	}
	other, err := imapfixture.Start(otherDirectory, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = other.Close() })
	wrongCA, err := NewEmailIMAPDataSource(other.Ready.CAFile, []string{fixture.Ready.Host})
	if err != nil {
		t.Fatal(err)
	}
	independentFailure(t, wrongCA, connection, "tls_failed")

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	certificate := &x509.Certificate{SerialNumber: big.NewInt(7), NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, DNSNames: []string{"different.example.test"}}
	der, err := x509.CreateCertificate(rand.Reader, certificate, certificate, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	caFile := filepath.Join(t.TempDir(), "wrong-host.pem")
	if err = os.WriteFile(caFile, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0600); err != nil {
		t.Fatal(err)
	}
	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}})
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
		_ = conn.(*tls.Conn).Handshake()
	}()
	t.Cleanup(func() { _ = listener.Close(); <-done })
	wrongName, err := NewEmailIMAPDataSource(caFile, []string{"127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	independentFailure(t, wrongName, m.EmailConnection{Host: "127.0.0.1", Port: listener.Addr().(*net.TCPAddr).Port}, "tls_failed")
}

func TestIndependentCAConfigurationFailsClosedForMissingInvalidAndOversizedFiles(t *testing.T) {
	directory := t.TempDir()
	for name, content := range map[string][]byte{"invalid.pem": []byte("not a certificate"), "oversized.pem": make([]byte, (1<<20)+1)} {
		if err := os.WriteFile(filepath.Join(directory, name), content, 0600); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range []string{"absent.pem", "invalid.pem", "oversized.pem"} {
		if _, err := NewEmailIMAPDataSource(filepath.Join(directory, name), nil); err == nil {
			t.Fatalf("accepted %s CA configuration", name)
		}
	}
}
