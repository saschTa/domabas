package datasources

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"
	"unicode/utf8"

	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	"github.com/domabas/domabas/backend/internal/data/postgres/pagination"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const invoiceCursorBytes = 32768

func plainInvoiceSearch(text string) bool {
	if strings.ContainsRune(text, '"') {
		return false
	}
	for _, word := range strings.Fields(text) {
		if strings.EqualFold(word, "or") || strings.HasPrefix(word, "-") {
			return false
		}
	}
	return true
}

func invoiceQueryFingerprint(account string, q m.InvoiceQuery) string {
	criteria := []string{account, q.Source}
	if q.Text != "" {
		criteria = append(criteria, q.Text)
	}
	extras := []string{q.Sort, q.Number, q.Seller, q.Buyer, q.Currency, q.TypeCode, q.Format, q.PaymentMeansCode, q.CreatedFrom, q.CreatedTo, q.IssueFrom, q.IssueTo, q.DueFrom, q.DueTo, q.TotalMin, q.TotalMax}
	if strings.Join(extras, "") != "" {
		criteria = append(criteria, extras...)
	}
	fingerprint, _ := pagination.Fingerprint(criteria)
	return fingerprint
}

func invoiceSortExpression(sort string) string {
	switch strings.TrimSuffix(strings.TrimSuffix(sort, "_asc"), "_desc") {
	case "due":
		return "i.due_date"
	case "issue":
		return "i.issue_date"
	case "number":
		return "lower(NULLIF(i.number,'') COLLATE pg_catalog.pg_unicode_fast)"
	case "seller":
		return "lower(NULLIF(i.seller_name,'') COLLATE pg_catalog.pg_unicode_fast)"
	case "buyer":
		return "lower(NULLIF(i.buyer_name,'') COLLATE pg_catalog.pg_unicode_fast)"
	default:
		return "i.created_at"
	}
}

func invoiceSortValue(sort string, invoice r.InvoiceRecord) string {
	switch strings.TrimSuffix(strings.TrimSuffix(sort, "_asc"), "_desc") {
	case "due":
		return invoice.DueDate
	case "issue":
		return invoice.IssueDate
	case "number":
		return invoice.Number
	case "seller":
		return invoice.Seller.Name
	case "buyer":
		return invoice.Buyer.Name
	default:
		return ""
	}
}

