package processor

import (
	"context"
	"errors"
	"io"
	"math"
	"strings"
	"unicode/utf8"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/klippa-app/go-pdfium"
	"github.com/klippa-app/go-pdfium/enums"
	pdferrors "github.com/klippa-app/go-pdfium/errors"
	"github.com/klippa-app/go-pdfium/references"
	"github.com/klippa-app/go-pdfium/requests"
	"github.com/klippa-app/go-pdfium/webassembly"
	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/experimental"
)

const maxPDFObjects = 20_000

func validPDFPageSize(width, height float64) bool {
	return width > 0 && height > 0 && !math.IsNaN(width) && !math.IsNaN(height) && !math.IsInf(width, 0) && !math.IsInf(height, 0)
}

func pdfRenderDPI(width, height float64) (int, error) {
	if validPDFPageSize(width, height) {
		for dpi := 200; dpi >= 1; dpi-- {
			scale := float64(dpi) / 72
			pixelsWide := math.Ceil(width * scale)
			pixelsHigh := math.Ceil(height * scale)
			if pixelsWide >= 1 && pixelsHigh >= 1 && pixelsWide <= maxPixels && pixelsHigh <= maxPixels && pixelsWide*pixelsHigh <= maxPixels {
				return dpi, nil
			}
		}
	}
	return 0, records.DocumentProcessorError{Code: "resource_limit"}
}

func objectImages(instance pdfium.Pdfium, object references.FPDF_PAGEOBJECT, depth int, total *int) (bool, error) {
	*total++
	if depth > 16 || *total > maxPDFObjects {
		return false, records.DocumentProcessorError{Code: "resource_limit"}
	}
	kind, err := instance.FPDFPageObj_GetType(&requests.FPDFPageObj_GetType{PageObject: object})
	if err != nil {
		return false, err
	}
	if kind.Type == enums.FPDF_PAGEOBJ_IMAGE {
		size, err := instance.FPDFImageObj_GetImagePixelSize(&requests.FPDFImageObj_GetImagePixelSize{ImageObject: object})
		if err != nil {
			return false, err
		}
		if size.Width > maxPixels || size.Height > maxPixels {
			return false, records.DocumentProcessorError{Code: "resource_limit"}
		}
		if err = validatePixels(int(size.Width), int(size.Height)); err != nil {
			return false, err
		}
		return true, nil
	}
	if kind.Type != enums.FPDF_PAGEOBJ_FORM {
		return false, nil
	}
	count, err := instance.FPDFFormObj_CountObjects(&requests.FPDFFormObj_CountObjects{PageObject: object})
	if err != nil {
		return false, err
	}
	if count.Count < 0 || count.Count > maxPDFObjects-*total {
		return false, records.DocumentProcessorError{Code: "resource_limit"}
	}
	images := false
	for i := 0; i < count.Count; i++ {
		child, err := instance.FPDFFormObj_GetObject(&requests.FPDFFormObj_GetObject{PageObject: object, Index: uint64(i)})
		if err != nil {
			return false, err
		}
		found, err := objectImages(instance, child.PageObject, depth+1, total)
		if err != nil {
			return false, err
		}
		images = images || found
	}
	return images, nil
}
func pageImages(instance pdfium.Pdfium, page requests.Page, total *int) (bool, error) {
	count, err := instance.FPDFPage_CountObjects(&requests.FPDFPage_CountObjects{Page: page})
	if err != nil {
		return false, err
	}
	if count.Count < 0 || count.Count > maxPDFObjects-*total {
		return false, records.DocumentProcessorError{Code: "resource_limit"}
	}
	images := false
	for i := 0; i < count.Count; i++ {
		object, err := instance.FPDFPage_GetObject(&requests.FPDFPage_GetObject{Page: page, Index: i})
		if err != nil {
			return false, err
		}
		found, err := objectImages(instance, object.PageObject, 0, total)
		if err != nil {
			return false, err
		}
		images = images || found
	}
	return images, nil
}
func pdfError(err error) error {
	var safe records.DocumentProcessorError
	if errors.As(err, &safe) {
		return safe
	}
	if errors.Is(err, pdferrors.ErrPassword) || errors.Is(err, pdferrors.ErrSecurity) {
		return records.DocumentProcessorError{Code: "encrypted_pdf"}
	}
	return records.DocumentProcessorError{Code: "invalid_file"}
}
func (e *DocumentFileExtractor) newPDFPool(ctx context.Context) (pdfium.Pool, error) {
	runtime := wazero.NewRuntimeConfig().WithCompilationCache(e.compilationCache).WithCoreFeatures(api.CoreFeaturesV2 | experimental.CoreFeaturesExceptionHandling).WithMemoryLimitPages(16384).WithCloseOnContextDone(true)
	return webassembly.Init(webassembly.Config{Context: ctx, MaxTotal: 1, ReuseWorkers: false, FSConfig: wazero.NewFSConfig(), RuntimeConfig: runtime, Stdout: io.Discard, Stderr: io.Discard})
}

