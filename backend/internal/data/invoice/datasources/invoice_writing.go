package datasources

import (
	"context"
	"errors"
	"fmt"
	"strings"

	r "github.com/domabas/domabas/backend/internal/data/invoice/models"
	m "github.com/domabas/domabas/backend/internal/domain/invoice/models"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const upsertInvoice = `INSERT INTO invoices(
 id,account_id,document_id,generation,ocr_revision,source,format,number,type_code,issue_date,due_date,
 currency,tax_currency,total_net,total_tax,total_gross,amount_due,paid_amount,rounding_amount,tax_accounting_amount,
 profile,extraction_model,seller_name,seller_tax_id,seller_registration_id,seller_address,seller_country,seller_email,
 buyer_name,buyer_tax_id,buyer_registration_id,buyer_address,buyer_country,buyer_email,
 payment_means_code,payment_reference,payment_iban,payment_bic,payment_terms,source_xml,search_vector)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,NULLIF($10,'')::date,NULLIF($11,'')::date,
 $12,NULLIF($13,''),NULLIF($14,'')::numeric,NULLIF($15,'')::numeric,NULLIF($16,'')::numeric,
 NULLIF($17,'')::numeric,NULLIF($18,'')::numeric,NULLIF($19,'')::numeric,NULLIF($20,'')::numeric,
 $21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$40,to_tsvector('simple',$41))
 ON CONFLICT(account_id,document_id) DO UPDATE SET
 generation=EXCLUDED.generation,ocr_revision=EXCLUDED.ocr_revision,source=EXCLUDED.source,format=EXCLUDED.format,
 number=EXCLUDED.number,type_code=EXCLUDED.type_code,issue_date=EXCLUDED.issue_date,due_date=EXCLUDED.due_date,
 currency=EXCLUDED.currency,tax_currency=EXCLUDED.tax_currency,total_net=EXCLUDED.total_net,total_tax=EXCLUDED.total_tax,
 total_gross=EXCLUDED.total_gross,amount_due=EXCLUDED.amount_due,paid_amount=EXCLUDED.paid_amount,
 rounding_amount=EXCLUDED.rounding_amount,tax_accounting_amount=EXCLUDED.tax_accounting_amount,
 profile=EXCLUDED.profile,extraction_model=EXCLUDED.extraction_model,
 seller_name=EXCLUDED.seller_name,seller_tax_id=EXCLUDED.seller_tax_id,seller_registration_id=EXCLUDED.seller_registration_id,
 seller_address=EXCLUDED.seller_address,seller_country=EXCLUDED.seller_country,seller_email=EXCLUDED.seller_email,
 buyer_name=EXCLUDED.buyer_name,buyer_tax_id=EXCLUDED.buyer_tax_id,buyer_registration_id=EXCLUDED.buyer_registration_id,
 buyer_address=EXCLUDED.buyer_address,buyer_country=EXCLUDED.buyer_country,buyer_email=EXCLUDED.buyer_email,
 payment_means_code=EXCLUDED.payment_means_code,payment_reference=EXCLUDED.payment_reference,
 payment_iban=EXCLUDED.payment_iban,payment_bic=EXCLUDED.payment_bic,payment_terms=EXCLUDED.payment_terms,
 source_xml=EXCLUDED.source_xml,search_vector=EXCLUDED.search_vector,updated_at=clock_timestamp()
 WHERE invoices.source<>'structured' OR EXCLUDED.source='structured'
 RETURNING id`

func saveRecord(ctx context.Context, tx pgx.Tx, w m.InvoiceWork, v r.InvoiceRecord) error {
	var id string
	account := w.Job.AccountID
	err := tx.QueryRow(ctx, upsertInvoice,
		uuid.NewString(), account, w.Job.DocumentID, w.Job.Generation, w.Revision, v.Source, v.Format, v.Number, v.TypeCode, v.IssueDate, v.DueDate,
		v.Currency, v.TaxCurrency, v.TotalNet, v.TotalTax, v.TotalGross, v.AmountDue, v.PaidAmount, v.RoundingAmount, v.TaxAccountingAmount,
		v.Profile, v.ExtractionModel, v.Seller.Name, v.Seller.TaxID, v.Seller.RegistrationID, v.Seller.Address, v.Seller.Country, v.Seller.Email,
		v.Buyer.Name, v.Buyer.TaxID, v.Buyer.RegistrationID, v.Buyer.Address, v.Buyer.Country, v.Buyer.Email,
		v.Payment.MeansCode, v.Payment.Reference, v.Payment.IBAN, v.Payment.BIC, v.Payment.Terms, w.XML, invoiceSearchText(v)).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("save invoice header: %w", err)
	}
	batch := &pgx.Batch{}
	for _, table := range []string{"invoice_lines", "invoice_taxes", "invoice_allowances", "invoice_references", "invoice_notes"} {
		batch.Queue("DELETE FROM "+table+" WHERE account_id=$1 AND invoice_id=$2", account, id)
	}
	for position, line := range v.Lines {
		batch.Queue(`INSERT INTO invoice_lines(account_id,invoice_id,position,line_id,description,quantity,unit_code,unit_price,net_amount,tax_category,tax_rate) VALUES($1,$2,$3,$4,$5,NULLIF($6,'')::numeric,$7,NULLIF($8,'')::numeric,NULLIF($9,'')::numeric,$10,NULLIF($11,'')::numeric)`, account, id, position, line.ID, line.Description, line.Quantity, line.UnitCode, line.UnitPrice, line.NetAmount, line.TaxCategory, line.TaxRate)
	}
	for position, tax := range v.Taxes {
		batch.Queue(`INSERT INTO invoice_taxes(account_id,invoice_id,position,category,rate,taxable_amount,tax_amount,exemption_reason) VALUES($1,$2,$3,$4,NULLIF($5,'')::numeric,NULLIF($6,'')::numeric,NULLIF($7,'')::numeric,$8)`, account, id, position, tax.Category, tax.Rate, tax.TaxableAmount, tax.TaxAmount, tax.ExemptionReason)
	}
	for position, allowance := range v.Allowances {
		batch.Queue(`INSERT INTO invoice_allowances(account_id,invoice_id,position,charge,reason,amount,tax_category,tax_rate) VALUES($1,$2,$3,$4,$5,NULLIF($6,'')::numeric,$7,NULLIF($8,'')::numeric)`, account, id, position, allowance.Charge, allowance.Reason, allowance.Amount, allowance.TaxCategory, allowance.TaxRate)
	}
	for position, reference := range v.References {
		batch.Queue(`INSERT INTO invoice_references(account_id,invoice_id,position,number,issue_date) VALUES($1,$2,$3,$4,NULLIF($5,'')::date)`, account, id, position, reference.Number, reference.IssueDate)
	}
	for position, note := range v.Notes {
		batch.Queue(`INSERT INTO invoice_notes(account_id,invoice_id,position,content) VALUES($1,$2,$3,$4)`, account, id, position, note)
	}
	results := tx.SendBatch(ctx, batch)
	defer results.Close()
	for range batch.Len() {
		if _, err = results.Exec(); err != nil {
			return fmt.Errorf("replace invoice details: %w", err)
		}
	}
	return results.Close()
}

