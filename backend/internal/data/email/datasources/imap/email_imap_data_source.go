package imap

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"io"
	"net"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	protocol "github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

type EmailIMAPDataSource struct {
	roots        *x509.CertPool
	allowed      map[string]bool
	lookupIPAddr func(context.Context, string) ([]net.IPAddr, error)
	dialContext  func(context.Context, string, string) (net.Conn, error)
}

func NewEmailIMAPDataSource(caFile string, allowed []string) (*EmailIMAPDataSource, error) {
	roots, err := x509.SystemCertPool()
	if err != nil {
		return nil, errors.New("load IMAP trust roots")
	}
	if caFile != "" {
		bytes, e := os.ReadFile(caFile)
		if e != nil || len(bytes) > 1<<20 || !roots.AppendCertsFromPEM(bytes) {
			return nil, errors.New("invalid EMAIL_IMAP_CA_FILE")
		}
	}
	result := &EmailIMAPDataSource{
		roots: roots, allowed: map[string]bool{},
		lookupIPAddr: net.DefaultResolver.LookupIPAddr,
		dialContext:  (&net.Dialer{}).DialContext,
	}
	for _, host := range allowed {
		host = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(host), "."))
		if host == "" {
			continue
		}
		normalized, e := (m.EmailSettings{Label: "allowlist", Host: host}).Normalize()
		if e != nil || normalized.Host != host {
			return nil, errors.New("invalid EMAIL_IMAP_ALLOWED_HOSTS")
		}
		result.allowed[host] = true
	}
	return result, nil
}
func (g *EmailIMAPDataSource) Connect(ctx context.Context, settings m.EmailConnection) (*EmailIMAPSession, error) {
	raw, err := g.dialConnection(ctx, settings)
	if err != nil {
		return nil, err
	}
	conn := tls.Client(raw, &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: g.roots, ServerName: settings.Host})
	if err = conn.HandshakeContext(ctx); err != nil {
		raw.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, m.EmailFailure{Code: "tls_failed"}
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	guarded := NewEmailIMAPConnectionGuard(conn)
	lifetime, cancel := context.WithCancel(ctx)
	session := &EmailIMAPSession{guard: guarded, unsolicited: make(chan *imapclient.FetchMessageData, 1), ctx: lifetime, cancel: cancel}
	session.stop = context.AfterFunc(ctx, func() { _ = guarded.Close() })
	session.client = imapclient.New(guarded, &imapclient.Options{UnilateralDataHandler: &imapclient.UnilateralDataHandler{Fetch: session.unilateral, Expunge: session.expunge}})
	if err = session.client.WaitGreeting(); err == nil {
		err = session.client.Login(settings.Credentials.Username, settings.Credentials.Password).Wait()
	}
	if err != nil {
		session.Close()
		return nil, m.EmailFailure{Code: "authentication_failed"}
	}
	selected, err := session.client.Select(settings.Mailbox, &protocol.SelectOptions{ReadOnly: true}).Wait()
	if err != nil {
		session.Close()
		return nil, m.EmailFailure{Code: "mailbox_unavailable", Retryable: true}
	}
	if selected.UIDValidity == 0 || selected.UIDNext == 0 {
		session.Close()
		return nil, m.EmailFailure{Code: "invalid_mailbox_identity"}
	}
	session.info = m.EmailMailbox{UIDValidity: int64(selected.UIDValidity), UIDNext: int64(selected.UIDNext)}
	session.messageCount = selected.NumMessages
	return session, nil
}

type EmailIMAPSession struct {
	client       *imapclient.Client
	guard        *EmailIMAPConnectionGuard
	info         m.EmailMailbox
	ctx          context.Context
	cancel       context.CancelFunc
	stop         func() bool
	unsolicited  chan *imapclient.FetchMessageData
	mutex        sync.Mutex
	fetching     bool
	callbacks    sync.WaitGroup
	messageCount uint32
	expunged     atomic.Bool
}

