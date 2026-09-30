package datasources

import (
	"context"
	"errors"

	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	document "github.com/domabas/domabas/backend/internal/domain/document/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/jackc/pgx/v5"
)

const invoiceColumns = `i.id,i.document_id,d.title,i.created_at,i.source,i.format,i.number,i.type_code,
 COALESCE(i.issue_date::text,''),COALESCE(i.due_date::text,''),i.currency,COALESCE(i.tax_currency,''),
 COALESCE(i.total_net::text,''),COALESCE(i.total_tax::text,''),COALESCE(i.total_gross::text,''),
 COALESCE(i.amount_due::text,''),COALESCE(i.paid_amount::text,''),COALESCE(i.rounding_amount::text,''),COALESCE(i.tax_accounting_amount::text,''),
 i.profile,i.extraction_model,
 i.seller_name,i.seller_tax_id,i.seller_registration_id,i.seller_address,i.seller_country,i.seller_email,
 i.buyer_name,i.buyer_tax_id,i.buyer_registration_id,i.buyer_address,i.buyer_country,i.buyer_email,
 i.payment_means_code,i.payment_reference,i.payment_iban,i.payment_bic,i.payment_terms`

func scanInvoice(row pgx.Row, v *r.InvoiceRecord) error {
	return row.Scan(&v.ID, &v.DocumentID, &v.DocumentTitle, &v.CreatedAt, &v.Source, &v.Format, &v.Number, &v.TypeCode,
		&v.IssueDate, &v.DueDate, &v.Currency, &v.TaxCurrency,
		&v.TotalNet, &v.TotalTax, &v.TotalGross, &v.AmountDue, &v.PaidAmount, &v.RoundingAmount, &v.TaxAccountingAmount,
		&v.Profile, &v.ExtractionModel,
		&v.Seller.Name, &v.Seller.TaxID, &v.Seller.RegistrationID, &v.Seller.Address, &v.Seller.Country, &v.Seller.Email,
		&v.Buyer.Name, &v.Buyer.TaxID, &v.Buyer.RegistrationID, &v.Buyer.Address, &v.Buyer.Country, &v.Buyer.Email,
		&v.Payment.MeansCode, &v.Payment.Reference, &v.Payment.IBAN, &v.Payment.BIC, &v.Payment.Terms, &v.Score)
}

func (s *InvoiceDataSource) Get(ctx context.Context, a document.DocumentActor, id string) (r.InvoiceRecord, error) {
	var result r.InvoiceRecord
	err := s.readTx(ctx, a, func(tx pgx.Tx) error {
		if err := scanInvoice(tx.QueryRow(ctx, `SELECT `+invoiceColumns+`,0::float8 FROM invoices i JOIN documents d ON d.account_id=i.account_id AND d.id=i.document_id WHERE i.account_id=$1 AND i.id=$2`, a.AccountID, id), &result); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return m.ErrNotFound
			}
			return err
		}
		if err := readChildren(ctx, tx, a.AccountID, []*r.InvoiceRecord{&result}); err != nil {
			return err
		}
		for index, ref := range result.References {
			rows, err := tx.Query(ctx, `SELECT id,document_id FROM invoices WHERE account_id=$1 AND number=$2 AND id<>$3 AND ($4='' OR issue_date=NULLIF($4,'')::date) AND (($5<>'' AND seller_tax_id=$5) OR ($5='' AND $6<>'' AND seller_registration_id=$6)) ORDER BY id LIMIT 2`, a.AccountID, ref.Number, id, ref.IssueDate, result.Seller.TaxID, result.Seller.RegistrationID)
			if err != nil {
				return err
			}
			count := 0
			var invoiceID, documentID string
			for rows.Next() {
				count++
				if err = rows.Scan(&invoiceID, &documentID); err != nil {
					rows.Close()
					return err
				}
			}
			err = rows.Err()
			rows.Close()
			if err != nil {
				return err
			}
			if count == 1 {
				result.References[index].InvoiceID = invoiceID
				result.References[index].DocumentID = documentID
			}
		}
		return nil
	})
	return result, err
}

func readChildren(ctx context.Context, tx pgx.Tx, account string, invoices []*r.InvoiceRecord) error {
	if len(invoices) == 0 {
		return nil
	}
	ids := make([]string, 0, len(invoices))
	byID := make(map[string]*r.InvoiceRecord, len(invoices))
	for _, invoice := range invoices {
		ids = append(ids, invoice.ID)
		byID[invoice.ID] = invoice
	}
	rows, err := tx.Query(ctx, `SELECT invoice_id,line_id,description,COALESCE(quantity::text,''),unit_code,COALESCE(unit_price::text,''),COALESCE(net_amount::text,''),tax_category,COALESCE(tax_rate::text,'') FROM invoice_lines WHERE account_id=$1 AND invoice_id=ANY($2::uuid[]) ORDER BY invoice_id,position`, account, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var line r.InvoiceLineRecord
		if err = rows.Scan(&id, &line.ID, &line.Description, &line.Quantity, &line.UnitCode, &line.UnitPrice, &line.NetAmount, &line.TaxCategory, &line.TaxRate); err != nil {
			rows.Close()
			return err
		}
		byID[id].Lines = append(byID[id].Lines, line)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT invoice_id,category,COALESCE(rate::text,''),COALESCE(taxable_amount::text,''),COALESCE(tax_amount::text,''),exemption_reason FROM invoice_taxes WHERE account_id=$1 AND invoice_id=ANY($2::uuid[]) ORDER BY invoice_id,position`, account, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var tax r.InvoiceTaxRecord
		if err = rows.Scan(&id, &tax.Category, &tax.Rate, &tax.TaxableAmount, &tax.TaxAmount, &tax.ExemptionReason); err != nil {
			rows.Close()
			return err
		}
		byID[id].Taxes = append(byID[id].Taxes, tax)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT invoice_id,charge,reason,COALESCE(amount::text,''),tax_category,COALESCE(tax_rate::text,'') FROM invoice_allowances WHERE account_id=$1 AND invoice_id=ANY($2::uuid[]) ORDER BY invoice_id,position`, account, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var allowance r.InvoiceAllowanceRecord
		if err = rows.Scan(&id, &allowance.Charge, &allowance.Reason, &allowance.Amount, &allowance.TaxCategory, &allowance.TaxRate); err != nil {
			rows.Close()
			return err
		}
		byID[id].Allowances = append(byID[id].Allowances, allowance)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT invoice_id,number,COALESCE(issue_date::text,'') FROM invoice_references WHERE account_id=$1 AND invoice_id=ANY($2::uuid[]) ORDER BY invoice_id,position`, account, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		var reference r.InvoiceReferenceRecord
		if err = rows.Scan(&id, &reference.Number, &reference.IssueDate); err != nil {
			rows.Close()
			return err
		}
		byID[id].References = append(byID[id].References, reference)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT invoice_id,content FROM invoice_notes WHERE account_id=$1 AND invoice_id=ANY($2::uuid[]) ORDER BY invoice_id,position`, account, ids)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id, note string
		if err = rows.Scan(&id, &note); err != nil {
			rows.Close()
			return err
		}
		byID[id].Notes = append(byID[id].Notes, note)
	}
	err = rows.Err()
	rows.Close()
	return err
}
