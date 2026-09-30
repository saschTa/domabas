package processor

import (
	"bytes"
	"encoding/xml"
	"io"
	"strings"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"github.com/klippa-app/go-pdfium"
	"github.com/klippa-app/go-pdfium/references"
	"github.com/klippa-app/go-pdfium/requests"
)

func pdfInvoiceXML(instance pdfium.Pdfium, document references.FPDF_DOCUMENT) ([]byte, error) {
	count, err := instance.FPDFDoc_GetAttachmentCount(&requests.FPDFDoc_GetAttachmentCount{Document: document})
	if err != nil {
		return nil, pdfError(err)
	}
	if count.AttachmentCount > 32 {
		return nil, records.DocumentProcessorError{Code: "invalid_invoice"}
	}
	var result []byte
	for i := 0; i < count.AttachmentCount; i++ {
		attachment, err := instance.FPDFDoc_GetAttachment(&requests.FPDFDoc_GetAttachment{Document: document, Index: i})
		if err != nil {
			return nil, pdfError(err)
		}
		name, err := instance.FPDFAttachment_GetName(&requests.FPDFAttachment_GetName{Attachment: attachment.Attachment})
		if err != nil {
			return nil, pdfError(err)
		}
		filename := strings.ToLower(name.Name)
		if !strings.HasSuffix(filename, ".xml") {
			continue
		}
		file, err := instance.FPDFAttachment_GetFile(&requests.FPDFAttachment_GetFile{Attachment: attachment.Attachment})
		if err != nil {
			return nil, pdfError(err)
		}
		if len(file.Contents) > 2<<20 {
			return nil, records.DocumentProcessorError{Code: "invalid_invoice"}
		}
		recognized := filename == "factur-x.xml" || filename == "zugferd-invoice.xml" || filename == "xrechnung.xml"
		decoder := xml.NewDecoder(bytes.NewReader(file.Contents))
		for {
			token, err := decoder.Token()
			if err != nil {
				if err != io.EOF && recognized {
					return nil, records.DocumentProcessorError{Code: "invalid_invoice"}
				}
				break
			}
			if start, ok := token.(xml.StartElement); ok {
				switch start.Name.Local {
				case "CrossIndustryInvoice", "CrossIndustryDocument", "Invoice", "CreditNote":
					recognized = true
				}
				break
			}
		}
		if !recognized {
			continue
		}
		if result != nil {
			return nil, records.DocumentProcessorError{Code: "invalid_invoice"}
		}
		result = file.Contents
	}
	return result, nil
}
