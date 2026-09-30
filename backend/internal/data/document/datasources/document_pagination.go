package datasources

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
)

const cursorTimestamp = "2006-01-02T15:04:05.000000Z"

type documentPosition struct {
	ID        string
	CreatedAt time.Time
	Title     string
	Date      string
	Missing   bool
	Score     float64
}

type documentFingerprint struct {
	Version        int                      `json:"v"`
	Namespace      string                   `json:"namespace"`
	Operation      string                   `json:"operation"`
	Mode           string                   `json:"mode"`
	Query          string                   `json:"query"`
	Tags           []string                 `json:"tags"`
	Sender         string                   `json:"sender"`
	Recipient      string                   `json:"recipient"`
	Sort           string                   `json:"sort"`
	Limit          int                      `json:"limit"`
	Space          m.DocumentEmbeddingSpace `json:"space"`
	SenderMatch    string                   `json:"senderMatch,omitempty"`
	RecipientMatch string                   `json:"recipientMatch,omitempty"`
	Kinds          []string                 `json:"kinds,omitempty"`
}

func cursorFailure() error {
	return m.DocumentValidationError{Message: "invalid document pagination cursor"}
}

func documentCursorFingerprint(account, operation string, input m.DocumentSearchInput) (string, error) {
	id, err := uuid.Parse(account)
	if err != nil || id == uuid.Nil {
		return "", cursorFailure()
	}
	tags := input.Tags
	if tags == nil {
		tags = []string{}
	}
	space := m.DocumentEmbeddingSpace{}
	if input.UsesEmbeddings() {
		space = input.Space
	}
	fingerprint := documentFingerprint{Version: 1, Namespace: id.String(), Operation: operation, Mode: input.Mode, Query: input.Query, Tags: tags, Sender: input.Sender, Recipient: input.Recipient, Sort: input.Sort, Limit: input.Limit, Space: space}
	fingerprint.Kinds = input.Kinds
	if input.SenderMatch == "exact" && input.Sender != "" {
		fingerprint.SenderMatch = "exact"
	}
	if input.RecipientMatch == "exact" && input.Recipient != "" {
		fingerprint.RecipientMatch = "exact"
	}
	return pagination.Fingerprint(fingerprint)
}

func decodeDocumentPosition(token, operation, fingerprint, sort string) (*documentPosition, error) {
	if token == "" {
		return nil, nil
	}
	fields, err := pagination.Decode(token, operation, fingerprint, sort)
	if err != nil {
		return nil, cursorFailure()
	}
	position := &documentPosition{}
	readString := func(name string, value *string) bool {
		raw, ok := fields[name]
		return ok && json.Unmarshal(raw, value) == nil
	}
	if !readString("id", &position.ID) {
		return nil, cursorFailure()
	}
	id, err := uuid.Parse(position.ID)
	if err != nil || id == uuid.Nil || id.String() != position.ID {
		return nil, cursorFailure()
	}
	valid := false
	switch sort {
	case "relevance":
		var value string
		if len(fields) == 2 && readString("score", &value) && len(value) <= 32 {
			position.Score, err = strconv.ParseFloat(value, 64)
			valid = err == nil && !math.IsNaN(position.Score) && !math.IsInf(position.Score, 0) && strconv.FormatFloat(position.Score, 'g', -1, 64) == value
		}
	case "newest", "oldest":
		var value string
		if len(fields) == 2 && readString("createdAt", &value) {
			position.CreatedAt, err = time.Parse(cursorTimestamp, value)
			valid = err == nil && position.CreatedAt.Year() >= 1 && position.CreatedAt.Year() <= 9999 && position.CreatedAt.Format(cursorTimestamp) == value
		}
	case "title":
		valid = len(fields) == 2 && readString("title", &position.Title) && utf8.ValidString(position.Title) && len(position.Title) <= 1600 && utf8.RuneCountInString(position.Title) <= 400 && !strings.ContainsRune(position.Title, 0)
	case "date-newest", "date-oldest":
		raw, ok := fields["missing"]
		if ok && json.Unmarshal(raw, &position.Missing) == nil {
			if position.Missing {
				valid = len(fields) == 2
			} else if len(fields) == 3 && readString("date", &position.Date) {
				stamp, parseErr := time.Parse("2006-01-02", position.Date)
				valid = parseErr == nil && stamp.Year() >= 1 && stamp.Year() <= 9999 && stamp.Format("2006-01-02") == position.Date
			}
		}
	}
	if !valid {
		return nil, cursorFailure()
	}
	return position, nil
}

