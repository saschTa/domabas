package models

import (
	"errors"
	"math"
	"strings"
	"testing"
)

func TestMetadataNormalizationAndPartialClearing(t *testing.T) {
	metadata, err := (DocumentMetadata{Title: " Invoice ", Tags: []string{" Work ", "MAIL"}, Recipients: []string{" Alice Example "}, DocumentDate: "2024-02-29", Kind: "letter"}).Normalize()
	if err != nil || metadata.Title != "Invoice" || metadata.Tags[0] != "mail" || metadata.Recipients[0] != "Alice Example" {
		t.Fatalf("normalization: %+v %v", metadata, err)
	}
	empty := ""
	tags := []string{}
	changed, err := (DocumentMetadataPatch{DocumentDate: &empty, Tags: &tags}).Apply(metadata)
	if err != nil || changed.DocumentDate != "" || len(changed.Tags) != 0 || changed.Title != metadata.Title || changed.Kind != "letter" {
		t.Fatalf("partial clear: %+v %v", changed, err)
	}
	for _, value := range []DocumentMetadata{{Title: "x", Tags: []string{"mail", "MAIL"}}, {Title: "x", DocumentDate: "2023-02-29"}, {Title: "x", Recipients: []string{"Alice", " Alice "}}, {Title: "x", Subject: "header\r\ninjection"}, {Title: "x", Kind: "arbitrary"}, {Title: strings.Repeat("x", 201)}, {Title: "x", Description: strings.Repeat("x", 4001)}} {
		if _, err := value.Normalize(); err == nil {
			t.Fatalf("invalid metadata accepted: %+v", value)
		}
	}
	if _, err = (DocumentMetadataPatch{}).Apply(metadata); err == nil {
		t.Fatal("empty patch accepted")
	}
	if _, err = (DocumentMetadataPatch{Title: &empty}).Apply(metadata); err == nil {
		t.Fatal("title cleared")
	}
}
func TestEmbeddingVectorsRejectMalformedAndNormalize(t *testing.T) {
	vector := make([]float64, EmbeddingDimensions)
	vector[0] = 3
	vector[1] = 4
	normalized, err := NormalizeVector(vector)
	if err != nil || math.Abs(normalized[0]-.6) > 1e-12 || math.Abs(normalized[1]-.8) > 1e-12 || vector[0] != 3 {
		t.Fatalf("normalization: %v %v", normalized, err)
	}
	cases := [][]float64{{1}, make([]float64, EmbeddingDimensions)}
	for _, bad := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		v := append([]float64{}, vector...)
		v[0] = bad
		cases = append(cases, v)
	}
	for _, bad := range cases {
		if _, err = NormalizeVector(bad); err == nil {
			t.Fatal("malformed vector accepted")
		}
	}
	var typed DocumentProcessingError
	if !errors.As(DocumentProcessingError{Code: "processing_failed"}, &typed) {
		t.Fatal("processing error is not typed")
	}
}
func TestOwnerConfigurationCannotChooseArbitraryEngine(t *testing.T) {
	for _, c := range []DocumentProcessingConfiguration{{Language: "eng", Segmentation: "auto"}, {Language: "deu", Segmentation: "single_block"}, {Language: "eng+deu", Segmentation: "auto"}} {
		if err := c.Validate(); err != nil {
			t.Fatal(err)
		}
	}
	for _, c := range []DocumentProcessingConfiguration{{Language: "fra", Segmentation: "auto"}, {Language: "eng", Segmentation: "--output"}} {
		if err := c.Validate(); err == nil {
			t.Fatal("unsupported processor option accepted")
		}
	}
}
