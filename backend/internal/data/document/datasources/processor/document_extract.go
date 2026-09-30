package processor

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"image"
	_ "image/jpeg"
	"image/png"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/domabas/domabas/backend/internal/data/document/datasources/mimecontent"
	records "github.com/domabas/domabas/backend/internal/data/document/models"
	"golang.org/x/text/cases"
)

const maxPixels = 50_000_000

type documentProcessorBoundedBuffer struct {
	bytes.Buffer
	limit    int
	exceeded bool
}

func (b *documentProcessorBoundedBuffer) Write(data []byte) (int, error) {
	size := len(data)
	remaining := b.limit - b.Len()
	if len(data) > remaining {
		b.exceeded = true
		data = data[:remaining]
	}
	_, _ = b.Buffer.Write(data)
	return size, nil
}
func validOptions(options records.DocumentProcessorOptions) bool {
	return (options.Language == "eng" || options.Language == "deu" || options.Language == "eng+deu") && (options.Segmentation == "auto" || options.Segmentation == "single_block")
}
func meaningful(text string) bool {
	for _, r := range text {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return true
		}
	}
	return false
}
func normalizedLine(value string) string {
	return strings.Join(strings.Fields(strings.Map(func(r rune) rune {
		if unicode.IsPunct(r) || unicode.IsSymbol(r) {
			return ' '
		}
		return r
	}, cases.Fold().String(value))), " ")
}
func mergeText(native, ocr string) string {
	lines := []string{}
	represented := normalizedLine(native)
	for _, line := range strings.Split(native, "\n") {
		if line = strings.TrimSpace(line); line != "" {
			lines = append(lines, line)
		}
	}
	for _, line := range strings.Split(ocr, "\n") {
		line = strings.TrimSpace(line)
		normalized := normalizedLine(line)
		if normalized == "" || strings.Contains(" "+represented+" ", " "+normalized+" ") {
			continue
		}
		lines = append(lines, line)
		represented += " " + normalized
	}
	return strings.Join(lines, "\n")
}
func validatePixels(width, height int) error {
	if width <= 0 || height <= 0 || width > maxPixels || height > maxPixels || int64(width)*int64(height) > maxPixels {
		return records.DocumentProcessorError{Code: "resource_limit"}
	}
	return nil
}
func orient(source image.Image, orientation int) image.Image {
	if orientation < 2 || orientation > 8 {
		return source
	}
	bounds := source.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	ow, oh := w, h
	if orientation >= 5 {
		ow, oh = h, w
	}
	target := image.NewNRGBA(image.Rect(0, 0, ow, oh))
	for y := 0; y < oh; y++ {
		for x := 0; x < ow; x++ {
			sx, sy := x, y
			switch orientation {
			case 2:
				sx = w - 1 - x
			case 3:
				sx, sy = w-1-x, h-1-y
			case 4:
				sy = h - 1 - y
			case 5:
				sx, sy = y, x
			case 6:
				sx, sy = y, h-1-x
			case 7:
				sx, sy = w-1-y, h-1-x
			case 8:
				sx, sy = w-1-y, x
			}
			target.Set(x, y, source.At(bounds.Min.X+sx, bounds.Min.Y+sy))
		}
	}
	return target
}
func exifOrientation(data []byte) int {
	if len(data) < 4 || data[0] != 0xff || data[1] != 0xd8 {
		return 1
	}
	for at := 2; at+4 <= len(data); {
		if data[at] != 0xff {
			return 1
		}
		marker := data[at+1]
		at += 2
		if marker == 0xda || marker == 0xd9 {
			return 1
		}
		if marker == 0xff {
			at--
			continue
		}
		if marker >= 0xd0 && marker <= 0xd7 {
			continue
		}
		size := int(binary.BigEndian.Uint16(data[at : at+2]))
		if size < 2 || size > len(data)-at {
			return 1
		}
		segment := data[at+2 : at+size]
		at += size
		if marker != 0xe1 || len(segment) < 14 || !bytes.Equal(segment[:6], []byte("Exif\x00\x00")) {
			continue
		}
		tiff := segment[6:]
		var order binary.ByteOrder
		switch string(tiff[:2]) {
		case "II":
			order = binary.LittleEndian
		case "MM":
			order = binary.BigEndian
		default:
			return 1
		}
		if order.Uint16(tiff[2:4]) != 42 {
			return 1
		}
		offset := uint64(order.Uint32(tiff[4:8]))
		if offset+2 > uint64(len(tiff)) {
			return 1
		}
		count := uint64(order.Uint16(tiff[offset : offset+2]))
		if count > 4096 || offset+2+count*12 > uint64(len(tiff)) {
			return 1
		}
		for i := uint64(0); i < count; i++ {
			entry := tiff[offset+2+i*12 : offset+2+(i+1)*12]
			if order.Uint16(entry[:2]) == 0x112 && order.Uint16(entry[2:4]) == 3 && order.Uint32(entry[4:8]) == 1 {
				orientation := int(order.Uint16(entry[8:10]))
				if orientation >= 1 && orientation <= 8 {
					return orientation
				}
				return 1
			}
		}
	}
	return 1
}
func runTesseract(ctx context.Context, weights, file string, options records.DocumentProcessorOptions, osd bool) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()
	args := []string{file, "stdout", "--tessdata-dir", weights}
	if osd {
		args = append(args, "-l", "osd", "--psm", "0")
	} else {
		segmentation := "3"
		if options.Segmentation == "single_block" {
			segmentation = "6"
		}
		args = append(args, "-l", options.Language, "--oem", "1", "--psm", segmentation)
	}
	command := exec.CommandContext(ctx, "tesseract", args...)
	command.Env = append(os.Environ(), "OMP_THREAD_LIMIT=1")
	command.WaitDelay = time.Second
	output := &documentProcessorBoundedBuffer{limit: MaxTextBytes}
	diagnostics := &documentProcessorBoundedBuffer{limit: 64 << 10}
	command.Stdout = output
	command.Stderr = diagnostics
	err := command.Run()
	if ctx.Err() != nil {
		return "", records.DocumentProcessorError{Code: "processing_timeout"}
	}
	if output.exceeded {
		return "", records.DocumentProcessorError{Code: "resource_limit"}
	}
	if err != nil {
		if osd {
			return "", nil
		}
		return "", records.DocumentProcessorError{Code: "processing_failed"}
	}
	if !utf8.Valid(output.Bytes()) {
		return "", records.DocumentProcessorError{Code: "processing_failed"}
	}
	return output.String(), nil
}
func imageOCR(ctx context.Context, source image.Image, weights, temp string, options records.DocumentProcessorOptions) (string, error) {
	if err := validatePixels(source.Bounds().Dx(), source.Bounds().Dy()); err != nil {
		return "", err
	}
	file := filepath.Join(temp, "page.png")
	write := func(img image.Image) error {
		output, err := os.OpenFile(file, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
		if err != nil {
			return err
		}
		return errors.Join(png.Encode(output, img), output.Close())
	}
	if err := write(source); err != nil {
		return "", records.DocumentProcessorError{Code: "processing_failed"}
	}
	orientation, err := runTesseract(ctx, weights, file, options, true)
	if err != nil {
		return "", err
	}
	rotation := 0
	for _, line := range strings.Split(orientation, "\n") {
		if strings.HasPrefix(line, "Rotate: ") {
			rotation, _ = strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(line, "Rotate: ")))
		}
	}
	transform := 1
	switch rotation {
	case 90:
		transform = 6
	case 180:
		transform = 3
	case 270:
		transform = 8
	}
	if transform != 1 {
		if err = write(orient(source, transform)); err != nil {
			return "", records.DocumentProcessorError{Code: "processing_failed"}
		}
	}
	return runTesseract(ctx, weights, file, options, false)
}
func (e *DocumentFileExtractor) ExtractFile(ctx context.Context, reader io.Reader, mediaType, weights, temp string, options records.DocumentProcessorOptions) (records.DocumentExtractionResult, error) {
	result := records.DocumentExtractionResult{ExtractionRevision: ExtractionRevision, Engine: "tesseract", EngineVersion: EngineVersion}
	if options.ExtractionRevision != "" {
		result.ExtractionRevision = options.ExtractionRevision
	}
	if options.ExtractionRevision != "" && options.ExtractionRevision != ExtractionRevision && options.ExtractionRevision != CurrentExtractionRevision {
		return result, records.DocumentProcessorError{Code: "configuration_unavailable"}
	}
	if !validOptions(options) {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	data, err := io.ReadAll(io.LimitReader(documentProcessorContextReader{ctx, reader}, MaxFileBytes+1))
	if err != nil {
		return result, err
	}
	if int64(len(data)) > MaxFileBytes {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	if mediaType == "message/rfc822" {
		if options.ExtractionRevision != CurrentExtractionRevision {
			return result, records.DocumentProcessorError{Code: "configuration_unavailable"}
		}
		inspection, err := mimecontent.Inspect(ctx, bytes.NewReader(data), nil)
		if err != nil || inspection.TextFailures {
			return result, records.DocumentProcessorError{Code: "processing_failed"}
		}
		return records.DocumentExtractionResult{ExtractionRevision: CurrentExtractionRevision, Text: inspection.Text, Pages: 1, Engine: "domabas-mime", EngineVersion: "1", Weights: []records.DocumentProcessorWeight{}}, nil
	}
	switch mediaType {
	case "image/png", "image/jpeg":
		configuration, format, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || "image/"+format != mediaType {
			return result, records.DocumentProcessorError{Code: "invalid_file"}
		}
		if err = validatePixels(configuration.Width, configuration.Height); err != nil {
			return result, err
		}
		decoded, _, err := image.Decode(bytes.NewReader(data))
		if err != nil {
			return result, records.DocumentProcessorError{Code: "invalid_file"}
		}
		if mediaType == "image/jpeg" {
			decoded = orient(decoded, exifOrientation(data))
		}
		result.Text, err = imageOCR(ctx, decoded, weights, temp, options)
		if err != nil {
			return result, err
		}
		result.Pages = 1
	case "application/pdf":
		result.Text, result.Pages, err = e.extractPDF(ctx, data, weights, temp, options, &result.InvoiceXML, &result.InvoiceFailureCode)
		if err != nil {
			return result, err
		}
	default:
		return result, records.DocumentProcessorError{Code: "invalid_file"}
	}
	if !utf8.ValidString(result.Text) || strings.ContainsRune(result.Text, 0) {
		return result, records.DocumentProcessorError{Code: "processing_failed"}
	}
	if len(result.Text) > MaxTextBytes {
		return result, records.DocumentProcessorError{Code: "resource_limit"}
	}
	for _, weight := range weightArtifacts() {
		result.Weights = append(result.Weights, records.DocumentProcessorWeight{Name: strings.TrimSuffix(weight.Name, ".traineddata"), SHA256: weight.SHA256})
	}
	return result, nil
}
