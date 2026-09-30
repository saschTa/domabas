//go:build e2e

package e2e_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/domabas/domabas/backend/internal/testdb"
	"github.com/domabas/domabas/backend/tests/fixtures"
	invoices "github.com/domabas/domabas/backend/tests/fixtures/invoices"
	"github.com/getkin/kin-openapi/openapi3"
)

func TestIssue29InvoiceIngestionSourcesCurrencyCorrectionsAndIsolation(t *testing.T) {
	databaseURL := testdb.New(t)
	env := newServerEnvironment(t, databaseURL)
	binary := filepath.Join(t.TempDir(), "server")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/server")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build %v %s", err, output)
	}
	spec, err := openapi3.NewLoader().LoadFromFile(filepath.Join("..", "..", "..", "contracts", "backend", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	base, stop := startServer(t, binary, databaseURL, env)
	defer func() { stop() }()
	api := &ingestionAPI{t: t, baseURL: base, client: &http.Client{Timeout: 15 * time.Second}, spec: spec}
	token := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Invoice tests","email":"invoice@example.test","password":"Invoice tests password 2026!"}`, 201, "AuthSession")["token"].(string)
	other := api.request("", "POST", "/api/v1/auth/register", `{"accountName":"Other invoice tests","email":"invoice-other@example.test","password":"Invoice tests password 2026!"}`, 201, "AuthSession")["token"].(string)
	api.request("", "GET", "/api/v1/invoices", "", 401, "Error")
	structuredXML := strings.ReplaceAll(string(invoices.CII), "119.00", "+00119.00")
	original := api.upload(token, "factur-x.pdf", invoices.PDF([]byte(structuredXML)), `{"title":"HiddenDocumentTitleOnly"}`, true, 202)
	docID := original["id"].(string)
	api.waitProcessing(token, docID, "ready")
	api.waitAI(token, docID, "succeeded")
	page := api.request(token, "GET", "/api/v1/invoices?limit=1", "", 200, "InvoicePage")
	items := page["items"].([]any)
	if len(items) != 1 {
		t.Fatal(page)
	}
	invoice := items[0].(map[string]any)
	id := invoice["id"].(string)
	if invoice["documentId"] != docID || invoice["source"] != "structured" || invoice["currency"] != "EUR" || invoice["totalGross"] != "119.00" || invoice["number"] != "INV-2026-001" {
		t.Fatal(invoice)
	}
	api.request(other, "GET", "/api/v1/invoices/"+id, "", 404, "Error")
	for _, query := range []string{"limit=0", "limit=51", "source=untrusted", "cursor=bad", "limit=1&limit=2", "cursor=", "extra=1", "q=Acme&q=Tokyo", "q=" + strings.Repeat("a", 201), "q=bad%00text", "sort=invalid", "seller=", "seller=a&seller=b", "dueFrom=2026-02-30", "createdFrom=2026-10-01&createdTo=2026-01-01", "totalMin=1", "currency=EUR&totalMin=2&totalMax=1"} {
		api.request(token, "GET", "/api/v1/invoices?"+query, "", 400, "Error")
	}
	for _, query := range []string{"INV-2026-001", "Printer paper", "EUR", "suppliez"} {
		matches := api.request(token, "GET", "/api/v1/invoices?q="+url.QueryEscape(query), "", 200, "InvoicePage")
		if len(matches["items"].([]any)) != 1 || matches["items"].([]any)[0].(map[string]any)["id"] != id {
			t.Fatalf("invoice search %q: %v", query, matches)
		}
	}
	for _, query := range []string{"HiddenDocumentTitleOnly", "NoSuchInvoiceProperty", "Acme -Printer"} {
		matches := api.request(token, "GET", "/api/v1/invoices?q="+url.QueryEscape(query), "", 200, "InvoicePage")
		if len(matches["items"].([]any)) != 0 {
			t.Fatalf("non-invoice content matched %q: %v", query, matches)
		}
	}

	api.request("", "GET", "/api/v1/invoices/filter-values?field=seller", "", 401, "Error")
	for _, query := range []string{"", "field=unknown", "field=seller&limit=51", "field=seller&field=buyer", "field=seller&extra=x", "field=seller&q=bad%00text", "field=seller&cursor="} {
		api.request(token, "GET", "/api/v1/invoices/filter-values?"+query, "", 400, "Error")
	}
	values := api.request(token, "GET", "/api/v1/invoices/filter-values?field=seller&q=ACME", "", 200, "InvoiceFilterValuePage")
	if len(values["items"].([]any)) != 1 {
		t.Fatal("invoice value search", values)
	}
	isolatedValues := api.request(other, "GET", "/api/v1/invoices/filter-values?field=seller", "", 200, "InvoiceFilterValuePage")
	if len(isolatedValues["items"].([]any)) != 0 {
		t.Fatal("cross-library filter values", isolatedValues)
	}
	for _, sort := range []string{"created_asc", "created_desc", "due_asc", "due_desc", "issue_asc", "issue_desc", "number_asc", "number_desc", "seller_asc", "seller_desc", "buyer_asc", "buyer_desc"} {
		path := "/api/v1/invoices?sort=" + sort + "&number=INV-2026-001&currency=EUR&totalMin=119&totalMax=119.00&seller=" + url.QueryEscape(invoice["seller"].(map[string]any)["name"].(string))
		matches := api.request(token, "GET", path, "", 200, "InvoicePage")
		if len(matches["items"].([]any)) != 1 || matches["items"].([]any)[0].(map[string]any)["id"] != id {
			t.Fatal("explicit filtered sort", sort, matches)
		}
	}
	empty := api.request(token, "GET", "/api/v1/invoices?currency=USD&totalMin=119", "", 200, "InvoicePage")
	if len(empty["items"].([]any)) != 0 {
		t.Fatal("currency filter", empty)
	}
	creditDoc := api.upload(token, "credit.pdf", invoices.PDF(invoices.UBLCredit), `{"title":"Structured credit note"}`, true, 202)
	api.waitProcessing(token, creditDoc["id"].(string), "ready")
	api.waitAI(token, creditDoc["id"].(string), "succeeded")
	page = api.request(token, "GET", "/api/v1/invoices?limit=1", "", 200, "InvoicePage")
	credit := page["items"].([]any)[0].(map[string]any)
	detail := api.request(token, "GET", "/api/v1/invoices/"+credit["id"].(string), "", 200, "Invoice")
	references := detail["references"].([]any)
	if detail["currency"] != "KWD" || detail["totalGross"] != "1.190" || detail["taxCurrency"] != "EUR" || detail["taxAccountingAmount"] != "0.55" || len(references) != 1 || references[0].(map[string]any)["invoiceId"] != id {
		t.Fatal(detail)
	}

	numbers := api.request(token, "GET", "/api/v1/invoices/filter-values?field=number&limit=1", "", 200, "InvoiceFilterValuePage")
	valueCursor := url.QueryEscape(numbers["nextCursor"].(string))
	remainingNumbers := api.request(token, "GET", "/api/v1/invoices/filter-values?field=number&limit=1&cursor="+valueCursor, "", 200, "InvoiceFilterValuePage")
	if numbers["items"].([]any)[0] == remainingNumbers["items"].([]any)[0] {
		t.Fatal("duplicate vocabulary continuation")
	}
	api.request(token, "GET", "/api/v1/invoices/filter-values?field=seller&cursor="+valueCursor, "", 400, "Error")
	api.request(other, "GET", "/api/v1/invoices/filter-values?field=number&cursor="+valueCursor, "", 400, "Error")
	sortedPage := api.request(token, "GET", "/api/v1/invoices?sort=number_asc&limit=1", "", 200, "InvoicePage")
	sortedCursor := url.QueryEscape(sortedPage["nextCursor"].(string))
	api.request(token, "GET", "/api/v1/invoices?sort=number_asc&limit=1&cursor="+sortedCursor, "", 200, "InvoicePage")
	api.request(token, "GET", "/api/v1/invoices?sort=number_desc&limit=1&cursor="+sortedCursor, "", 400, "Error")
	api.request(token, "GET", "/api/v1/invoices?sort=number_asc&currency=EUR&limit=1&cursor="+sortedCursor, "", 400, "Error")
	next := api.request(token, "GET", "/api/v1/invoices?limit=1&cursor="+page["nextCursor"].(string), "", 200, "InvoicePage")
	if next["items"].([]any)[0].(map[string]any)["id"] != id {
		t.Fatal(next)
	}
	search := api.request(token, "GET", "/api/v1/invoices?source=structured&q=Acme&limit=1", "", 200, "InvoicePage")
	searchCursor := url.QueryEscape(search["nextCursor"].(string))
	api.request(token, "GET", "/api/v1/invoices?source=structured&q=Acme&limit=1&cursor="+searchCursor, "", 200, "InvoicePage")
	api.request(token, "GET", "/api/v1/invoices?source=structured&q=Printer&limit=1&cursor="+searchCursor, "", 400, "Error")
	api.request(token, "GET", "/api/v1/invoices?source=ai&q=Acme&limit=1&cursor="+searchCursor, "", 400, "Error")
	isolated := api.request(other, "GET", "/api/v1/invoices?q=Acme", "", 200, "InvoicePage")
	if len(isolated["items"].([]any)) != 0 {
		t.Fatal("search exposed another library", isolated)
	}
	var inferenceCalls, propertyCalls atomic.Int32
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Messages    []struct{ Content string }
			Temperature float64
		}
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			w.WriteHeader(400)
			return
		}
		invoiceRequest := false
		classificationRequest := false
		nonInvoice := false
		valueFixture := false
		fabricatedTotal := false
		fabricatedDate := false
		for _, message := range body.Messages {
			classificationRequest = classificationRequest || strings.Contains(message.Content, `"required":["reason"]`)
			if strings.Contains(message.Content, "Meeting notes for the engineering team") || strings.Contains(message.Content, "Career profile.") || strings.Contains(message.Content, "General terms.") {
				nonInvoice = true
			}
			if strings.Contains(message.Content, `"required":["invoice"]`) {
				invoiceRequest = true
			}
			valueFixture = valueFixture || strings.Contains(message.Content, "SYN-VALUES-1")
			fabricatedTotal = fabricatedTotal || strings.Contains(message.Content, "Fabricated total fixture")
			fabricatedDate = fabricatedDate || strings.Contains(message.Content, "Fabricated date fixture")
		}
		content := `{"description":"Invoice summary\nPayment due in 14 days.","sender":"Example GmbH\nSample Street 1\n10115 Berlin","subject":"Extracted\tproperties","tags":[],"recipients":["Customer AG\r\nOther Street 2\n20095 Hamburg"],"documentDate":""}`
		if classificationRequest {
			if body.Temperature != 0.2 {
				t.Errorf("classification temperature: %v", body.Temperature)
			}
			content = `{"reason":"invoice"}`
			if nonInvoice {
				content = `{"reason":"other_document"}`
			}
		} else if invoiceRequest {
			if body.Temperature != 0.2 {
				t.Errorf("extraction temperature: %v", body.Temperature)
			}
			inferenceCalls.Add(1)
			content = `{"invoice":{"number":"AI-2026-001","typeCode":"380","currency":"JPY","seller":{"name":"Tokyo Supplies"},"totalNet":"","totalTax":"","totalGross":"1000","amountDue":"1000","issueDate":"2026-09-19","dueDate":"","vatAccounting":null}}`
			if valueFixture {
				content = `{"invoice":{"number":"SYN-VALUES-1","currency":"EUR","seller":{"name":"Synthetic Supplies"},"totalNet":"1000.00","totalTax":"190.00","totalGross":"1190.00","issueDate":"2026-09-16","dueDate":"","vatAccounting":null}}`
				if fabricatedTotal {
					content = strings.Replace(content, `"totalGross":"1190.00"`, `"totalGross":"1191.00"`, 1)
				}
				if fabricatedDate {
					content = strings.Replace(content, `"issueDate":"2026-09-16"`, `"issueDate":"2026-09-17"`, 1)
				}
			}
			if nonInvoice {
				t.Error("non-invoice reached extraction")
				content = `{"invoice":null}`
			}
		} else {
			propertyCalls.Add(1)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": map[string]string{"content": content}}}})
	}))
	defer provider.Close()
	configuration := api.request(token, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	body := fmt.Sprintf(`{"language":"eng+deu","segmentation":"auto","expectedRevision":%.0f,"llm":{"enabled":false,"invoiceEnabled":true,"provider":"openai","model":"invoice-fixture","baseUrl":%q}}`, configuration["revision"], provider.URL+"/v1")
	api.request(token, "PUT", "/api/v1/system/document-processing", body, 200, "DocumentProcessingConfiguration")
	pdf := api.upload(token, "plain-invoice.pdf", fixtures.PDF(t,
		fixtures.Page{Text: "Invoice No. AI-2026-001"},
		fixtures.Page{Text: "Seller: Tokyo Supplies 2026-09-19"},
		fixtures.Page{Text: "Grand Total: JPY 1000"},
		fixtures.Page{Text: "Amount due: JPY 1000"},
	), `{"title":"Ordinary PDF invoice"}`, true, 202)
	api.waitProcessing(token, pdf["id"].(string), "ready")
	api.waitAI(token, pdf["id"].(string), "succeeded")
	email := []byte("From: billing@example.test\r\nTo: buyer@example.test\r\nSubject: Invoice AI-2026-001\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nInvoice No. AI-2026-001\r\nSeller: Tokyo Supplies\r\n2026-09-19\r\nGrand Total: JPY 1000\r\nAmount due: JPY 1000\r\n")
	eml := api.upload(token, "invoice.eml", email, `{"title":"Email invoice","kind":"email"}`, true, 202)
	api.waitProcessing(token, eml["id"].(string), "ready")
	api.waitAI(token, eml["id"].(string), "succeeded")
	page = api.request(token, "GET", "/api/v1/invoices?source=ai", "", 200, "InvoicePage")
	if len(page["items"].([]any)) != 2 || inferenceCalls.Load() != 2 || propertyCalls.Load() != 0 {
		t.Fatalf("ordinary source detection %v calls %d", page, inferenceCalls.Load())
	}
	for _, item := range page["items"].([]any) {
		v := item.(map[string]any)
		if v["source"] != "ai" || v["extractionModel"] != "invoice-fixture" || v["currency"] != "JPY" || v["totalGross"] != "1000" {
			t.Fatal(v)
		}
	}
	page = api.request(token, "GET", "/api/v1/invoices?source=ai&q=JPY", "", 200, "InvoicePage")
	if len(page["items"].([]any)) != 2 {
		t.Fatal("AI currency search", page)
	}
	page = api.request(token, "GET", "/api/v1/invoices?source=structured&q=JPY", "", 200, "InvoicePage")
	if len(page["items"].([]any)) != 0 {
		t.Fatal("source filter did not constrain search", page)
	}
	notes := api.upload(token, "meeting-notes.pdf", fixtures.PDF(t, fixtures.Page{Text: "Meeting notes for the engineering team"}), `{"title":"Meeting notes"}`, true, 202)
	api.waitProcessing(token, notes["id"].(string), "ready")
	api.waitAI(token, notes["id"].(string), "succeeded")
	aiJobs := api.request(token, "GET", "/api/v1/document-jobs?pipeline=ai&documentId="+notes["id"].(string), "", 200, "DocumentJobPage")["items"].([]any)
	if len(aiJobs) != 1 || aiJobs[0].(map[string]any)["invoiceClassification"].(map[string]any)["decision"] != "not_invoice" || inferenceCalls.Load() != 2 {
		t.Fatalf("non-invoice classification was lost or extraction ran: %v", aiJobs)
	}
	noteJobs := api.request(token, "GET", "/api/v1/document-jobs?pipeline=ingestion&status=succeeded&documentId="+notes["id"].(string), "", 200, "DocumentJobPage")["items"].([]any)
	if len(noteJobs) != 1 || noteJobs[0].(map[string]any)["failureCode"] != nil {
		t.Fatalf("non-invoice did not complete normally: %v", noteJobs)
	}
	page = api.request(token, "GET", "/api/v1/invoices?source=ai", "", 200, "InvoicePage")
	if len(page["items"].([]any)) != 2 {
		t.Fatal("non-invoice created an invoice", page)
	}
	for _, scenario := range []struct{ filename, text string }{
		{"profile.pdf", "Career profile. Example Engineer. Experience: 2019-2026."},
		{"terms.pdf", "General terms. Invoices follow delivery. Storage fee: 0.25%."},
	} {
		doc := api.upload(token, scenario.filename, fixtures.PDF(t, fixtures.Page{Text: scenario.text}), `{"title":"Source evidence regression"}`, true, 202)
		documentID := doc["id"].(string)
		api.waitProcessing(token, documentID, "ready")
		api.waitAI(token, documentID, "succeeded")
		api.assertMatch(token, "Source evidence regression", documentID)
		page = api.request(token, "GET", "/api/v1/invoices?source=ai", "", 200, "InvoicePage")
		if len(page["items"].([]any)) != 2 {
			t.Fatal("unsupported positive model decision created an invoice", scenario.filename, page)
		}
	}
	if inferenceCalls.Load() != 2 {
		t.Fatal("non-invoices reached expensive invoice extraction", inferenceCalls.Load())
	}
	for _, scenario := range []struct {
		name, text string
		accepted   bool
	}{
		{"unlisted-labels", "Rechnungs-Nr. SYN-VALUES-1 / 16.09.2026\nSynthetic Supplies\nNetto-Summe: 1.000,00 EUR\nMehrwertsteuer: 190,00 EUR\nRechnungsendbetrag in EUR 1.190,00", true},
		{"unlabelled-values", "SYN-VALUES-1\nSynthetic Supplies\n2026-09-16\nEUR\n1,000.00\n190.00\n1,190.00", true},
		{"invented-total", "Fabricated total fixture\nSYN-VALUES-1\nSynthetic Supplies\n16.09.2026\nEUR 1000,00 190,00 1190,00", false},
		{"invented-date", "Fabricated date fixture\nSYN-VALUES-1\nSynthetic Supplies\n16.09.2026\nEUR 1000,00 190,00 1190,00", false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			valueAPI := *api
			valueAPI.t = t
			var pages []fixtures.Page
			for _, line := range strings.Split(scenario.text, "\n") {
				pages = append(pages, fixtures.Page{Text: line})
			}
			doc := valueAPI.upload(token, scenario.name+".pdf", fixtures.PDF(t, pages...), `{"title":"Numeric invoice evidence"}`, true, 202)
			documentID := doc["id"].(string)
			valueAPI.waitProcessing(token, documentID, "ready")
			status := "failed"
			if scenario.accepted {
				status = "succeeded"
			}
			job := valueAPI.waitAI(token, documentID, status)
			if !scenario.accepted && job["failureCode"] != "invalid_invoice" {
				t.Fatal("missing values did not fail extraction", job)
			}
			jobs := valueAPI.request(token, "GET", "/api/v1/document-jobs?pipeline=ai&documentId="+documentID, "", 200, "DocumentJobPage")["items"].([]any)
			if len(jobs) != 1 || jobs[0].(map[string]any)["invoiceClassification"].(map[string]any)["decision"] != "invoice" {
				t.Fatal("source validation changed classification", jobs)
			}
			matches := valueAPI.request(token, "GET", "/api/v1/invoices?source=ai&q=SYN-VALUES-1", "", 200, "InvoicePage")["items"].([]any)
			found := false
			for _, item := range matches {
				value := item.(map[string]any)
				if value["documentId"] != documentID {
					continue
				}
				found = true
				detail := valueAPI.request(token, "GET", "/api/v1/invoices/"+value["id"].(string), "", 200, "Invoice")
				if detail["totalGross"] != "1190.00" || detail["issueDate"] != "2026-09-16" || detail["totalNet"] != "1000.00" || detail["totalTax"] != "190.00" {
					t.Fatal("normalized values changed during persistence", detail)
				}
			}
			if found != scenario.accepted {
				t.Fatalf("published=%t, expected=%t", found, scenario.accepted)
			}
		})
	}
	invoiceCallsBeforeProperties := inferenceCalls.Load()
	if invoiceCallsBeforeProperties != 6 {
		t.Fatal("numeric evidence fixtures skipped extraction", invoiceCallsBeforeProperties)
	}
	broken := api.upload(token, "broken-invoice.pdf", invoices.PDF([]byte(`<CrossIndustryInvoice xmlns="wrong"/>`)), `{"title":"Malformed invoice"}`, true, 202)
	api.waitProcessing(token, broken["id"].(string), "ready")
	failed := api.waitAI(token, broken["id"].(string), "failed")
	if failed["failureCode"] != "invalid_invoice" {
		t.Fatal(failed)
	}
	stop()
	base, stop = startServer(t, binary, databaseURL, env)
	api.baseURL = base
	retained := api.request(token, "GET", "/api/v1/invoices/"+id, "", 200, "Invoice")
	if retained["totalGross"] != "119.00" {
		t.Fatal("lost invoice on restart", retained)
	}
	configuration = api.request(token, "GET", "/api/v1/system/document-processing", "", 200, "DocumentProcessingConfiguration")
	if llm := configuration["llm"].(map[string]any); llm["enabled"] != false || llm["invoiceEnabled"] != true {
		t.Fatal("restart lost independent settings", llm)
	}
	body = fmt.Sprintf(`{"language":"eng+deu","segmentation":"auto","expectedRevision":%.0f,"llm":{"enabled":true,"invoiceEnabled":false,"provider":"openai","model":"invoice-fixture","baseUrl":%q}}`, configuration["revision"], provider.URL+"/v1")
	api.request(token, "PUT", "/api/v1/system/document-processing", body, 200, "DocumentProcessingConfiguration")
	propertyDocument := api.upload(token, "property-only.pdf", fixtures.PDF(t, fixtures.Page{Text: "Invoice PROPERTY-ONLY Tokyo Supplies JPY 500"}), `{"title":"Property-only extraction"}`, true, 202)
	propertyID := propertyDocument["id"].(string)
	api.waitProcessing(token, propertyID, "ready")
	api.waitAI(token, propertyID, "succeeded")
	propertyDocument = api.request(token, "GET", "/api/v1/documents/"+propertyID, "", 200, "Document")
	if propertyDocument["subject"] != "Extracted properties" || inferenceCalls.Load() != invoiceCallsBeforeProperties || propertyCalls.Load() == 0 {
		t.Fatal("property-only processing invoked invoice AI or omitted properties", propertyDocument)
	}
	jobs := api.request(token, "GET", "/api/v1/document-jobs?pipeline=ai&documentId="+propertyID, "", 200, "DocumentJobPage")
	jobConfiguration := jobs["items"].([]any)[0].(map[string]any)["configuration"].(map[string]any)
	if jobConfiguration["propertyExtractionEnabled"] != true || jobConfiguration["invoiceExtractionEnabled"] != false {
		t.Fatal("job lost independently configured steps", jobConfiguration)
	}
	addressXML := strings.ReplaceAll(string(invoices.CII), "INV-2026-001", "ADDRESS-2026-001")
	addressDocument := api.upload(token, "postal-address-invoice.pdf", invoices.PDF([]byte(addressXML)), `{"title":"Invoice with postal addresses"}`, true, 202)
	addressID := addressDocument["id"].(string)
	api.waitProcessing(token, addressID, "ready")
	api.waitAI(token, addressID, "succeeded")
	addressDocument = api.request(token, "GET", "/api/v1/documents/"+addressID, "", 200, "Document")
	addressRecipients := addressDocument["recipients"].([]any)
	if addressDocument["sender"] != "Example GmbH Sample Street 1 10115 Berlin" || len(addressRecipients) != 1 || addressRecipients[0] != "Customer AG Other Street 2 20095 Hamburg" || addressDocument["description"] != "Invoice summary\nPayment due in 14 days." {
		t.Fatal("postal address properties were not saved correctly", addressDocument)
	}
	addressInvoices := api.request(token, "GET", "/api/v1/invoices?source=structured&q=ADDRESS-2026-001", "", 200, "InvoicePage")["items"].([]any)
	if len(addressInvoices) != 1 {
		t.Fatal("missing structured invoice after property extraction", addressInvoices)
	}
	addressInvoice := addressInvoices[0].(map[string]any)
	if addressInvoice["documentId"] != addressID || addressInvoice["source"] != "structured" || addressInvoice["totalGross"] != "119.00" || inferenceCalls.Load() != invoiceCallsBeforeProperties {
		t.Fatal("property extraction changed the structured invoice", addressInvoice)
	}
	api.request(token, "DELETE", "/api/v1/documents/"+docID, "", 204, "")
	api.request(token, "GET", "/api/v1/invoices/"+id, "", 404, "Error")
}
