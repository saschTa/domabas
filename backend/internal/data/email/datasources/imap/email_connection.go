package imap

import (
	"context"
	"net"
	"strconv"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

func (g *EmailIMAPDataSource) dialConnection(ctx context.Context, settings m.EmailConnection) (net.Conn, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if len(g.allowed) > 0 && !g.allowed[settings.Host] {
		return nil, m.EmailFailure{Code: "destination_not_allowed"}
	}
	connectionCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	addresses, err := g.lookupIPAddr(connectionCtx, settings.Host)
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil || len(addresses) == 0 {
		return nil, m.EmailFailure{Code: "connection_failed", Retryable: true}
	}
	for _, candidate := range addresses {
		ip := candidate.IP
		if ip.To16() == nil || ip.IsUnspecified() || ip.IsMulticast() || (!g.allowed[settings.Host] && (!ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || net.ParseIP(settings.Host) != nil)) {
			return nil, m.EmailFailure{Code: "destination_not_allowed"}
		}
	}
	deadline, _ := connectionCtx.Deadline()
	for index, candidate := range addresses {
		if connectionCtx.Err() != nil {
			break
		}
		attemptCtx, stop := context.WithTimeout(connectionCtx, time.Until(deadline)/time.Duration(len(addresses)-index))
		raw, err := g.dialContext(attemptCtx, "tcp", net.JoinHostPort(candidate.IP.String(), strconv.Itoa(settings.Port)))
		stop()
		if err == nil {
			if connectionCtx.Err() == nil {
				return raw, nil
			}
			_ = raw.Close()
			break
		}
	}
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	return nil, m.EmailFailure{Code: "connection_failed", Retryable: true}
}
