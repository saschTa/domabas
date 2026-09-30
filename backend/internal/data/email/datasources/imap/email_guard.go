package imap

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
)

var ErrProtocolLimit = errors.New("IMAP response exceeds permitted protocol bounds")

type EmailIMAPConnectionGuard struct {
	net.Conn
	reader                               *bufio.Reader
	mutex                                sync.Mutex
	uid                                  uint32
	allowed                              int64
	total                                atomic.Int64
	literal                              int64
	output                               []byte
	frame                                []string
	frameBytes, frames, literals, tokens int
	bodyCount                            atomic.Int32
	failed                               error
}

func NewEmailIMAPConnectionGuard(connection net.Conn) *EmailIMAPConnectionGuard {
	return &EmailIMAPConnectionGuard{Conn: connection, reader: bufio.NewReaderSize(connection, 4096), allowed: 2 << 20}
}
func (g *EmailIMAPConnectionGuard) Body(uid uint32) {
	g.mutex.Lock()
	g.uid = uid
	g.allowed = g.total.Load() + (102 << 20)
	g.bodyCount.Store(0)
	g.mutex.Unlock()
}
func (g *EmailIMAPConnectionGuard) EndBody() {
	g.mutex.Lock()
	g.uid = 0
	g.allowed = g.total.Load() + (2 << 20)
	g.mutex.Unlock()
}
func (g *EmailIMAPConnectionGuard) reject(err error) (int, error) {
	g.failed = err
	_ = g.Conn.Close()
	return 0, err
}
func lex(line []byte) ([]string, error) {
	result := []string{}
	for at := 0; at < len(line); {
		c := line[at]
		if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
			at++
			continue
		}
		if c == '(' || c == ')' {
			result = append(result, string(c))
			at++
			continue
		}
		start := at
		if c == '"' {
			at++
			escaped, closed := false, false
			for at < len(line) {
				c = line[at]
				at++
				if escaped {
					escaped = false
					continue
				}
				if c == '\\' {
					escaped = true
				} else if c == '"' {
					closed = true
					break
				}
			}
			if !closed {
				return nil, ErrProtocolLimit
			}
		} else {
			for at < len(line) && !bytes.ContainsRune([]byte(" ()\t\r\n"), rune(line[at])) {
				if line[at] == 0 {
					return nil, ErrProtocolLimit
				}
				at++
			}
		}
		if at-start > 8192 || at == start {
			return nil, ErrProtocolLimit
		}
		result = append(result, string(line[start:at]))
		if len(result) > 4096 {
			return nil, ErrProtocolLimit
		}
	}
	return result, nil
}
func fetchLiteral(tokens []string) (bool, error) {
	if len(tokens) < 4 || tokens[0] != "*" || strings.ToUpper(tokens[2]) != "FETCH" || tokens[3] != "(" {
		return false, nil
	}
	if _, err := strconv.ParseUint(tokens[1], 10, 32); err != nil {
		return false, ErrProtocolLimit
	}
	for at := 4; at < len(tokens); {
		attribute := strings.ToUpper(tokens[at])
		at++
		if attribute == ")" {
			if at != len(tokens) {
				return false, ErrProtocolLimit
			}
			return false, nil
		}
		if attribute != "UID" && attribute != "RFC822.SIZE" && attribute != "INTERNALDATE" && attribute != "FLAGS" && attribute != "BODY[]" {
			return false, ErrProtocolLimit
		}
		if at == len(tokens) {
			return attribute == "BODY[]", nil
		}
		if attribute == "FLAGS" {
			if tokens[at] != "(" {
				return false, ErrProtocolLimit
			}
			at++
			for at < len(tokens) && tokens[at] != ")" {
				if tokens[at] == "(" {
					return false, ErrProtocolLimit
				}
				at++
			}
			if at == len(tokens) {
				return false, ErrProtocolLimit
			}
			at++
		} else {
			if tokens[at] == "(" || tokens[at] == ")" {
				return false, ErrProtocolLimit
			}
			at++
		}
	}
	return false, nil
}
func (g *EmailIMAPConnectionGuard) frameValid(complete bool, uid uint32) error {
	depth := 0
	for _, token := range g.frame {
		if token == "(" {
			depth++
			if depth > 32 {
				return ErrProtocolLimit
			}
		}
		if token == ")" {
			depth--
			if depth < 0 {
				return ErrProtocolLimit
			}
		}
	}
	if complete && depth != 0 {
		return ErrProtocolLimit
	}
	if uid == 0 {
		return nil
	}
	if _, err := fetchLiteral(g.frame); err != nil {
		return err
	}
	if !complete || len(g.frame) < 4 || strings.ToUpper(g.frame[2]) != "FETCH" {
		return nil
	}
	foundUID, bodies := uint64(0), 0
	uidCount := 0
	for at := 4; at < len(g.frame)-1; at++ {
		switch strings.ToUpper(g.frame[at]) {
		case "UID":
			at++
			if at >= len(g.frame) {
				return ErrProtocolLimit
			}
			value, err := strconv.ParseUint(g.frame[at], 10, 32)
			if err != nil || value == 0 {
				return ErrProtocolLimit
			}
			foundUID = value
			uidCount++
		case "BODY[]":
			at++
			bodies++
		case "FLAGS":
			at++
			for at < len(g.frame) && g.frame[at] != ")" {
				at++
			}
		case "RFC822.SIZE", "INTERNALDATE":
			at++
		}
	}
	if bodies > 0 && (bodies != 1 || uidCount != 1 || foundUID != uint64(uid)) {
		return ErrProtocolLimit
	}
	return nil
}
func (g *EmailIMAPConnectionGuard) Read(buffer []byte) (int, error) {
	if g.failed != nil {
		return 0, g.failed
	}
	if len(buffer) == 0 {
		return 0, nil
	}
	if len(g.output) > 0 {
		n := copy(buffer, g.output)
		g.output = g.output[n:]
		return n, nil
	}
	if g.literal > 0 {
		if int64(len(buffer)) > g.literal {
			buffer = buffer[:g.literal]
		}
		n, err := g.reader.Read(buffer)
		g.literal -= int64(n)
		g.total.Add(int64(n))
		if err != nil && g.literal != 0 {
			return g.reject(err)
		}
		return n, err
	}
	var line []byte
	for {
		value, err := g.reader.ReadByte()
		if err != nil {
			if len(line) > 0 && err == io.EOF {
				err = io.ErrUnexpectedEOF
			}
			return g.reject(err)
		}
		line = append(line, value)
		if len(line)+g.frameBytes > 64<<10 {
			return g.reject(ErrProtocolLimit)
		}
		if value == '\n' {
			if len(line) < 2 || line[len(line)-2] != '\r' {
				return g.reject(ErrProtocolLimit)
			}
			break
		}
	}
	g.total.Add(int64(len(line)))
	g.frameBytes += len(line)
	g.mutex.Lock()
	uid, allowed := g.uid, g.allowed
	g.mutex.Unlock()
	if g.total.Load() > allowed || g.total.Load() > 128<<20 {
		return g.reject(ErrProtocolLimit)
	}
	tokens, err := lex(line)
	if err != nil {
		return g.reject(err)
	}
	g.tokens += len(tokens)
	if g.tokens > 32768 || len(g.frame)+len(tokens) > 4096 {
		return g.reject(ErrProtocolLimit)
	}
	length := int64(-1)
	if len(tokens) > 0 {
		marker := tokens[len(tokens)-1]
		if strings.HasPrefix(marker, "{") || strings.HasPrefix(marker, "~{") {
			if !strings.HasPrefix(marker, "{") || !strings.HasSuffix(marker, "}") {
				return g.reject(ErrProtocolLimit)
			}
			digits := strings.TrimSuffix(strings.TrimPrefix(marker, "{"), "}")
			if digits == "" || strings.Trim(digits, "0123456789") != "" {
				return g.reject(ErrProtocolLimit)
			}
			length, err = strconv.ParseInt(digits, 10, 64)
			if err != nil {
				return g.reject(ErrProtocolLimit)
			}
			tokens = tokens[:len(tokens)-1]
		}
	}
	g.frame = append(g.frame, tokens...)
	if length >= 0 {
		body, err := fetchLiteral(g.frame)
		if err != nil && uid != 0 {
			return g.reject(err)
		}
		limit := int64(64 << 10)
		if body && uid != 0 {
			if g.bodyCount.Add(1) > 1 {
				return g.reject(ErrProtocolLimit)
			}
			limit = 100 << 20
		}
		g.literals++
		if g.literals > 128 || length > limit || g.total.Load()+length > allowed || g.total.Load()+length > 128<<20 {
			return g.reject(ErrProtocolLimit)
		}
		g.frame = append(g.frame, "literal")
		g.literal = length
	} else {
		g.frames++
		if g.frames > 4096 {
			return g.reject(ErrProtocolLimit)
		}
	}
	if err = g.frameValid(length < 0, uid); err != nil {
		return g.reject(err)
	}
	if length < 0 {
		g.frame = nil
		g.frameBytes = 0
	}
	g.output = line
	n := copy(buffer, g.output)
	g.output = g.output[n:]
	return n, nil
}
