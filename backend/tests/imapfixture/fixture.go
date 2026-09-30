package imapfixture

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"log"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapserver"
	"github.com/emersion/go-imap/v2/imapserver/imapmemserver"
	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

type Ready struct {
	Host         string `json:"host"`
	Port         int    `json:"port"`
	CAFile       string `json:"caFile"`
	Username     string `json:"username"`
	Password     string `json:"password"`
	Mailbox      string `json:"mailbox"`
	MessageCount int    `json:"messageCount"`
}
type Fixture struct {
	Server   *imapserver.Server
	Listener net.Listener
	Ready    Ready
}
type literal struct{ *bytes.Reader }

func (l literal) Size() int64 { return int64(l.Len()) }
func Message() []byte {
	var picture bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 1400, 400))
	draw.Draw(img, img.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	parsed, _ := opentype.Parse(goregular.TTF)
	face, _ := opentype.NewFace(parsed, &opentype.FaceOptions{Size: 25, DPI: 144, Hinting: font.HintingFull})
	defer face.Close()
	drawer := font.Drawer{Dst: img, Src: image.NewUniform(color.Black), Face: face, Dot: fixed.P(55, 100)}
	drawer.DrawString("Domabas email attachment fixture")
	_ = png.Encode(&picture, img)
	pdf := fixturePDF()
	return []byte("From: sender@example.test\r\nTo: owner@example.test\r\nSubject: Domabas email fixture\r\nMessage-ID: <domabas-email-fixture@example.test>\r\nDate: " + time.Now().UTC().Format(time.RFC1123Z) + "\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=domabas-fixture\r\n\r\n--domabas-fixture\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nThe retained email fixture contains a searchable body and two attachments.\r\n--domabas-fixture\r\nContent-Type: image/png\r\nContent-Disposition: attachment; filename=fixture.png\r\nContent-Transfer-Encoding: base64\r\n\r\n" + base64.StdEncoding.EncodeToString(picture.Bytes()) + "\r\n--domabas-fixture\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=fixture.pdf\r\nContent-Transfer-Encoding: base64\r\n\r\n" + base64.StdEncoding.EncodeToString([]byte(pdf)) + "\r\n--domabas-fixture--\r\n")
}
func fixturePDF() string {
	stream := "BT /F1 20 Tf 25 100 Td (Domabas email attachment fixture) Tj ET\n"
	objects := []string{"<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 700 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(stream), stream)}
	var out strings.Builder
	out.WriteString("%PDF-1.4\n")
	offsets := make([]int, len(objects))
	for i, object := range objects {
		offsets[i] = out.Len()
		fmt.Fprintf(&out, "%d 0 obj\n%s\nendobj\n", i+1, object)
	}
	xref := out.Len()
	fmt.Fprintf(&out, "xref\n0 %d\n0000000000 65535 f \n", len(objects)+1)
	for _, offset := range offsets {
		fmt.Fprintf(&out, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(objects)+1, xref)
	return out.String()
}
func Start(directory, address string) (*Fixture, error) {
	if err := os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	info, err := os.Stat(directory)
	if err != nil || info.Mode().Perm()&0077 != 0 {
		return nil, fmt.Errorf("fixture directory must be private")
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	certificate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Domabas disposable IMAP fixture"}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(24 * time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")}}
	der, err := x509.CreateCertificate(rand.Reader, certificate, certificate, &key.PublicKey, key)
	if err != nil {
		return nil, err
	}
	caFile := filepath.Join(directory, "imap-ca.pem")
	if err = os.WriteFile(caFile, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0600); err != nil {
		return nil, err
	}
	listener, err := tls.Listen("tcp", address, &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}})
	if err != nil {
		return nil, err
	}
	host, port, _ := net.SplitHostPort(listener.Addr().String())
	number, _ := strconv.Atoi(port)
	memory := imapmemserver.New()
	user := imapmemserver.NewUser("fixture@example.test", "fixture-password-only")
	if err = user.Create("INBOX", nil); err != nil {
		listener.Close()
		return nil, err
	}
	if _, err = user.Append("INBOX", literal{bytes.NewReader(Message())}, &imap.AppendOptions{Time: now}); err != nil {
		listener.Close()
		return nil, err
	}
	memory.AddUser(user)
	server := imapserver.New(&imapserver.Options{NewSession: func(*imapserver.Conn) (imapserver.Session, *imapserver.GreetingData, error) {
		return memory.NewSession(), nil, nil
	}, Logger: log.New(io.Discard, "", 0)})
	fixture := &Fixture{Server: server, Listener: listener, Ready: Ready{Host: host, Port: number, CAFile: caFile, Username: "fixture@example.test", Password: "fixture-password-only", Mailbox: "INBOX", MessageCount: 1}}
	go func() { _ = server.Serve(listener) }()
	return fixture, nil
}
func (f *Fixture) Close() error { return f.Server.Close() }
func (f *Fixture) PublishReady(filename string) error {
	if strings.TrimSpace(filename) == "" {
		return fmt.Errorf("ready file required")
	}
	data, err := json.Marshal(f.Ready)
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(filename), ".imap-ready-*")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if err = file.Chmod(0600); err == nil {
		_, err = file.Write(data)
	}
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(name, filename)
}
