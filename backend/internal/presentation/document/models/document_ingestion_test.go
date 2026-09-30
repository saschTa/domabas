package models

import (
	"strings"
	"testing"
)

func TestStrictDocumentObjectsRejectNullDuplicateUnknownAndWrongTypes(t *testing.T) {
	tests := map[string][]string{
		"upload":        {`null`, `[]`, `{}`, `{"title":null}`, `{"title":1}`, `{"title":"x","title":"y"}`, `{"title":"x","accountId":"foreign"}`, `{"title":"x","tags":null}`, `{"title":"x","tags":"mail"}`, `{"title":"x","tags":[null]}`, `{"title":"x","tags":[1]}`, `{"title":"x"} {}`, `{"title":"x","sender":{}}`},
		"update":        {`{}`, `{"description":null}`, `{"title":"x","title":"x"}`, `{"generation":2}`, `{"recipients":[null]}`},
		"search":        {`{"query":"x"}`, `{"query":"x","mode":"fulltext","limit":1.5}`, `{"query":"x","mode":"fulltext","offset":"1"}`, `{"query":"x","mode":"fulltext","tags":[false]}`, `{"query":"x","mode":"fulltext","query":"y"}`},
		"configuration": {`{"language":"eng"}`, `{"language":"eng","segmentation":null}`, `{"language":"eng","segmentation":"auto","engine":"arbitrary"}`, `{"language":"eng","segmentation":"auto","language":"deu"}`},
	}
	for operation, bodies := range tests {
		for _, body := range bodies {
			t.Run(operation+"/"+body, func(t *testing.T) {
				if err := ValidateObject([]byte(body), operation); err == nil {
					t.Fatalf("accepted invalid object %s", body)
				}
			})
		}
	}
	if err := ValidateObject(append([]byte(`{"title":"`), 0xff, '"', '}'), "upload"); err == nil {
		t.Fatal("invalid UTF8 accepted")
	}
}
func TestStrictDocumentObjectsPreserveEmptyClearsAndMetadataNormalization(t *testing.T) {
	for operation, body := range map[string]string{"upload": `{"title":"Mail","tags":[]}`, "update": `{"description":"","documentDate":"","recipients":[]}`, "search": `{"query":"letter","mode":"fulltext","limit":20,"offset":0}`, "configuration": `{"language":"eng+deu","segmentation":"auto"}`} {
		if err := ValidateObject([]byte(body), operation); err != nil {
			t.Fatalf("%s: %v", operation, err)
		}
	}
	metadata, err := DecodeMetadata([]byte(`{"title":" Invoice ","kind":"letter","tags":[" Work ","MAIL"],"recipients":[" A. Example "]}`))
	if err != nil || metadata.Title != "Invoice" || strings.Join(metadata.Tags, ",") != "mail,work" || metadata.Recipients[0] != "A. Example" {
		t.Fatalf("invalid metadata mapping: %+v %v", metadata, err)
	}
	for _, body := range []string{`{"title":"  "}`, `{"title":"x","tags":["MAIL","mail"]}`, `{"title":"x","documentDate":"2023-02-29"}`, `{"title":"x","sender":"a\r\nb"}`} {
		if _, err := DecodeMetadata([]byte(body)); err == nil {
			t.Fatalf("invalid metadata accepted: %s", body)
		}
	}
}

func TestInvoiceExtractionSwitchUsesStrictBooleanValidation(t *testing.T) {
	for _, field := range []string{"", `,"invoiceEnabled":true`, `,"invoiceEnabled":false`} {
		body := `{"language":"eng+deu","segmentation":"auto","llm":{"enabled":false,"provider":"ollama","model":"qwen3.5:4b","baseUrl":""` + field + `}}`
		if err := ValidateObject([]byte(body), "configuration"); err != nil {
			t.Fatalf("valid independent invoice switch rejected: %v", err)
		}
	}
	for _, field := range []string{`"invoiceEnabled":null`, `"invoiceEnabled":"true"`, `"invoiceEnabled":true,"invoiceEnabled":false`} {
		body := `{"enabled":false,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"",` + field + `}`
		if err := ValidateObject([]byte(body), "llm"); err == nil {
			t.Fatal("invalid invoice switch accepted")
		}
	}
}

func TestLMStudioCompatibilityUsesStrictBooleanValidation(t *testing.T) {
	for _, field := range []string{"", `,"lmStudioCompatibility":true`, `,"lmStudioCompatibility":false`} {
		body := `{"language":"eng+deu","segmentation":"auto","llm":{"enabled":false,"provider":"openai","model":"fixture","baseUrl":"http://model.test/v1"` + field + `}}`
		if err := ValidateObject([]byte(body), "configuration"); err != nil {
			t.Fatalf("valid compatibility preference rejected: %v", err)
		}
	}
	for _, field := range []string{`"lmStudioCompatibility":null`, `"lmStudioCompatibility":"true"`, `"lmStudioCompatibility":1`, `"lmStudioCompatibility":true,"lmStudioCompatibility":false`} {
		body := `{"enabled":false,"provider":"openai","model":"fixture","baseUrl":"http://model.test/v1",` + field + `}`
		if err := ValidateObject([]byte(body), "llm"); err == nil {
			t.Fatal("invalid compatibility preference accepted")
		}
	}
}

func TestOCRJSONPreservesExactUnicodeAndRejectsReplacementDecoding(t *testing.T) {
	input, err := DecodeOCR([]byte(`{"revision":3,"text":"\r\n  \uD83D\uDE80\t\uFFFD"}`))
	if err != nil || input.Revision != 3 || input.Text != "\r\n  🚀\t�" {
		t.Fatalf("exact text did not survive JSON: %+v %v", input, err)
	}
	for _, body := range []string{
		`{"revision":0,"text":"\uD800"}`,
		`{"revision":0,"text":"\uDC00"}`,
		`{"revision":0,"text":"\uD800\u0041"}`,
		`{"revision":0,"text":"\u0000"}`,
		`{"revision":0,"text":"first","text":"second"}`,
		`{"revision":0,"text":null}`,
		`{"revision":null,"text":"text"}`,
		`{"revision":-1,"text":"text"}`,
		`{"revision":1.0,"text":"text"}`,
		`{"revision":9223372036854775808,"text":"text"}`,
		`{"revision":0,"text":"text","extra":true}`,
		`{"revision":0,"text":"text"} {}`,
	} {
		if _, err := DecodeOCR([]byte(body)); err == nil {
			t.Fatalf("invalid correction accepted: %s", body)
		}
	}
	if _, err := DecodeOCR([]byte{'{', '"', 'r', 'e', 'v', 'i', 's', 'i', 'o', 'n', '"', ':', '0', ',', '"', 't', 'e', 'x', 't', '"', ':', '"', 0xff, '"', '}'}); err == nil {
		t.Fatal("invalid UTF-8 accepted")
	}
}

func TestThinkingSettingsRequireUnambiguousBooleans(t *testing.T) {
	for _, name := range []string{"propertyThinkingEnabled", "invoiceThinkingEnabled"} {
		for _, value := range []string{"true", "false", "null", `"true"`, "1", "true,\"" + name + "\":false"} {
			body := `{"enabled":false,"provider":"ollama","model":"fixture","baseUrl":"","` + name + `":` + value + `}`
			err := ValidateObject([]byte(body), "llm")
			if (err == nil) != (value == "true" || value == "false") {
				t.Fatalf("invalid thinking validation %s: %v", body, err)
			}
		}
	}
}
