package datasources

import (
	"context"
	"encoding/json"
	"strings"
	"unicode/utf8"

	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/jackc/pgx/v5"
)

func invoiceFilterColumn(field string) string {
	switch field {
	case "number":
		return "number"
	case "seller":
		return "seller_name"
	case "buyer":
		return "buyer_name"
	case "currency":
		return "currency"
	case "typeCode":
		return "type_code"
	case "format":
		return "format"
	case "paymentMeansCode":
		return "payment_means_code"
	default:
		return ""
	}
}

func (s *InvoiceDataSource) FilterValues(ctx context.Context, a document.DocumentActor, q m.InvoiceFilterValueQuery) (m.InvoiceFilterValuePage, error) {
	result := m.InvoiceFilterValuePage{Items: []string{}}
	if err := q.Validate(); err != nil {
		return result, err
	}
	q.Text = strings.TrimSpace(q.Text)
	fingerprint, _ := pagination.Fingerprint([]string{a.AccountID, q.Field, q.Text})
	var after string
	if q.Cursor != "" {
		key, err := pagination.DecodeBounded(q.Cursor, "invoice-filter-values", fingerprint, "value_asc", invoiceCursorBytes)
		if err != nil || len(key) != 1 || json.Unmarshal(key["value"], &after) != nil || after == "" || !utf8.ValidString(after) || utf8.RuneCountInString(after) > 4000 || strings.ContainsRune(after, 0) {
			return result, m.ErrInvalid
		}
	}
	column := invoiceFilterColumn(q.Field)
	query := `WITH values_in_library AS (SELECT DISTINCT ` + column + ` COLLATE "C" AS value FROM invoices WHERE account_id=$1 AND ` + column + `<>'')
 SELECT value FROM values_in_library
 WHERE ($2::text='' OR strpos(lower(value COLLATE pg_catalog.pg_unicode_fast),lower($2::text COLLATE pg_catalog.pg_unicode_fast))>0)
 AND ($3::text='' OR (lower(value COLLATE pg_catalog.pg_unicode_fast),value)>(lower($3::text COLLATE pg_catalog.pg_unicode_fast),$3 COLLATE "C"))
 ORDER BY lower(value COLLATE pg_catalog.pg_unicode_fast),value LIMIT $4`
	err := s.readTx(ctx, a, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, query, a.AccountID, q.Text, after, q.Limit+1)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var value string
			if err := rows.Scan(&value); err != nil {
				return err
			}
			result.Items = append(result.Items, value)
		}
		return rows.Err()
	})
	if err != nil {
		return result, err
	}
	if len(result.Items) > q.Limit {
		result.Items = result.Items[:q.Limit]
		result.NextCursor, err = pagination.EncodeBounded("invoice-filter-values", fingerprint, "value_asc", map[string]string{"value": result.Items[q.Limit-1]}, invoiceCursorBytes)
	}
	return result, err
}
