//go:build e2e || jobs

package fixtures

type Page struct {
	Text   string
	JPEG   []byte
	Width  float64
	Height float64
}