func (s *InvoiceDataSource) List(ctx context.Context, a document.DocumentActor, q m.InvoiceQuery) (r.InvoiceRecordPage, error) {
	result := r.InvoiceRecordPage{Items: []r.InvoiceRecord{}}
	if err := q.Validate(); err != nil {
		return result, err
	}
	q.Text = strings.TrimSpace(q.Text)
	sort := q.Sort
	if sort == "" {
		sort = "created_desc"
		if q.Text != "" {
			sort = "relevance_desc"
		}
	}
	custom := sort != "created_desc" && sort != "created_asc" && sort != "relevance_desc"
	fingerprint := invoiceQueryFingerprint(a.AccountID, q)
	var after time.Time
	var afterID, value string
	var score float64
	if q.Cursor != "" {
		key, err := pagination.DecodeBounded(q.Cursor, "invoices", fingerprint, sort, invoiceCursorBytes)
		size := 2
		if custom || sort == "relevance_desc" {
			size = 3
		}
		if err != nil || len(key) != size || json.Unmarshal(key["at"], &after) != nil || json.Unmarshal(key["id"], &afterID) != nil || after.IsZero() || after.Year() < 1 || after.Year() > 9999 {
			return result, m.ErrInvalid
		}
		id, err := uuid.Parse(afterID)
		if err != nil || id.String() != afterID {
			return result, m.ErrInvalid
		}
		if sort == "relevance_desc" && (json.Unmarshal(key["score"], &score) != nil || math.IsNaN(score) || math.IsInf(score, 0) || score < 0.3 || score > 6) {
			return result, m.ErrInvalid
		}
		if custom {
			if json.Unmarshal(key["value"], &value) != nil || !utf8.ValidString(value) || utf8.RuneCountInString(value) > 4000 || strings.ContainsRune(value, 0) {
				return result, m.ErrInvalid
			}
			if value != "" && (strings.HasPrefix(sort, "due_") || strings.HasPrefix(sort, "issue_")) {
				if _, err := time.Parse("2006-01-02", value); err != nil || strings.HasPrefix(value, "0000-") {
					return result, m.ErrInvalid
				}
			}
		}
	}
	args := []any{}
	bind := func(value any) string { args = append(args, value); return fmt.Sprintf("$%d", len(args)) }
	conditions := []string{"i.account_id=" + bind(a.AccountID)}
	for _, filter := range [][2]string{{"source", q.Source}, {"number", q.Number}, {"seller_name", q.Seller}, {"buyer_name", q.Buyer}, {"currency", q.Currency}, {"type_code", q.TypeCode}, {"format", q.Format}, {"payment_means_code", q.PaymentMeansCode}} {
		if filter[1] != "" {
			conditions = append(conditions, "i."+filter[0]+"="+bind(filter[1]))
		}
	}
	for _, bound := range [][3]string{{"issue_date", ">=", q.IssueFrom}, {"issue_date", "<=", q.IssueTo}, {"due_date", ">=", q.DueFrom}, {"due_date", "<=", q.DueTo}} {
		if bound[2] != "" {
			conditions = append(conditions, "i."+bound[0]+bound[1]+bind(bound[2])+"::date")
		}
	}
	if q.CreatedFrom != "" {
		conditions = append(conditions, "i.created_at >= ("+bind(q.CreatedFrom)+"::date::timestamp AT TIME ZONE 'UTC')")
	}
	if q.CreatedTo != "" {
		conditions = append(conditions, "i.created_at < (("+bind(q.CreatedTo)+"::date + 1)::timestamp AT TIME ZONE 'UTC')")
	}
	if q.TotalMin != "" {
		conditions = append(conditions, "i.total_gross >= "+bind(q.TotalMin)+"::numeric")
	}
	if q.TotalMax != "" {
		conditions = append(conditions, "i.total_gross <= "+bind(q.TotalMax)+"::numeric")
	}
	prefix := "WITH "
	scoring := "0::float8"
	pageConditions := []string{"TRUE"}
	if q.Text != "" {
		term := bind(q.Text)
		plain := bind(plainInvoiceSearch(q.Text))
		prefix += "terms AS (SELECT websearch_to_tsquery('simple'," + term + ") AS query,tsvector_to_array(to_tsvector('simple'," + term + ")) AS words,lower(" + term + "::text COLLATE pg_catalog.pg_unicode_fast) AS needle), "
		scoring = `CASE WHEN cardinality(terms.words)=0 THEN 0::float8
 WHEN ` + plain + `::boolean AND lower(i.number COLLATE pg_catalog.pg_unicode_fast)=terms.needle THEN 6::float8
 WHEN ` + plain + `::boolean AND (strpos(lower(i.number COLLATE pg_catalog.pg_unicode_fast),terms.needle)>0 OR strpos(lower(i.seller_name COLLATE pg_catalog.pg_unicode_fast),terms.needle)>0 OR strpos(lower(i.buyer_name COLLATE pg_catalog.pg_unicode_fast),terms.needle)>0) THEN 4::float8
 WHEN i.search_vector @@ terms.query THEN 2+ts_rank_cd(i.search_vector,terms.query,32)::float8
 WHEN ` + plain + `::boolean THEN document_fuzzy_score(terms.words,i.search_vector) ELSE 0::float8 END`
		conditions = append(conditions, "("+plain+"::boolean OR i.search_vector @@ terms.query)")
		pageConditions = append(pageConditions, "i.score>=0.3")
	}
	from := "invoices i"
	if q.Text != "" {
		from += " CROSS JOIN terms"
	}
	materialized := "NOT MATERIALIZED"
	if q.Text != "" {
		materialized = "MATERIALIZED"
	}
	prefix += "scored AS " + materialized + " (SELECT i.*," + scoring + " AS score FROM " + from + " WHERE " + strings.Join(conditions, " AND ") + ") "
	direction, comparison := "DESC", "<"
	if strings.HasSuffix(sort, "_asc") {
		direction, comparison = "ASC", ">"
	}
	expression := invoiceSortExpression(sort)
	order := expression + " " + direction + " NULLS LAST,i.created_at DESC,i.id DESC"
	if sort == "relevance_desc" {
		order = "i.score DESC,i.created_at DESC,i.id DESC"
	}
	if !custom && sort != "relevance_desc" {
		order = "i.created_at " + direction + ",i.id " + direction
	}
	if afterID != "" {
		at, id := bind(after), bind(afterID)+"::uuid"
		tie := "(i.created_at,i.id)<(" + at + "," + id + ")"
		switch {
		case sort == "relevance_desc":
			pageConditions = append(pageConditions, "(i.score,i.created_at,i.id)<("+bind(score)+","+at+","+id+")")
		case !custom:
			pageConditions = append(pageConditions, "(i.created_at,i.id)"+comparison+"("+at+","+id+")")
		case value == "":
			pageConditions = append(pageConditions, "("+expression+" IS NULL AND "+tie+")")
		default:
			boundary := bind(value)
			if strings.HasPrefix(sort, "due_") || strings.HasPrefix(sort, "issue_") {
				boundary += "::date"
			} else {
				boundary = "lower(" + boundary + "::text COLLATE pg_catalog.pg_unicode_fast)"
			}
			pageConditions = append(pageConditions, "("+expression+" IS NULL OR "+expression+comparison+boundary+" OR ("+expression+"="+boundary+" AND "+tie+"))")
		}
	}
	query := prefix + "SELECT " + invoiceColumns + ",i.score FROM scored i JOIN documents d ON d.account_id=i.account_id AND d.id=i.document_id WHERE " + strings.Join(pageConditions, " AND ") + " ORDER BY " + order + " LIMIT " + bind(q.Limit+1)
	err := s.readTx(ctx, a, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL statement_timeout='5s'"); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var v r.InvoiceRecord
			if err = scanInvoice(rows, &v); err != nil {
				return err
			}
			result.Items = append(result.Items, v)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		invoices := make([]*r.InvoiceRecord, 0, min(len(result.Items), q.Limit))
		for index := range result.Items[:min(len(result.Items), q.Limit)] {
			invoices = append(invoices, &result.Items[index])
		}
		return readChildren(ctx, tx, a.AccountID, invoices)
	})
	if err != nil {
		return result, err
	}
	if len(result.Items) > q.Limit {
		result.Items = result.Items[:q.Limit]
		last := result.Items[len(result.Items)-1]
		key := map[string]any{"at": last.CreatedAt, "id": last.ID}
		if sort == "relevance_desc" {
			key["score"] = last.Score
		}
		if custom {
			key["value"] = invoiceSortValue(sort, last)
		}
		result.NextCursor, err = pagination.EncodeBounded("invoices", fingerprint, sort, key, invoiceCursorBytes)
	}
	return result, err
}