func encodeDocumentPosition(operation, fingerprint, sort string, position documentPosition) (string, error) {
	key := map[string]any{"id": position.ID}
	switch sort {
	case "relevance":
		key["score"] = strconv.FormatFloat(position.Score, 'g', -1, 64)
	case "newest", "oldest":
		key["createdAt"] = position.CreatedAt.UTC().Format(cursorTimestamp)
	case "title":
		key["title"] = position.Title
	case "date-newest", "date-oldest":
		key["missing"] = position.Date == ""
		if position.Date != "" {
			key["date"] = position.Date
		}
	default:
		return "", cursorFailure()
	}
	token, err := pagination.Encode(operation, fingerprint, sort, key)
	if err != nil {
		return "", fmt.Errorf("encode document cursor: %w", err)
	}
	if _, err = decodeDocumentPosition(token, operation, fingerprint, sort); err != nil {
		return "", fmt.Errorf("encode document position: %w", err)
	}
	return token, nil
}

func searchOrder(sort, qualifier string) string {
	switch sort {
	case "newest":
		return qualifier + "created_at DESC," + qualifier + "id DESC"
	case "oldest":
		return qualifier + "created_at ASC," + qualifier + "id ASC"
	case "title":
		return qualifier + "lower_title COLLATE pg_catalog.pg_unicode_fast ASC," + qualifier + "id ASC"
	case "date-newest":
		return qualifier + "sort_date DESC NULLS LAST," + qualifier + "id ASC"
	case "date-oldest":
		return qualifier + "sort_date ASC NULLS LAST," + qualifier + "id ASC"
	default:
		return qualifier + "score DESC," + qualifier + "id ASC"
	}
}

func searchSeek(sort string, position *documentPosition, args *[]any) string {
	if position == nil {
		return ""
	}
	bind := func(value any) string { *args = append(*args, value); return fmt.Sprintf("$%d", len(*args)) }
	id := bind(position.ID) + "::uuid"
	var predicate string
	switch sort {
	case "newest", "oldest":
		operator := ">"
		if sort == "newest" {
			operator = "<"
		}
		stamp := bind(position.CreatedAt) + "::timestamptz"
		predicate = fmt.Sprintf("(created_at,id) %s (%s,%s)", operator, stamp, id)
	case "title":
		title := bind(position.Title) + "::text COLLATE pg_catalog.pg_unicode_fast"
		predicate = fmt.Sprintf("(lower_title COLLATE pg_catalog.pg_unicode_fast > %s OR (lower_title COLLATE pg_catalog.pg_unicode_fast = %s AND id > %s))", title, title, id)
	case "date-newest", "date-oldest":
		if position.Missing {
			predicate = "sort_date IS NULL AND id > " + id
		} else {
			operator := ">"
			if sort == "date-newest" {
				operator = "<"
			}
			date := bind(position.Date) + "::date"
			predicate = fmt.Sprintf("(sort_date %s %s OR (sort_date = %s AND id > %s) OR sort_date IS NULL)", operator, date, date, id)
		}
	default:
		score := bind(position.Score) + "::float8"
		predicate = fmt.Sprintf("(score < %s OR (score = %s AND id > %s))", score, score, id)
	}
	return " WHERE " + predicate
}
