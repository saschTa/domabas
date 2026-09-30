package processor

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"io"
	"math"

	records "github.com/domabas/domabas/backend/internal/data/document/models"
	models "github.com/domabas/domabas/backend/internal/domain/document/models"
	"github.com/klippa-app/go-pdfium/requests"
	xdraw "golang.org/x/image/draw"
)

func thumbnailDimensions(width, height float64, maximumWidth, maximumHeight int) (int, int) {
	scale := math.Min(1, math.Min(float64(maximumWidth)/width, float64(maximumHeight)/height))
	return max(1, int(math.Floor(width*scale))), max(1, int(math.Floor(height*scale)))
}

func thumbnailImage(source image.Image, orientation int) image.Image {
	maximumWidth, maximumHeight := models.MaxThumbnailWidth, models.MaxThumbnailHeight
	if orientation >= 5 && orientation <= 8 {
		maximumWidth, maximumHeight = maximumHeight, maximumWidth
	}
	width, height := thumbnailDimensions(float64(source.Bounds().Dx()), float64(source.Bounds().Dy()), maximumWidth, maximumHeight)
	target := image.NewRGBA(image.Rect(0, 0, width, height))
	draw.Draw(target, target.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	xdraw.ApproxBiLinear.Scale(target, target.Bounds(), source, source.Bounds(), draw.Over, nil)
	return orient(target, orientation)
}

func validateThumbnailJPEG(data []byte) (records.DocumentThumbnailResult, error) {
	result := records.DocumentThumbnailResult{}
	if len(data) == 0 || len(data) > models.MaxThumbnailBytes {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	configuration, err := jpeg.DecodeConfig(bytes.NewReader(data))
	if err != nil || configuration.Width < 1 || configuration.Height < 1 || configuration.Width > models.MaxThumbnailWidth || configuration.Height > models.MaxThumbnailHeight {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if _, err = jpeg.Decode(bytes.NewReader(data)); err != nil {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	return records.DocumentThumbnailResult{Bytes: data, Width: configuration.Width, Height: configuration.Height, MediaType: "image/jpeg"}, nil
}

func (e *DocumentFileExtractor) RenderThumbnail(ctx context.Context, reader io.Reader, mediaType string) (records.DocumentThumbnailResult, error) {
	result := records.DocumentThumbnailResult{}
	if mediaType != "application/pdf" && mediaType != "image/png" && mediaType != "image/jpeg" {
		return result, records.DocumentProcessorError{Code: "unsupported_media"}
	}
	data, err := io.ReadAll(io.LimitReader(documentProcessorContextReader{ctx, reader}, MaxFileBytes+1))
	if err != nil {
		return result, err
	}
	if int64(len(data)) > MaxFileBytes {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	var thumbnail image.Image
	if mediaType == "application/pdf" {
		thumbnail, err = e.pdfThumbnail(ctx, data)
	} else {
		configuration, format, decodeErr := image.DecodeConfig(bytes.NewReader(data))
		if decodeErr != nil || "image/"+format != mediaType {
			return result, records.DocumentProcessorError{Code: "invalid_file"}
		}
		if err = validatePixels(configuration.Width, configuration.Height); err != nil {
			return result, err
		}
		var decoded image.Image
		decoded, _, err = image.Decode(bytes.NewReader(data))
		if err != nil {
			return result, records.DocumentProcessorError{Code: "invalid_file"}
		}
		orientation := 1
		if mediaType == "image/jpeg" {
			orientation = exifOrientation(data)
		}
		thumbnail = thumbnailImage(decoded, orientation)
	}
	if err != nil {
		return result, err
	}
	if err = ctx.Err(); err != nil {
		return result, err
	}
	output := &documentProcessorBoundedBuffer{limit: models.MaxThumbnailBytes}
	if err = jpeg.Encode(output, thumbnail, &jpeg.Options{Quality: 85}); err != nil {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if output.exceeded {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if err = ctx.Err(); err != nil {
		return result, err
	}
	return validateThumbnailJPEG(output.Bytes())
}

func (e *DocumentFileExtractor) pdfThumbnail(ctx context.Context, data []byte) (image.Image, error) {
	pool, err := e.newPDFPool(ctx)
	if err != nil {
		return nil, pdfError(err)
	}
	defer pool.Close()
	instance, err := pool.GetInstanceWithContext(ctx)
	if err != nil {
		return nil, pdfError(err)
	}
	defer instance.Close()
	document, err := instance.OpenDocument(&requests.OpenDocument{File: &data})
	if err != nil {
		return nil, pdfError(err)
	}
	count, err := instance.FPDF_GetPageCount(&requests.FPDF_GetPageCount{Document: document.Document})
	if err != nil {
		return nil, pdfError(err)
	}
	if count.PageCount < 1 || count.PageCount > models.MaxPDFPages {
		return nil, records.DocumentProcessorError{Code: "resource_limit"}
	}
	page := requests.Page{ByIndex: &requests.PageByIndex{Document: document.Document, Index: 0}}
	size, err := instance.GetPageSize(&requests.GetPageSize{Page: page})
	if err != nil {
		return nil, pdfError(err)
	}
	if !validPDFPageSize(size.Width, size.Height) {
		return nil, records.DocumentProcessorError{Code: "resource_limit"}
	}
	objects := 0
	if _, err = pageImages(instance, page, &objects); err != nil {
		return nil, pdfError(err)
	}
	width, height := thumbnailDimensions(size.Width, size.Height, models.MaxThumbnailWidth, models.MaxThumbnailHeight)
	render, err := instance.RenderPageInPixels(&requests.RenderPageInPixels{Page: page, Width: width, Height: height})
	if err != nil {
		return nil, pdfError(err)
	}
	defer render.Cleanup()
	return thumbnailImage(render.Result.RenderedImage, 1), nil
}
