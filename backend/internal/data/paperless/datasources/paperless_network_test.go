package datasources

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

func TestUserURLsSupportPrivateHostsAndRejectUnsafeAddresses(t *testing.T) {
	for _, server := range []string{"https://paperless.example.test", "http://192.168.0.100:8000/paperless/", "http://localhost:8000", "http://127.0.0.1:8000", "https://[fd12::1234]:443", "http://paperless:8000"} {
		if _, err := normalizeServerURL(server); err != nil {
			t.Errorf("intended source rejected %s: %v", server, err)
		}
	}
	for _, server := range []string{"http://169.254.169.254", "http://[fe80::1234]", "http://[::]", "http://0.0.0.0", "http://0.1.2.3", "http://224.0.0.1", "http://[ff02::1]", "http://[::ffff:169.254.169.254]", "http://100.100.100.200", "http://168.63.129.16", "http://[fd00:ec2::254]", "http://[64:ff9b::a9fe:a9fe]", "http://255.255.255.255", "http://host:", "http://host:0", "http://host:65536", "http://[not-an-ip]", "http://[fe80::1%25en0]", "http://host./a/../b", "http://host?", "http://host#", "http://user:token@host", "http://host\\evil/", "http://ho_st/", "http://host/prefix%20name", "http://host/prefix%5Cname"} {
		if _, err := normalizeServerURL(server); err == nil {
			t.Errorf("unsafe source accepted %s", server)
		}
	}
	normalized, err := normalizeServerURL("http://PAPERLESS.example.test/prefix/")
	if err != nil || normalized != "http://paperless.example.test/prefix" {
		t.Fatal(normalized, err)
	}
}

type mockResolver struct {
	answers [][]netip.Addr
	calls   int
}

func (r *mockResolver) LookupNetIP(context.Context, string, string) ([]netip.Addr, error) {
	answer := r.answers[r.calls]
	r.calls++
	return answer, nil
}

func TestDialPinsResolvedAddressAndRejectsRebindingAndMixedAnswers(t *testing.T) {
	resolver := &mockResolver{answers: [][]netip.Addr{{netip.MustParseAddr("192.168.1.20")}, {netip.MustParseAddr("169.254.169.254")}, {netip.MustParseAddr("192.168.1.20"), netip.MustParseAddr("::ffff:169.254.169.254")}}}
	var dialed []string
	dialer := paperlessGuardedDialer{resolver: resolver, dial: func(_ context.Context, _, address string) (net.Conn, error) {
		dialed = append(dialed, address)
		left, right := net.Pipe()
		right.Close()
		return left, nil
	}}
	conn, err := dialer.DialContext(t.Context(), "tcp", "paperless.example.test:8000")
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
	if len(dialed) != 1 || dialed[0] != "192.168.1.20:8000" {
		t.Fatalf("hostname was resolved again by network dial: %v", dialed)
	}
	for range 2 {
		_, err := dialer.DialContext(t.Context(), "tcp", "paperless.example.test:8000")
		var failure m.PaperlessFailure
		if !errors.As(err, &failure) || failure.Code != "server_not_allowed" || len(dialed) != 1 {
			t.Fatalf("unsafe DNS answer reached network: %v %v", dialed, err)
		}
	}
}
