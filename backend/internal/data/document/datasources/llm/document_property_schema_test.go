package llm

import (
	"encoding/json"
	"reflect"
	"testing"

	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/santhosh-tekuri/jsonschema/v6"
)

func TestPropertySchemaAndAdaptersDistinguishNullFromMissing(t *testing.T) {
	var definition any
	if err := json.Unmarshal([]byte(propertySchema), &definition); err != nil {
		t.Fatal(err)
	}
	compiler := jsonschema.NewCompiler()
	const location = "https://domabas.invalid/property-test.schema.json"
	if err := compiler.AddResource(location, definition); err != nil {
		t.Fatal(err)
	}
	schema, err := compiler.Compile(location)
	if err != nil {
		t.Fatal(err)
	}
	fields := []string{"description", "tags", "sender", "recipients", "documentDate", "subject"}
	for _, provider := range []string{"ollama", "openai"} {
		t.Run(provider, func(t *testing.T) {
			for _, omitted := range append([]string{"none"}, fields...) {
				t.Run(omitted, func(t *testing.T) {
					payload := map[string]any{}
					for _, field := range fields {
						if field != omitted {
							payload[field] = nil
						}
					}
					valid := omitted == "none"
					if (schema.Validate(payload) == nil) != valid {
						t.Fatal("schema confused an explicit null with an omitted key")
					}
					data, err := json.Marshal(payload)
					if err != nil {
						t.Fatal(err)
					}
					server := propertyResponseServer(t, provider, string(data))
					defer server.Close()
					remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
					if err != nil {
						t.Fatal(err)
					}
					defer remote.Close()
					got, err := remote.Extract(t.Context(), provider, "model", server.URL, "", "Unreadable document fragment", true, false)
					if (err == nil) != valid {
						t.Fatal("adapter confused an explicit null with an omitted key", err)
					}
					if valid {
						values := m.DocumentMetadata{Title: "extracted properties", Description: got.Description, Tags: got.Tags, Sender: got.Sender, Recipients: got.Recipients, DocumentDate: got.DocumentDate, Subject: got.Subject}
						values, err = values.Normalize()
						if err != nil {
							t.Fatal("null must map to valid empty metadata", err)
						}
						for _, existing := range []m.DocumentMetadata{{Title: "Document"}, {Title: "Document", Description: "User summary", Tags: []string{"user"}, Sender: "User sender", Recipients: []string{"User recipient"}, DocumentDate: "2026-09-19", Subject: "User subject"}} {
							if merged := existing.FillExtractedProperties(values); !reflect.DeepEqual(merged, existing) {
								t.Fatalf("unknown properties changed metadata: %+v", merged)
							}
						}
					}
				})
			}
		})
	}
}

func TestPropertyNullsPreserveKnownValuesAndRejectWrongTypes(t *testing.T) {
	for _, provider := range []string{"ollama", "openai"} {
		t.Run(provider, func(t *testing.T) {
			for _, scenario := range []struct {
				name, content string
				valid         bool
			}{
				{"mixed", `{"description":null,"tags":["invoice"],"sender":"Supplier","recipients":null,"documentDate":null,"subject":null}`, true},
				{"null replaces duplicate scalar", `{"description":"discarded value","description":null,"tags":["invoice"],"sender":"Supplier","recipients":null,"documentDate":null,"subject":null}`, true},
				{"numeric scalar", `{"description":null,"tags":null,"sender":42,"recipients":null,"documentDate":null,"subject":null}`, false},
				{"scalar list", `{"description":null,"tags":"invoice","sender":null,"recipients":null,"documentDate":null,"subject":null}`, false},
				{"wrong list member", `{"description":null,"tags":null,"sender":null,"recipients":[42],"documentDate":null,"subject":null}`, false},
				{"extra field", `{"description":null,"tags":null,"sender":null,"recipients":null,"documentDate":null,"subject":null,"title":"invented"}`, false},
				{"trailing JSON", `{"description":null,"tags":null,"sender":null,"recipients":null,"documentDate":null,"subject":null} {}`, false},
			} {
				t.Run(scenario.name, func(t *testing.T) {
					server := propertyResponseServer(t, provider, scenario.content)
					defer server.Close()
					remote, err := NewDocumentPropertyRemoteDataSource(server.URL)
					if err != nil {
						t.Fatal(err)
					}
					defer remote.Close()
					got, err := remote.Extract(t.Context(), provider, "model", server.URL, "", "Invoice from Supplier", false, false)
					if (err == nil) != scenario.valid {
						t.Fatal("incorrect response acceptance", err)
					}
					if scenario.valid && (got.Description != "" || got.Sender != "Supplier" || !reflect.DeepEqual(got.Tags, []string{"invoice"}) || len(got.Recipients) != 0 || got.DocumentDate != "" || got.Subject != "") {
						t.Fatalf("known values changed or nulls were invented: %+v", got)
					}
				})
			}
		})
	}
}
