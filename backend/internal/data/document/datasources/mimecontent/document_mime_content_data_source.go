package mimecontent

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net/mail"
	"net/textproto"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
	"golang.org/x/net/html"
	"golang.org/x/net/html/charset"
)

const MaxRawBytes = int(models.MaxFileBytes)
const maxText = models.MaxOCRBytes

var ErrEnvelope = errors.New("invalid email envelope")
var ErrLimit = errors.New("email content exceeds resource limit")

type DocumentMimeContentDataSource struct{}

func NewDocumentMimeContentDataSource() *DocumentMimeContentDataSource {
	return &DocumentMimeContentDataSource{}
}
func (*DocumentMimeContentDataSource) Inspect(ctx context.Context, input io.Reader, visit func(r.DocumentEmailPart) error) (r.DocumentEmailInspection, error) {
	return Inspect(ctx, input, visit)
}
func (*DocumentMimeContentDataSource) Envelope(input io.Reader) (r.DocumentEmailMetadata, error) {
	header, _, err := ReadEnvelope(input)
	if err != nil {
		return r.DocumentEmailMetadata{}, err
	}
	return Metadata(header), nil
}

func ReadEnvelope(input io.Reader) (textproto.MIMEHeader, io.Reader, error) {
	reader := bufio.NewReaderSize(input, 4096)
	var raw bytes.Buffer
	lineBytes := 0
	for {
		line, err := reader.ReadSlice('\n')
		if raw.Len()+len(line) > 64<<10 {
			return nil, nil, ErrEnvelope
		}
		raw.Write(line)
		lineBytes += len(line)
		if err == bufio.ErrBufferFull {
			continue
		}
		if err != nil {
			return nil, nil, ErrEnvelope
		}
		if lineBytes == len(line) && (bytes.Equal(line, []byte("\r\n")) || bytes.Equal(line, []byte("\n"))) {
			break
		}
		lineBytes = 0
	}
	if bytes.IndexByte(raw.Bytes(), 0) >= 0 {
		return nil, nil, ErrEnvelope
	}
	header, err := textproto.NewReader(bufio.NewReader(bytes.NewReader(raw.Bytes()))).ReadMIMEHeader()
	if err != nil || len(header) == 0 {
		return nil, nil, ErrEnvelope
	}
	recognized := false
	for _, name := range []string{"From", "To", "Cc", "Bcc", "Date", "Subject", "Message-Id", "Mime-Version", "Content-Type"} {
		if len(header.Values(name)) > 0 {
			recognized = true
		}
	}
	if !recognized {
		return nil, nil, ErrEnvelope
	}
	return header, reader, nil
}
func Validate(input io.Reader) error { _, _, err := ReadEnvelope(input); return err }
func word(value string) string {
	decoder := mime.WordDecoder{CharsetReader: func(label string, input io.Reader) (io.Reader, error) { return charset.NewReaderLabel(label, input) }}
	result, err := decoder.DecodeHeader(value)
	if err != nil {
		result = value
	}
	result = strings.TrimSpace(strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, result))
	for len(result) > 1000 {
		_, n := utf8.DecodeLastRuneInString(result)
		result = result[:len(result)-n]
	}
	return result
}
func addresses(header textproto.MIMEHeader, key string) []string {
	result := []string{}
	list, err := mail.ParseAddressList(header.Get(key))
	if err != nil {
		return result
	}
	for _, a := range list {
		if len(result) >= 100 {
			break
		}
		if len(a.Address) <= 320 {
			result = append(result, a.Address)
		}
	}
	return result
}
func Metadata(header textproto.MIMEHeader) r.DocumentEmailMetadata {
	value := r.DocumentEmailMetadata{Subject: word(header.Get("Subject")), MessageID: word(header.Get("Message-Id")), Recipients: addresses(header, "To"), CC: addresses(header, "Cc"), BCC: addresses(header, "Bcc")}
	if list := addresses(header, "From"); len(list) > 0 {
		value.Sender = list[0]
	}
	if stamp, err := mail.ParseDate(header.Get("Date")); err == nil {
		value.Date = stamp.Format("2006-01-02")
	}
	return value
}

type documentMimeContentBudgetReader struct {
	ctx       context.Context
	reader    io.Reader
	remaining *int64
}

func (b documentMimeContentBudgetReader) Read(p []byte) (int, error) {
	if err := b.ctx.Err(); err != nil {
		return 0, err
	}
	if *b.remaining < 0 {
		return 0, ErrLimit
	}
	if int64(len(p)) > *b.remaining+1 {
		p = p[:*b.remaining+1]
	}
	n, err := b.reader.Read(p)
	*b.remaining -= int64(n)
	if *b.remaining < 0 {
		return 0, ErrLimit
	}
	return n, err
}

type documentMimeContentParser struct {
	ctx                         context.Context
	count, headers, attachments int
	decoded                     int64
	failures, textFailures      bool
	visit                       func(r.DocumentEmailPart) error
}

