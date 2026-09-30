//go:build e2e || temporal

package fixtures

type Page struct {
	Text   string
	JPEG   []byte
	Width  float64
	Height float64
}