func (s *EmailIMAPSession) Info() m.EmailMailbox { return s.info }
func (s *EmailIMAPSession) expunge(uint32)       { s.expunged.Store(true) }
func drain(message *imapclient.FetchMessageData) {
	for item := message.Next(); item != nil; item = message.Next() {
		if body, ok := item.(imapclient.FetchItemDataBodySection); ok && body.Literal != nil {
			_, _ = io.Copy(io.Discard, body.Literal)
		}
	}
}
func (s *EmailIMAPSession) unilateral(message *imapclient.FetchMessageData) {
	s.mutex.Lock()
	fetching := s.fetching
	s.mutex.Unlock()
	if fetching {
		select {
		case s.unsolicited <- message:
			return
		case <-s.ctx.Done():
		}
	}
	drain(message)
}
func (s *EmailIMAPSession) Close() error {
	s.cancel()
	s.stop()
	_ = s.guard.Close()
	err := s.client.Close()
	s.callbacks.Wait()
	if errors.Is(err, net.ErrClosed) || errors.Is(err, io.EOF) || errors.Is(err, context.Canceled) {
		return nil
	}
	return err
}
func (s *EmailIMAPSession) Discover(ctx context.Context, from, to int64, since time.Time) (m.EmailDiscovery, error) {
	stop := s.cancelOperation(ctx)
	defer stop()
	if err := ctx.Err(); err != nil {
		return m.EmailDiscovery{}, err
	}
	if from < 1 || to < from || to > 1<<32-1 {
		return m.EmailDiscovery{}, m.EmailValidationError{Message: "invalid UID discovery range"}
	}
	through := to
	if to-from >= 1000 {
		if to >= s.info.UIDNext {
			return m.EmailDiscovery{}, m.EmailValidationError{Message: "UID discovery exceeds selected mailbox"}
		}
		var err error
		through, err = s.discoveryUpper(from, to)
		if err != nil {
			if ctx.Err() != nil {
				return m.EmailDiscovery{}, ctx.Err()
			}
			return m.EmailDiscovery{}, err
		}
	}
	uids, err := s.searchUIDs(from, through, since)
	if ctx.Err() != nil {
		return m.EmailDiscovery{}, ctx.Err()
	}
	if err != nil {
		return m.EmailDiscovery{}, err
	}
	if s.expunged.Load() {
		return m.EmailDiscovery{}, m.EmailFailure{Code: "mailbox_changed", Retryable: true}
	}
	return m.EmailDiscovery{UIDs: uids, Through: through}, nil
}