type documentMimeContentDecodingReader struct {
	reader  io.Reader
	failure error
}

func (r *documentMimeContentDecodingReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if err != nil && !errors.Is(err, io.EOF) {
		r.failure = err
	}
	return n, err
}

func (p *documentMimeContentParser) textFailed(path, name, media, code string) (documentMimeContentBodyText, error) {
	p.textFailures = true
	return documentMimeContentBodyText{}, p.failed(path, name, media, code)
}

func (p *documentMimeContentParser) failed(path, name, media, code string) error {
	p.failures = true
	if p.visit != nil {
		return p.visit(r.DocumentEmailPart{Path: path, Filename: name, MediaType: media, Status: "failed", FailureCode: code})
	}
	return nil
}
func headerSize(header textproto.MIMEHeader) (int, int) {
	size, count := 0, 0
	for key, values := range header {
		for _, value := range values {
			count++
			size += len(key) + len(value)
		}
	}
	return size, count
}
func (p *documentMimeContentParser) part(header textproto.MIMEHeader, input io.Reader, path string, depth int) (documentMimeContentBodyText, error) {
	if err := p.ctx.Err(); err != nil {
		return documentMimeContentBodyText{}, err
	}
	p.count++
	if p.count > 100 || depth > 16 {
		return documentMimeContentBodyText{}, ErrLimit
	}
	size, count := headerSize(header)
	if size > 64<<10 || count > 200 || p.headers+size > 256<<10 {
		return p.textFailed(path, "", "", "resource_limit")
	}
	p.headers += size
	media, params, err := mime.ParseMediaType(header.Get("Content-Type"))
	if header.Get("Content-Type") == "" {
		media = "text/plain"
		params = map[string]string{}
		err = nil
	}
	if err != nil {
		return p.textFailed(path, "", "", "invalid_mime")
	}
	_, disposition, e := mime.ParseMediaType(header.Get("Content-Disposition"))
	if e != nil {
		disposition = map[string]string{}
	}
	name := word(disposition["filename"])
	if name == "" {
		name = word(params["name"])
	}
	isMultipart := strings.HasPrefix(media, "multipart/")
	if !isMultipart && path == "" {
		path = "1"
	}
	isAttachment := name != "" || strings.HasPrefix(strings.ToLower(header.Get("Content-Disposition")), "attachment") || (media != "text/plain" && media != "text/html")
	encoding := strings.ToLower(strings.TrimSpace(header.Get("Content-Transfer-Encoding")))
	var decoded io.Reader = input
	switch encoding {
	case "", "7bit", "8bit", "binary":
	case "base64":
		decoded = base64.NewDecoder(base64.StdEncoding, input)
	case "quoted-printable":
		decoded = quotedprintable.NewReader(input)
	default:
		if isMultipart || !isAttachment {
			return p.textFailed(path, name, media, "unsupported_encoding")
		}
		return documentMimeContentBodyText{}, p.failed(path, name, media, "unsupported_encoding")
	}
	if isMultipart {
		if depth >= 16 || params["boundary"] == "" || (encoding != "" && encoding != "7bit" && encoding != "8bit" && encoding != "binary") {
			return p.textFailed(path, name, media, "invalid_mime")
		}
		reader := multipart.NewReader(input, params["boundary"])
		var combined strings.Builder
		var selected documentMimeContentBodyText
		for index := 1; ; index++ {
			child, err := reader.NextRawPart()
			if err == io.EOF {
				if media != "multipart/alternative" {
					selected.value = combined.String()
				}
				return selected, nil
			}
			if err != nil {
				p.failures = true
				return documentMimeContentBodyText{}, err
			}
			childPath := strconv.Itoa(index)
			if path != "" {
				childPath = path + "." + childPath
			}
			body, err := p.part(child.Header, child, childPath, depth+1)
			closeErr := child.Close()
			if err != nil {
				return documentMimeContentBodyText{}, err
			}
			if closeErr != nil {
				return documentMimeContentBodyText{}, closeErr
			}
			if !body.present {
				continue
			}
			if media == "multipart/alternative" {
				if !selected.present || body.plain || !selected.plain {
					selected = body
				}
				continue
			}
			separatorBytes := 0
			if selected.present {
				separatorBytes = 1
			}
			if combined.Len()+len(body.value)+separatorBytes > maxText {
				return documentMimeContentBodyText{}, ErrLimit
			}
			if selected.present {
				combined.WriteByte('\n')
				selected.plain = selected.plain && body.plain
			} else {
				selected = documentMimeContentBodyText{present: true, plain: body.plain}
			}
			combined.WriteString(body.value)
		}
	}
	tracked := &documentMimeContentDecodingReader{reader: decoded}
	bounded := documentMimeContentBudgetReader{p.ctx, tracked, &p.decoded}
	if isAttachment {
		status, code := "skipped", "unsupported_media"
		if media == "application/pdf" || media == "image/png" || media == "image/jpeg" {
			p.attachments++
			if p.attachments > 20 {
				return documentMimeContentBodyText{}, p.failed(path, name, media, "resource_limit")
			}
			status = "pending"
			code = ""
		}
		if p.visit != nil {
			if err := p.visit(r.DocumentEmailPart{Path: path, Filename: name, MediaType: media, Status: status, FailureCode: code, Reader: bounded}); err != nil {
				if p.ctx.Err() == nil && tracked.failure != nil && errors.Is(err, tracked.failure) {
					return documentMimeContentBodyText{}, p.failed(path, name, media, "invalid_encoding")
				}
				return documentMimeContentBodyText{}, err
			}
		}
		if _, err := io.Copy(io.Discard, bounded); err != nil {
			return documentMimeContentBodyText{}, p.failed(path, name, media, "invalid_encoding")
		}
		return documentMimeContentBodyText{}, nil
	}
	textReader := io.Reader(bounded)
	if label := params["charset"]; label != "" {
		textReader, err = charset.NewReaderLabel(label, bounded)
		if err != nil {
			return p.textFailed(path, name, media, "unsupported_charset")
		}
	}
	text, err := io.ReadAll(io.LimitReader(textReader, maxText+1))
	if err != nil {
		return p.textFailed(path, name, media, "invalid_encoding")
	}
	if len(text) > maxText || !utf8.Valid(text) || bytes.IndexByte(text, 0) >= 0 {
		return p.textFailed(path, name, media, "resource_limit")
	}
	value := string(text)
	if media == "text/html" {
		value, err = plainHTML(value)
		if err != nil {
			return p.textFailed(path, name, media, "resource_limit")
		}
	}
	return documentMimeContentBodyText{value: strings.TrimSpace(value), present: true, plain: media == "text/plain"}, nil
}
func plainHTML(source string) (string, error) {
	tokenizer := html.NewTokenizer(strings.NewReader(source))
	tokenizer.SetMaxBuf(64 << 10)
	var output strings.Builder
	type documentMimeContentElement struct {
		name   string
		hidden bool
	}
	stack := []documentMimeContentElement{}
	hidden := func() bool { return len(stack) > 0 && stack[len(stack)-1].hidden }
	lineBreak := func() {
		if output.Len() > 0 && !strings.HasSuffix(output.String(), "\n") {
			output.WriteByte('\n')
		}
	}
	for {
		kind := tokenizer.Next()
		if kind == html.ErrorToken {
			if tokenizer.Err() == io.EOF {
				return strings.TrimSpace(output.String()), nil
			}
			return "", tokenizer.Err()
		}
		switch kind {
		case html.StartTagToken, html.SelfClosingTagToken:
			token := tokenizer.Token()
			if !hidden() && htmlBreak(token.Data) {
				lineBreak()
			}
			if !htmlVoid(token.Data) {
				if len(stack) >= 64 {
					return "", ErrLimit
				}
				stack = append(stack, documentMimeContentElement{name: token.Data, hidden: hidden() || token.Data == "script" || token.Data == "style" || token.Data == "template" || token.Data == "head"})
			}
		case html.EndTagToken:
			token := tokenizer.Token()
			for index := len(stack) - 1; index >= 0; index-- {
				if stack[index].name == token.Data {
					stack = stack[:index]
					break
				}
			}
			if !hidden() && htmlBreak(token.Data) {
				lineBreak()
			}
		case html.TextToken:
			if !hidden() {
				output.Write(tokenizer.Text())
			}
		}
		if output.Len() > maxText {
			return "", ErrLimit
		}
	}
}

