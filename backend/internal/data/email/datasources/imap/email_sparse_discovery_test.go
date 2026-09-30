package imap

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	m "github.com/domabas/domabas/backend/internal/domain/email/models"
	"github.com/emersion/go-imap/v2/imapclient"
	"io"
	"net"
	"reflect"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type emailDiscoveryFixture struct {
	uids      []int64
	old       map[int64]bool
	expungeOn string
	commands  atomic.Int32
}

func sparseDiscoverySession(t *testing.T, fixture *emailDiscoveryFixture) (*EmailIMAPSession, context.Context) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	client, peer := net.Pipe()
	guard := NewEmailIMAPConnectionGuard(client)
	session := &EmailIMAPSession{guard: guard, ctx: ctx, cancel: cancel, unsolicited: make(chan *imapclient.FetchMessageData, 1), messageCount: uint32(len(fixture.uids)), info: m.EmailMailbox{UIDValidity: 7, UIDNext: 4000000001}}
	session.stop = context.AfterFunc(ctx, func() { _ = guard.Close() })
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer peer.Close()
		_, _ = io.WriteString(peer, "* OK [CAPABILITY IMAP4rev1] sparse fixture\r\n")
		reader := bufio.NewReader(peer)
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				return
			}
			fixture.commands.Add(1)
			fields := strings.Fields(line)
			tag := fields[0]
			switch fields[1] {
			case "FETCH":
				sequence, err := strconv.Atoi(fields[2])
				if err != nil || sequence < 1 || sequence > len(fixture.uids) {
					t.Errorf("invalid sequence probe %q", line)
					return
				}
				if fixture.expungeOn == "fetch" {
					_, _ = io.WriteString(peer, "* 1 EXPUNGE\r\n")
				}
				_, _ = fmt.Fprintf(peer, "* %d FETCH (FLAGS (\\Seen) UID %d)\r\n%s OK fetched\r\n", sequence, fixture.uids[sequence-1], tag)
			case "UID":
				if len(fields) < 7 || fields[2] != "SEARCH" || fields[3] != "UID" || fields[5] != "SINCE" {
					t.Errorf("unbounded or missing date query %q", line)
					return
				}
				bounds := strings.Split(fields[4], ":")
				from, err := strconv.ParseInt(bounds[0], 10, 64)
				if err != nil {
					t.Error(err)
					return
				}
				through := from
				if len(bounds) == 2 {
					through, err = strconv.ParseInt(bounds[1], 10, 64)
				}
				if err != nil {
					t.Error(err)
					return
				}
				var response strings.Builder
				response.WriteString("* SEARCH")
				count := 0
				for _, uid := range fixture.uids {
					if uid >= from && uid <= through {
						count++
						if !fixture.old[uid] {
							fmt.Fprintf(&response, " %d", uid)
						}
					}
				}
				if count > 1000 {
					t.Errorf("discovery requested %d existing messages", count)
					return
				}
				response.WriteString("\r\n")
				if fixture.expungeOn == "search" {
					response.WriteString("* 1 EXPUNGE\r\n")
				}
				fmt.Fprintf(&response, "%s OK searched\r\n", tag)
				_, _ = io.WriteString(peer, response.String())
			default:
				t.Errorf("unexpected command %q", line)
				return
			}
		}
	}()
	session.client = imapclient.New(guard, &imapclient.Options{UnilateralDataHandler: &imapclient.UnilateralDataHandler{Fetch: session.unilateral, Expunge: session.expunge}})
	t.Cleanup(func() { cancel(); _ = peer.Close(); _ = session.Close(); <-done })
	if err := session.client.WaitGreeting(); err != nil {
		t.Fatal(err)
	}
	return session, ctx
}
func TestSparseUIDDiscoveryJumpsBillionUIDGapsAndEmptySuffix(t *testing.T) {
	for _, tc := range []struct {
		name        string
		from, upper int64
		want        []int64
	}{
		{"initial", 1, 3000000000, []int64{2000000000, 3000000000}},
		{"between", 2000000001, 3000000000, []int64{3000000000}},
		{"empty_suffix", 3000000001, 4000000000, nil},
		{"captured_upper", 1, 2500000000, []int64{2000000000}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fixture := &emailDiscoveryFixture{uids: []int64{2000000000, 3000000000}}
			session, ctx := sparseDiscoverySession(t, fixture)
			got, err := session.Discover(ctx, tc.from, tc.upper, time.Now())
			if err != nil || got.Through != tc.upper || !reflect.DeepEqual(append([]int64(nil), got.UIDs...), tc.want) {
				t.Fatalf("discovery %+v, %v; want %v through %d", got, err, tc.want, tc.upper)
			}
			if fixture.commands.Load() > 4 {
				t.Fatalf("gap required %d commands", fixture.commands.Load())
			}
		})
	}
}
func TestSparseUIDDiscoveryBoundsDenseMailboxAndPreservesDateCutoff(t *testing.T) {
	fixture := &emailDiscoveryFixture{old: map[int64]bool{2000000000: true}}
	for i := int64(0); i < 2501; i++ {
		fixture.uids = append(fixture.uids, 2000000000+i)
	}
	session, ctx := sparseDiscoverySession(t, fixture)
	var got []int64
	from, upper := int64(1), fixture.uids[len(fixture.uids)-1]
	for windows := 0; from <= upper; windows++ {
		if windows >= 3 {
			t.Fatal("sparse mailbox did not finish within three windows")
		}
		page, err := session.Discover(ctx, from, upper, time.Now())
		if err != nil {
			t.Fatal(err)
		}
		if len(page.UIDs) > 1000 {
			t.Fatal("unbounded message page")
		}
		got = append(got, page.UIDs...)
		from = page.Through + 1
	}
	if !reflect.DeepEqual(got, fixture.uids[1:]) {
		t.Fatal("mail skipped, duplicated or age filter ignored")
	}
	if fixture.commands.Load() > 35 {
		t.Fatalf("too many probes: %d", fixture.commands.Load())
	}
}
func TestSparseUIDDiscoveryEmptyMailbox(t *testing.T) {
	session, ctx := sparseDiscoverySession(t, &emailDiscoveryFixture{})
	got, err := session.Discover(ctx, 1, 4000000000, time.Now())
	if err != nil || got.Through != 4000000000 || len(got.UIDs) != 0 {
		t.Fatalf("empty mailbox: %+v %v", got, err)
	}
}
func TestSparseUIDDiscoveryRejectsExpungeBeforeCheckpoint(t *testing.T) {
	for _, phase := range []string{"fetch", "search", "before"} {
		t.Run(phase, func(t *testing.T) {
			session, ctx := sparseDiscoverySession(t, &emailDiscoveryFixture{uids: []int64{2000000000}, expungeOn: phase})
			if phase == "before" {
				session.expunge(1)
			}
			got, err := session.Discover(ctx, 1, 4000000000, time.Now())
			var failure m.EmailFailure
			if !errors.As(err, &failure) || failure.Code != "mailbox_changed" || !failure.Retryable || got.Through != 0 || len(got.UIDs) != 0 {
				t.Fatalf("uncertain position checkpointed: %+v %v", got, err)
			}
		})
	}
}
func TestSparseUIDDiscoveryCancelsStalledProbe(t *testing.T) {
	session, lifetime := independentSession(t, func(peer net.Conn, command string) { _, _ = io.Copy(io.Discard, peer) })
	session.messageCount = 1
	session.info.UIDNext = 4000000001
	ctx, cancel := context.WithTimeout(lifetime, 50*time.Millisecond)
	defer cancel()
	got, err := session.Discover(ctx, 1, 4000000000, time.Now())
	if !errors.Is(err, context.DeadlineExceeded) || got.Through != 0 {
		t.Fatalf("cancelled lookup returned %+v %v", got, err)
	}
}