func (e *DocumentFileExtractor) extractPDF(ctx context.Context, data []byte, weights, temp string, options records.DocumentProcessorOptions, invoiceXML *[]byte, invoiceFailure ...*string) (string, int, error) {
	pool, err := e.newPDFPool(ctx)
	if err != nil {
		return "", 0, pdfError(err)
	}
	defer pool.Close()
	instance, err := pool.GetInstanceWithContext(ctx)
	if err != nil {
		return "", 0, pdfError(err)
	}
	defer instance.Close()
	document, err := instance.OpenDocument(&requests.OpenDocument{File: &data})
	if err != nil {
		return "", 0, pdfError(err)
	}
	*invoiceXML, err = pdfInvoiceXML(instance, document.Document)
	if err != nil {
		if len(invoiceFailure) == 0 {
			return "", 0, err
		}
		var failure records.DocumentProcessorError
		if !errors.As(err, &failure) || failure.Code != "invalid_invoice" {
			return "", 0, err
		}
		*invoiceFailure[0] = "invalid_invoice"
		*invoiceXML = nil
	}
	count, err := instance.FPDF_GetPageCount(&requests.FPDF_GetPageCount{Document: document.Document})
	if err != nil {
		return "", 0, pdfError(err)
	}
	if count.PageCount < 1 || count.PageCount > models.MaxPDFPages {
		return "", 0, records.DocumentProcessorError{Code: "resource_limit"}
	}
	pages := make([]string, 0, count.PageCount)
	totalBytes := 0
	for index := 0; index < count.PageCount; index++ {
		if err = ctx.Err(); err != nil {
			return "", 0, records.DocumentProcessorError{Code: "processing_timeout"}
		}
		page := requests.Page{ByIndex: &requests.PageByIndex{Document: document.Document, Index: index}}
		size, err := instance.GetPageSize(&requests.GetPageSize{Page: page})
		if err != nil {
			return "", 0, pdfError(err)
		}
		if !validPDFPageSize(size.Width, size.Height) {
			return "", 0, records.DocumentProcessorError{Code: "resource_limit"}
		}
		native, err := instance.GetPageText(&requests.GetPageText{Page: page})
		if err != nil {
			return "", 0, pdfError(err)
		}
		if len(native.Text) > MaxTextBytes || !utf8.ValidString(native.Text) {
			return "", 0, records.DocumentProcessorError{Code: "resource_limit"}
		}
		pageObjects := 0
		images, err := pageImages(instance, page, &pageObjects)
		if err != nil {
			return "", 0, pdfError(err)
		}
		text := native.Text
		if images || !meaningful(native.Text) {
			dpi, err := pdfRenderDPI(size.Width, size.Height)
			if err != nil {
				return "", 0, err
			}
			render, err := instance.RenderPageInDPI(&requests.RenderPageInDPI{Page: page, DPI: dpi, ImageFormat: requests.RenderImageFormatGrayscale})
			if err != nil {
				return "", 0, pdfError(err)
			}
			ocr, ocrErr := imageOCR(ctx, render.Result.RenderedImage, weights, temp, options)
			render.Cleanup()
			if ocrErr != nil {
				return "", 0, ocrErr
			}
			text = mergeText(native.Text, ocr)
		}
		totalBytes += len(text)
		if index > 0 {
			totalBytes += 2
		}
		if totalBytes > MaxTextBytes {
			return "", 0, records.DocumentProcessorError{Code: "resource_limit"}
		}
		pages = append(pages, text)
	}
	return strings.Join(pages, "\n\n"), count.PageCount, nil
}
