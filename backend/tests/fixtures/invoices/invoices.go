package invoices

import (
	"bytes"
	"compress/zlib"
	_ "embed"
	"fmt"
)

//go:embed cii.xml
var CII []byte

//go:embed ubl-credit.xml
var UBLCredit []byte

func PDF(xml []byte) []byte {
	var compressed bytes.Buffer
	z := zlib.NewWriter(&compressed)
	_, _ = z.Write(xml)
	_ = z.Close()
	text := "BT /F1 18 Tf 30 700 Td (Invoice INV-2026-001 Acme Supplies EUR 119.00) Tj ET"
	objects := [][]byte{
		[]byte("<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [(factur-x.xml) 6 0 R] >> >> /AF [6 0 R] >>"),
		[]byte("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
		[]byte("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"),
		[]byte("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"),
		[]byte(fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(text), text)),
		[]byte("<< /Type /Filespec /F (factur-x.xml) /UF (factur-x.xml) /AFRelationship /Alternative /EF << /F 7 0 R >> >>"),
		append(append([]byte(fmt.Sprintf("<< /Type /EmbeddedFile /Subtype /text#2Fxml /Filter /FlateDecode /Length %d >>\nstream\n", compressed.Len())), compressed.Bytes()...), []byte("\nendstream")...),
	}
	var out bytes.Buffer
	out.WriteString("%PDF-1.7\n")
	offsets := []int{0}
	for i, obj := range objects {
		offsets = append(offsets, out.Len())
		fmt.Fprintf(&out, "%d 0 obj\n", i+1)
		out.Write(obj)
		out.WriteString("\nendobj\n")
	}
	xref := out.Len()
	fmt.Fprintf(&out, "xref\n0 %d\n0000000000 65535 f \n", len(offsets))
	for _, offset := range offsets[1:] {
		fmt.Fprintf(&out, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF", len(offsets), xref)
	return out.Bytes()
}
