package mimecontent

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"testing"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
)

func TestEnvelopeLongHeaderChunksPreserveTheActualSeparator(t *testing.T) {
	for _, length := range []int{4095, 4096, 8192} {
		for _, ending := range []string{"\n", "\r\n"} {
			t.Run(fmt.Sprintf("length_%d_ending_%q", length, ending), func(t *testing.T) {
				first := "Subject: " + strings.Repeat("a", length-len("Subject: ")) + ending
				input := first + "From: sender@example.com" + ending + ending + "exact body\r\n"
				header, reader, err := ReadEnvelope(strings.NewReader(input))
				if err != nil {
					t.Fatal(err)
				}
				body, err := io.ReadAll(reader)
				if err != nil || header.Get("From") != "sender@example.com" || string(body) != "exact body\r\n" {
					t.Fatalf("lost envelope framing: header=%v body=%q err=%v", header, body, err)
				}
				if _, _, err := ReadEnvelope(strings.NewReader(first)); !errors.Is(err, ErrEnvelope) {
					t.Fatalf("accepted missing separator: %v", err)
				}
			})
		}
	}
}

func TestEnvelopeMetadataDoesNotRequireValidMIMEBody(t *testing.T) {
	input := "Subject: retained original\r\nFrom: sender@example.com\r\nContent-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\ninvalid broken child"
	metadata, err := NewDocumentMimeContentDataSource().Envelope(strings.NewReader(input))
	if err != nil || metadata.Subject != "retained original" || metadata.Sender != "sender@example.com" {
		t.Fatalf("metadata=%+v err=%v", metadata, err)
	}
	result, err := Inspect(context.Background(), strings.NewReader(input), nil)
	if err == nil || !result.ContentFailures || !result.TextFailures {
		t.Fatalf("broken MIME accepted as complete: %+v %v", result, err)
	}
}

func TestAlternativePreferenceDoesNotDiscardMixedSiblings(t *testing.T) {
	input := strings.ReplaceAll(`MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=outer

--outer
Content-Type: multipart/alternative; boundary=inner

--inner
Content-Type: text/plain

plain alternative
--inner
Content-Type: text/html

<p>duplicate HTML alternative</p>
--inner--
--outer
Content-Type: text/html

<p>distinct HTML sibling</p>
--outer
Content-Type: text/plain

distinct plain sibling
--outer--
`, "\n", "\r\n")
	result, err := Inspect(context.Background(), strings.NewReader(input), nil)
	if err != nil || result.ContentFailures || result.TextFailures || result.Text != "plain alternative\ndistinct HTML sibling\ndistinct plain sibling" {
		t.Fatalf("unexpected extraction: %+v %v", result, err)
	}
}

func TestAlternativeHonorsEmptyPlainBodyAndFallsBackToHTML(t *testing.T) {
	for _, tc := range []struct {
		name, plain, want string
	}{
		{name: "empty_plain_is_authoritative", plain: "--x\r\nContent-Type: text/plain\r\n\r\n\r\n", want: ""},
		{name: "html_without_plain", want: "HTML body"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := "Content-Type: multipart/alternative; boundary=x\r\n\r\n" + tc.plain + "--x\r\nContent-Type: text/html\r\n\r\n<p>HTML body</p>\r\n--x--\r\n"
			result, err := Inspect(context.Background(), strings.NewReader(input), nil)
			if err != nil || result.ContentFailures || result.Text != tc.want {
				t.Fatalf("unexpected alternative: %+v %v", result, err)
			}
		})
	}
}

func TestHTMLVoidElementsAndHiddenSubtrees(t *testing.T) {
	cases := []struct{ name, input, want string }{
		{"head_meta", `<html><head><meta charset="utf-8"><link href="https://example.invalid"><title>hidden</title></head><body><p>visible</p></body></html>`, "visible"},
		{"many_void_tags", "first" + strings.Repeat("<img><br><input><hr>", 100) + "last", "first\nlast"},
		{"inline_and_block_boundaries", "<p>one<strong>two</strong>three<br>four</p><div>five</div>", "onetwothree\nfour\nfive"},
		{"hidden_template", "before<template><div>hidden</wrong><img></div>still hidden</template>after", "beforeafter"},
		{"script_and_style", "<style>hidden CSS</style><script>hidden JavaScript</script><p>safe &amp; visible</p>", "safe & visible"},
		{"nonvoid_self_closing_syntax", "before<script/>hidden JavaScript</script>after", "beforeafter"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := plainHTML(tc.input)
			if err != nil || got != tc.want {
				t.Fatalf("got %q, want %q, err=%v", got, tc.want, err)
			}
		})
	}
	if _, err := plainHTML(strings.Repeat("<div>", 65) + "too deep"); !errors.Is(err, ErrLimit) {
		t.Fatalf("missing nesting bound: %v", err)
	}
	if _, err := plainHTML(strings.Repeat("x", (64<<10)+1)); err == nil {
		t.Fatal("missing tokenizer bound")
	}
}

func TestAttachmentFailureDoesNotInvalidateCompleteBody(t *testing.T) {
	input := "Content-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\ncomplete body\r\n--x\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=broken.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\n%%%invalid%%%\r\n--x--\r\n"
	var parts []r.DocumentEmailPart
	result, err := Inspect(context.Background(), strings.NewReader(input), func(part r.DocumentEmailPart) error {
		parts = append(parts, part)
		return nil
	})
	if err != nil || !result.ContentFailures || result.TextFailures || result.Text != "complete body" {
		t.Fatalf("attachment failure lost body: %+v %v", result, err)
	}
	if len(parts) != 2 || parts[1].Path != "2" || parts[1].FailureCode != "invalid_encoding" {
		t.Fatalf("missing stable attachment failure: %+v", parts)
	}
}

func TestIncompleteBodyIsMarkedSeparately(t *testing.T) {
	for _, tc := range []struct{ name, header, body string }{
		{"charset", "Content-Type: text/plain; charset=unknown-charset", "body"},
		{"encoding", "Content-Type: text/plain\r\nContent-Transfer-Encoding: base64", "%%%"},
		{"unknown_encoding", "Content-Type: text/plain\r\nContent-Transfer-Encoding: unsupported", "body"},
		{"invalid_utf8", "Content-Type: text/plain", "\xff"},
		{"body_limit", "Content-Type: text/plain", strings.Repeat("x", maxText+1)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			result, _ := Inspect(context.Background(), strings.NewReader(tc.header+"\r\n\r\n"+tc.body), nil)
			if !result.ContentFailures || !result.TextFailures {
				t.Fatalf("incomplete extraction not marked: %+v", result)
			}
		})
	}
}

func TestInspectionHonorsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	result, err := Inspect(ctx, strings.NewReader("Subject: cancelled\r\n\r\nbody"), nil)
	if !errors.Is(err, context.Canceled) || !result.TextFailures {
		t.Fatalf("cancellation was lost: %+v %v", result, err)
	}
}