func (s *EmailIMAPSession) discoveryUpper(from, to int64) (int64, error) {
	low, high := uint64(1), uint64(s.messageCount)+1
	if from == 1 {
		high = low
	}
	for low < high {
		middle := low + (high-low)/2
		uid, err := s.sequenceUID(uint32(middle))
		if err != nil {
			return 0, err
		}
		if uid < from {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low > uint64(s.messageCount) {
		return to, nil
	}
	last := min(low+999, uint64(s.messageCount))
	uid, err := s.sequenceUID(uint32(last))
	if err != nil {
		return 0, err
	}
	if uid < from {
		return 0, m.EmailFailure{Code: "protocol_failed"}
	}
	if last == uint64(s.messageCount) {
		return to, nil
	}
	return min(uid, to), nil
}

func (s *EmailIMAPSession) sequenceUID(sequence uint32) (int64, error) {
	if s.expunged.Load() {
		return 0, m.EmailFailure{Code: "mailbox_changed", Retryable: true}
	}
	command := s.client.Fetch(protocol.SeqSetNum(sequence), &protocol.FetchOptions{UID: true})
	count, uidCount := 0, 0
	var uid int64
	valid := true
	for message := command.Next(); message != nil; message = command.Next() {
		count++
		valid = valid && message.SeqNum == sequence
		for item := message.Next(); item != nil; item = message.Next() {
			switch value := item.(type) {
			case imapclient.FetchItemDataUID:
				uidCount++
				uid = int64(value.UID)
			case imapclient.FetchItemDataBodySection:
				if value.Literal != nil {
					_, _ = io.Copy(io.Discard, value.Literal)
				}
				valid = false
			case imapclient.FetchItemDataBinarySection:
				if value.Literal != nil {
					_, _ = io.Copy(io.Discard, value.Literal)
				}
				valid = false
			}
			if !valid || uidCount > 1 {
				_ = s.guard.Close()
			}
		}
	}
	err := command.Close()
	if s.expunged.Load() {
		return 0, m.EmailFailure{Code: "mailbox_changed", Retryable: true}
	}
	if err != nil {
		return 0, m.EmailFailure{Code: "protocol_failed", Retryable: true}
	}
	if !valid || count < 1 || uidCount != 1 || uid < 1 || uid >= s.info.UIDNext {
		return 0, m.EmailFailure{Code: "protocol_failed"}
	}
	return uid, nil
}

func (s *EmailIMAPSession) searchUIDs(from, to int64, since time.Time) ([]int64, error) {
	set := protocol.UIDSet{}
	set.AddRange(protocol.UID(from), protocol.UID(to))
	data, err := s.client.UIDSearch(&protocol.SearchCriteria{UID: []protocol.UIDSet{set}, Since: since.UTC().Add(-24 * time.Hour)}, nil).Wait()
	if err != nil {
		return nil, m.EmailFailure{Code: "protocol_failed", Retryable: true}
	}
	ranges, ok := data.All.(protocol.UIDSet)
	if !ok || ranges.Dynamic() {
		return nil, m.EmailFailure{Code: "protocol_failed"}
	}
	cardinality := int64(0)
	for _, entry := range ranges {
		first, last := int64(entry.Start), int64(entry.Stop)
		if first > last {
			first, last = last, first
		}
		if first < from || last > to || first == 0 {
			return nil, m.EmailFailure{Code: "protocol_limit"}
		}
		cardinality += last - first + 1
		if cardinality > 1000 {
			return nil, m.EmailFailure{Code: "protocol_limit"}
		}
	}
	values, ok := ranges.Nums()
	if !ok {
		return nil, m.EmailFailure{Code: "protocol_failed"}
	}
	result := make([]int64, 0, len(values))
	seen := map[int64]bool{}
	for _, value := range values {
		uid := int64(value)
		if uid < from || uid > to || seen[uid] {
			return nil, m.EmailFailure{Code: "protocol_failed"}
		}
		seen[uid] = true
		result = append(result, uid)
	}
	sort.Slice(result, func(i, j int) bool { return result[i] < result[j] })
	return result, nil
}
func (s *EmailIMAPSession) Fetch(ctx context.Context, uid int64, consume func(m.EmailMessage) error) (m.EmailMessage, error) {
	stop := s.cancelOperation(ctx)
	defer stop()
	result := m.EmailMessage{UID: uid}
	if uid < 1 || uid > 1<<32-1 {
		return result, m.EmailValidationError{Message: "invalid message UID"}
	}
	s.mutex.Lock()
	s.fetching = true
	s.mutex.Unlock()
	s.guard.Body(uint32(uid))
	command := s.client.Fetch(protocol.UIDSetNum(protocol.UID(uid)), &protocol.FetchOptions{UID: true, InternalDate: true, RFC822Size: true, BodySection: []*protocol.FetchItemBodySection{{Peek: true}}})
	messages := make(chan *imapclient.FetchMessageData, 1)
	consumed := make(chan struct{})
	commandDone := make(chan error, 1)
	s.callbacks.Add(1)
	go func() {
		defer s.callbacks.Done()
		for message := command.Next(); message != nil; message = command.Next() {
			select {
			case messages <- message:
				<-consumed
			case <-ctx.Done():
				drain(message)
			}
		}
		commandDone <- command.Close()
	}()
	count, bodies := 0, 0
	var failure error
	read := func(message *imapclient.FetchMessageData) {
		count++
		beforeBodies := bodies
		gotUID := int64(0)
		uidCount := 0
		for item := message.Next(); item != nil; item = message.Next() {
			switch value := item.(type) {
			case imapclient.FetchItemDataUID:
				gotUID = int64(value.UID)
				uidCount++
			case imapclient.FetchItemDataRFC822Size:
				result.Size = value.Size
			case imapclient.FetchItemDataInternalDate:
				result.InternalDate = value.Time
			case imapclient.FetchItemDataBodySection:
				bodies++
				if value.Literal == nil || value.Section == nil || len(value.Section.Part) != 0 || value.Section.Specifier != "" || value.Section.Partial != nil || bodies != 1 {
					failure = m.EmailFailure{Code: "protocol_failed"}
					_ = s.guard.Close()
					continue
				}
				if value.Literal.Size() > 100<<20 {
					failure = m.EmailFailure{Code: "message_too_large"}
					_ = s.guard.Close()
					continue
				}
				tracked := &emailIMAPLiteralProgress{reader: value.Literal, size: value.Literal.Size()}
				result.Reader = tracked
				if failure == nil {
					failure = consume(result)
				}
				if failure != nil {
					_ = s.guard.Close()
				}
				if tracked.err == nil && tracked.read < tracked.size {
					_, drainErr := io.Copy(io.Discard, tracked)
					if failure == nil {
						failure = drainErr
					}
				}
				if tracked.err != nil && tracked.read < tracked.size {
					_ = s.guard.Close()
					<-s.client.Closed()
				}
			}
		}
		if bodies > beforeBodies && (gotUID != uid || uidCount != 1) {
			failure = m.EmailFailure{Code: "protocol_failed"}
			_ = s.guard.Close()
		}
	}
	finished := false
	for !finished {
		select {
		case message := <-messages:
			read(message)
			consumed <- struct{}{}
		case message := <-s.unsolicited:
			read(message)
		case err := <-commandDone:
			if err != nil && failure == nil {
				failure = m.EmailFailure{Code: "protocol_failed", Retryable: true}
			}
			finished = true
		case <-ctx.Done():
			failure = ctx.Err()
			_ = s.guard.Close()
			for !finished {
				select {
				case message := <-messages:
					drain(message)
					consumed <- struct{}{}
				case message := <-s.unsolicited:
					drain(message)
				case <-commandDone:
					finished = true
				}
			}
		}
	}
	s.mutex.Lock()
	s.fetching = false
	s.mutex.Unlock()
	s.guard.EndBody()
	result.Reader = nil
	if failure == nil && (bodies != 1 || count < 1 || result.InternalDate.IsZero() || result.Size < 1 || result.Size > 100<<20) {
		failure = m.EmailFailure{Code: "message_unavailable"}
	}
	return result, failure
}
func (s *EmailIMAPSession) cancelOperation(ctx context.Context) func() {
	done := make(chan struct{})
	stop := context.AfterFunc(ctx, func() { defer close(done); _ = s.guard.Close() })
	return func() {
		if !stop() {
			<-done
		}
	}
}

type emailIMAPLiteralProgress struct {
	reader     io.Reader
	size, read int64
	err        error
}

func (r *emailIMAPLiteralProgress) Read(p []byte) (int, error) {
	if r.err != nil {
		return 0, r.err
	}
	n, err := r.reader.Read(p)
	r.read += int64(n)
	r.err = err
	return n, err
}