func TestSparseUIDDiscoveryRejectsInvalidProbeIdentity(t *testing.T) {
	for _, attributes := range []string{"UID 0", "UID 4000000001", "UID 17 UID 18", "FLAGS (\\Seen)"} {
		t.Run(attributes, func(t *testing.T) {
			session, ctx := independentSession(t, func(peer net.Conn, command string) {
				tag := strings.Fields(command)[0]
				_, _ = fmt.Fprintf(peer, "* 1 FETCH (%s)\r\n%s OK fetched\r\n", attributes, tag)
			})
			session.messageCount = 1
			session.info.UIDNext = 4000000001
			got, err := session.Discover(ctx, 1, 4000000000, time.Now())
			if err == nil || got.Through != 0 || len(got.UIDs) != 0 {
				t.Fatalf("invalid identity returned checkpoint: %+v %v", got, err)
			}
		})
	}
}

func TestSparseUIDDiscoveryDefersArrivalBeyondSelectedSnapshot(t *testing.T) {
	fixture := &emailDiscoveryFixture{uids: []int64{2000000000, 3000000000}}
	session, ctx := sparseDiscoverySession(t, fixture)
	session.messageCount = 1
	session.info.UIDNext = 2000000001
	got, err := session.Discover(ctx, 1, 2000000000, time.Now())
	if err != nil || got.Through != 2000000000 || !reflect.DeepEqual(got.UIDs, []int64{2000000000}) {
		t.Fatalf("arrival changed captured discovery: %+v %v", got, err)
	}
}
