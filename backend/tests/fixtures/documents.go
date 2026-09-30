//go:build e2e || temporal

package fixtures

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"image/png"
	"strings"
	"testing"

	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

func raster(t testing.TB, lines []string) image.Image {
	t.Helper()
	parsed, err := opentype.Parse(goregular.TTF)
	if err != nil {
		t.Fatal(err)
	}
	face, err := opentype.NewFace(parsed, &opentype.FaceOptions{Size: 25, DPI: 144, Hinting: font.HintingFull})
	if err != nil {
		t.Fatal(err)
	}
	defer face.Close()
	canvas := image.NewRGBA(image.Rect(0, 0, 1400, 500))
	draw.Draw(canvas, canvas.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	for index, line := range lines {
		drawer := font.Drawer{Dst: canvas, Src: image.NewUniform(color.Black), Face: face, Dot: fixed.P(55, 100+index*85)}
		drawer.DrawString(line)
	}
	return canvas
}

func PNG(t testing.TB, lines ...string) []byte {
	t.Helper()
	var buffer bytes.Buffer
	if err := png.Encode(&buffer, raster(t, lines)); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func JPEG(t testing.TB, lines ...string) []byte {
	t.Helper()
	var buffer bytes.Buffer
	if err := jpeg.Encode(&buffer, raster(t, lines), &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func PDF(t testing.TB, pages ...Page) []byte {
	t.Helper()
	objects := [][]byte{nil, nil, []byte("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")}
	add := func(value []byte) int {
		objects = append(objects, value)
		return len(objects)
	}
	var kids []string
	for _, page := range pages {
		width, height := page.Width, page.Height
		if width == 0 {
			width = 700
		}
		if height == 0 {
			height = 300
		}
		var content strings.Builder
		resources := "/Font << /F1 3 0 R >>"
		if page.Text != "" {
			escaped := strings.NewReplacer("\\", "\\\\", "(", "\\(", ")", "\\)").Replace(page.Text)
			fmt.Fprintf(&content, "BT /F1 20 Tf 25 275 Td (%s) Tj ET\n", escaped)
		}
		if len(page.JPEG) != 0 {
			imageObject := bytes.NewBufferString(fmt.Sprintf("<< /Type /XObject /Subtype /Image /Width 1400 /Height 500 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\nstream\n", len(page.JPEG)))
			imageObject.Write(page.JPEG)
			imageObject.WriteString("\nendstream")
			imageID := add(imageObject.Bytes())
			resources += fmt.Sprintf(" /XObject << /Im0 %d 0 R >>", imageID)
			content.WriteString("q 700 0 0 250 0 0 cm /Im0 Do Q\n")
		}
		stream := content.String()
		contentID := add([]byte(fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(stream), stream)))
		pageID := add([]byte(fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %g %g] /Resources << %s >> /Contents %d 0 R >>", width, height, resources, contentID)))
		kids = append(kids, fmt.Sprintf("%d 0 R", pageID))
	}
	objects[0] = []byte("<< /Type /Catalog /Pages 2 0 R >>")
	objects[1] = []byte(fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.Join(kids, " "), len(kids)))
	var result bytes.Buffer
	result.WriteString("%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
	offsets := make([]int, len(objects))
	for index, object := range objects {
		offsets[index] = result.Len()
		fmt.Fprintf(&result, "%d 0 obj\n", index+1)
		result.Write(object)
		result.WriteString("\nendobj\n")
	}
	xref := result.Len()
	fmt.Fprintf(&result, "xref\n0 %d\n0000000000 65535 f \n", len(objects)+1)
	for _, offset := range offsets {
		fmt.Fprintf(&result, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&result, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(objects)+1, xref)
	return result.Bytes()
}
