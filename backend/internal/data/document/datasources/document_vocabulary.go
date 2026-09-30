package datasources

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	r "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const vocabularyOperation = "document-vocabulary"

func vocabularyCursorFingerprint(account string, input m.DocumentVocabularyInput) (string, error) {
	id, err := uuid.Parse(account)
	if err != nil || id == uuid.Nil {
		return "", cursorFailure()
	}
	return pagination.Fingerprint(documentVocabularyFingerprint{1, vocabularyOperation, id.String(), input.Field, input.Query, input.Limit})
}

func decodeVocabularyPosition(token, fingerprint, field string) (string, error) {
	if token == "" {
		return "", nil
	}
	fields, err := pagination.Decode(token, vocabularyOperation, fingerprint, "value")
	if err != nil || len(fields) != 1 {
		return "", cursorFailure()
	}
	var value string
	if json.Unmarshal(fields["value"], &value) != nil || m.ValidateVocabularyValue(field, value) != nil {
		return "", cursorFailure()
	}
	return value, nil
}

func encodeVocabularyPosition(fingerprint, field, value string) (string, error) {
	if err := m.ValidateVocabularyValue(field, value); err != nil {
		return "", err
	}
	token, err := pagination.Encode(vocabularyOperation, fingerprint, "value", map[string]string{"value": value})
	if err != nil {
		return "", fmt.Errorf("encode vocabulary cursor: %w", err)
	}
	return token, nil
}

func vocabularyQuery(field string) string {
	values := `SELECT tag.value FROM documents d CROSS JOIN LATERAL unnest(d.tags) tag(value) WHERE d.account_id=$1`
	comparison := `value COLLATE pg_catalog.pg_unicode_fast`
	boundary := `$3::text COLLATE pg_catalog.pg_unicode_fast`
	if field != "tag" {
		comparison = `lower(value COLLATE pg_catalog.pg_unicode_fast)`
		boundary = `lower($3::text COLLATE pg_catalog.pg_unicode_fast)`
		values = `SELECT d.sender AS value FROM documents d WHERE d.account_id=$1 AND d.sender<>''`
		if field == "recipient" {
			values = `SELECT recipient.value FROM documents d CROSS JOIN LATERAL unnest(d.recipients || d.cc || d.bcc) recipient(value) WHERE d.account_id=$1 AND recipient.value<>''`
		}
	}
	return `WITH values_in_library AS (` + values + `),
 grouped AS (SELECT ` + comparison + ` AS comparison_key,min(value COLLATE "C") AS value FROM values_in_library GROUP BY ` + comparison + `)
 SELECT comparison_key,value FROM grouped
 WHERE ($2::text='' OR strpos(lower(comparison_key COLLATE pg_catalog.pg_unicode_fast),lower($2::text COLLATE pg_catalog.pg_unicode_fast))>0)
 AND ($3::text='' OR comparison_key COLLATE pg_catalog.pg_unicode_fast > ` + boundary + `)
 ORDER BY comparison_key COLLATE pg_catalog.pg_unicode_fast LIMIT $4`
}

func (source *DocumentDataSource) ListVocabularyRecords(ctx context.Context, actor m.DocumentActor, input m.DocumentVocabularyInput) (r.DocumentVocabularyRecords, error) {
	result := r.DocumentVocabularyRecords{Items: []r.DocumentVocabularyRecord{}}
	input, err := input.Normalize()
	if err != nil {
		return result, err
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	err = pgx.BeginTxFunc(ctx, source.database, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout='5s'"); err != nil {
			return err
		}
		fingerprint, err := vocabularyCursorFingerprint(actor.AccountID, input)
		if err != nil {
			return err
		}
		boundary, err := decodeVocabularyPosition(input.Cursor, fingerprint, input.Field)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, vocabularyQuery(input.Field), actor.AccountID, input.Query, boundary, input.Limit+1)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var record r.DocumentVocabularyRecord
			if err := rows.Scan(&record.ComparisonKey, &record.Value); err != nil {
				return err
			}
			result.Items = append(result.Items, record)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		if len(result.Items) > input.Limit {
			result.Items = result.Items[:input.Limit]
			result.NextCursor, err = encodeVocabularyPosition(fingerprint, input.Field, result.Items[input.Limit-1].Value)
			return err
		}
		return nil
	})
	return result, documentError(err)
}