func invoiceSearchText(v r.InvoiceRecord) string {
	values := []string{v.Source, v.Format, v.Number, v.TypeCode, v.IssueDate, v.DueDate, v.Currency, v.TaxCurrency,
		v.TotalNet, v.TotalTax, v.TotalGross, v.AmountDue, v.PaidAmount, v.RoundingAmount, v.TaxAccountingAmount,
		v.Profile, v.ExtractionModel, v.Payment.MeansCode, v.Payment.Reference, v.Payment.IBAN, v.Payment.BIC, v.Payment.Terms}
	for _, party := range []r.InvoicePartyRecord{v.Seller, v.Buyer} {
		values = append(values, party.Name, party.TaxID, party.RegistrationID, party.Address, party.Country, party.Email)
	}
	for _, line := range v.Lines {
		values = append(values, line.ID, line.Description, line.Quantity, line.UnitCode, line.UnitPrice, line.NetAmount, line.TaxCategory, line.TaxRate)
	}
	for _, tax := range v.Taxes {
		values = append(values, tax.Category, tax.Rate, tax.TaxableAmount, tax.TaxAmount, tax.ExemptionReason)
	}
	for _, allowance := range v.Allowances {
		kind := "allowance"
		if allowance.Charge {
			kind = "charge"
		}
		values = append(values, kind, allowance.Reason, allowance.Amount, allowance.TaxCategory, allowance.TaxRate)
	}
	for _, reference := range v.References {
		values = append(values, reference.Number, reference.IssueDate)
	}
	values = append(values, v.Notes...)
	return strings.Join(values, " ")
}
