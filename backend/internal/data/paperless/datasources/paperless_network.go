package datasources

import (
	"context"
	"net"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/paperless/models"
)

func normalizeServerURL(server string) (string, error) {
	u, err := url.Parse(server)
	if err != nil || u.Hostname() == "" || (u.Scheme != "https" && u.Scheme != "http") || u.User != nil || u.RawQuery != "" || u.ForceQuery || strings.Contains(server, "#") || strings.Contains(u.EscapedPath(), "%") || strings.Contains(u.Path, "..") || strings.Contains(u.Path, "//") || strings.ContainsAny(server, "\\\r\n\t ") || len(server) > 2048 {
		return "", m.PaperlessFailure{Code: "invalid_server_url"}
	}
	if strings.HasSuffix(u.Host, ":") {
		return "", m.PaperlessFailure{Code: "invalid_server_url"}
	}
	if port := u.Port(); port != "" {
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			return "", m.PaperlessFailure{Code: "invalid_server_url"}
		}
	}
	host := strings.ToLower(strings.TrimSuffix(u.Hostname(), "."))
	if address, err := netip.ParseAddr(host); err == nil {
		if !allowedAddress(address) {
			return "", m.PaperlessFailure{Code: "server_not_allowed"}
		}
	} else {
		if len(host) > 253 || strings.HasPrefix(u.Host, "[") || strings.ContainsAny(host, ":%") {
			return "", m.PaperlessFailure{Code: "invalid_server_url"}
		}
		for _, label := range strings.Split(host, ".") {
			if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
				return "", m.PaperlessFailure{Code: "invalid_server_url"}
			}
			for _, ch := range label {
				if (ch < 'a' || ch > 'z') && (ch < '0' || ch > '9') && ch != '-' {
					return "", m.PaperlessFailure{Code: "invalid_server_url"}
				}
			}
		}
	}
	u.Host = strings.ToLower(u.Host)
	return strings.TrimRight(u.String(), "/"), nil
}

func allowedAddress(address netip.Addr) bool {
	address = address.Unmap()
	if !address.IsValid() || address.Zone() != "" || (!address.IsGlobalUnicast() && !address.IsLoopback()) {
		return false
	}
	for _, blocked := range []string{"0.0.0.0/8", "240.0.0.0/4", "168.63.129.16/32", "100.100.100.200/32", "192.0.0.192/32", "fd00:ec2::254/128", "64:ff9b::/96", "64:ff9b:1::/48", "2002::/16"} {
		if netip.MustParsePrefix(blocked).Contains(address) {
			return false
		}
	}
	return true
}

type paperlessAddressResolver interface {
	LookupNetIP(context.Context, string, string) ([]netip.Addr, error)
}

type paperlessGuardedDialer struct {
	resolver paperlessAddressResolver
	dial     func(context.Context, string, string) (net.Conn, error)
}

func (d *paperlessGuardedDialer) DialContext(ctx context.Context, network, target string) (net.Conn, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	host, port, err := net.SplitHostPort(target)
	if err != nil {
		return nil, m.PaperlessFailure{Code: "invalid_server_url"}
	}
	addresses, err := d.resolver.LookupNetIP(ctx, "ip", host)
	if err != nil || len(addresses) == 0 {
		return nil, m.PaperlessFailure{Code: "source_unavailable"}
	}
	for _, address := range addresses {
		if !allowedAddress(address) {
			return nil, m.PaperlessFailure{Code: "server_not_allowed"}
		}
	}
	for _, address := range addresses {
		conn, err := d.dial(ctx, network, net.JoinHostPort(address.String(), port))
		if err == nil {
			return conn, nil
		}
		if ctx.Err() != nil {
			break
		}
	}
	return nil, m.PaperlessFailure{Code: "source_unavailable"}
}
