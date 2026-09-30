package services

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	p "github.com/domabas/domabas/backend/internal/domain/document/interfaces"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"image"
	"image/jpeg"
	"io"
	"testing"
)

type thumbnailRepositoryStub struct {
	p.DocumentThumbnailRepository
	published *m.DocumentThumbnailContent
}

func (r *thumbnailRepositoryStub) ThumbnailWork(context.Context, m.DocumentThumbnailJob) (m.DocumentThumbnailWork, error) {
	return m.DocumentThumbnailWork{Reference: m.DocumentFileReference{File: m.DocumentFile{MediaType: "image/png"}}}, nil
}
func (r *thumbnailRepositoryStub) PublishThumbnail(_ context.Context, _ m.DocumentThumbnailJob, v m.DocumentThumbnailContent) error {
	r.published = &v
	return nil
}

type thumbnailStoreStub struct{ p.DocumentContentStore }

func (thumbnailStoreStub) Open(context.Context, m.DocumentFileReference) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader([]byte("source"))), nil
}

type thumbnailRendererStub struct{ image m.DocumentThumbnailImage }

func (r thumbnailRendererStub) RenderThumbnail(context.Context, io.Reader, string) (m.DocumentThumbnailImage, error) {
	return r.image, nil
}
func TestThumbnailPublicationRejectsIncompleteJPEGAndComputesIdentity(t *testing.T) {
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, image.NewRGBA(image.Rect(0, 0, 32, 40)), nil); err != nil {
		t.Fatal(err)
	}
	valid := encoded.Bytes()
	truncated := valid[:len(valid)-30]
	if _, err := jpeg.DecodeConfig(bytes.NewReader(truncated)); err != nil {
		t.Fatalf("fixture must retain JPEG header: %v", err)
	}
	for _, scenario := range []struct {
		name  string
		data  []byte
		width int
		valid bool
	}{{"complete", valid, 32, true}, {"header only", truncated, 32, false}, {"dimension mismatch", valid, 31, false}, {"byte limit", make([]byte, m.MaxThumbnailBytes+1), 32, false}} {
		t.Run(scenario.name, func(t *testing.T) {
			repo := &thumbnailRepositoryStub{}
			service := NewDocumentThumbnailService(repo, thumbnailStoreStub{}, thumbnailRendererStub{m.DocumentThumbnailImage{Bytes: scenario.data, Width: scenario.width, Height: 40, MediaType: "image/jpeg"}}, nil)
			err := service.Render(t.Context(), m.DocumentThumbnailJob{SourceSHA256: "source-hash", RendererRevision: 1})
			if (err == nil) != scenario.valid || (repo.published != nil) != scenario.valid {
				t.Fatalf("published=%v err=%v", repo.published != nil, err)
			}
			if scenario.valid {
				hash := sha256.Sum256(valid)
				if repo.published.Descriptor.SHA256 != hex.EncodeToString(hash[:]) || repo.published.Descriptor.SourceSHA256 != "source-hash" {
					t.Fatal("publication lost source/output identity")
				}
			}
		})
	}
}