func htmlVoid(name string) bool {
	switch name {
	case "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr":
		return true
	default:
		return false
	}
}

func htmlBreak(name string) bool {
	switch name {
	case "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul":
		return true
	default:
		return false
	}
}

func Inspect(ctx context.Context, input io.Reader, visit func(r.DocumentEmailPart) error) (r.DocumentEmailInspection, error) {
	header, body, err := ReadEnvelope(input)
	if err != nil {
		return r.DocumentEmailInspection{}, err
	}
	result := r.DocumentEmailInspection{Metadata: Metadata(header)}
	p := documentMimeContentParser{ctx: ctx, decoded: int64(MaxRawBytes), visit: visit}
	parsed, err := p.part(header, body, "", 0)
	result.ContentFailures = p.failures || err != nil
	result.TextFailures = p.textFailures || err != nil
	result.Text = strings.TrimSpace(parsed.value)
	prefix := []string{}
	if result.Metadata.Subject != "" {
		prefix = append(prefix, result.Metadata.Subject)
	}
	if result.Metadata.Sender != "" {
		prefix = append(prefix, result.Metadata.Sender)
	}
	if result.Text != "" {
		prefix = append(prefix, result.Text)
	}
	result.Text = strings.Join(prefix, "\n")
	if len(result.Text) > maxText {
		result.Text = ""
		err = ErrLimit
		result.ContentFailures = true
		result.TextFailures = true
	}
	if err != nil {
		return result, fmt.Errorf("inspect email content: %w", err)
	}
	return result, nil
}
