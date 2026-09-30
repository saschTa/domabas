package pdf

import (
	"bytes"
	"crypto/md5"
	"crypto/rc4"
	"encoding/hex"
	"fmt"
)

func PasswordPDF(password, text string) []byte {
	padding := []byte{0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41, 0x64, 0x00, 0x4e, 0x56, 0xff, 0xfa, 0x01, 0x08, 0x2e, 0x2e, 0x00, 0xb6, 0xd0, 0x68, 0x3e, 0x80, 0x2f, 0x0c, 0xa9, 0xfe, 0x64, 0x53, 0x69, 0x7a}
	pad := func(value string) []byte { return append([]byte(value), padding...)[:32] }
	encrypt := func(key, data []byte) []byte {
		cipher, err := rc4.NewCipher(key)
		if err != nil {
			panic(err)
		}
		result := make([]byte, len(data))
		cipher.XORKeyStream(result, data)
		return result
	}
	ownerDigest := md5.Sum(pad("fixture owner password"))
	owner := encrypt(ownerDigest[:5], pad(password))
	id := md5.Sum([]byte(text))
	material := append(pad(password), owner...)
	material = append(material, 0xfc, 0xff, 0xff, 0xff)
	material = append(material, id[:]...)
	digest := md5.Sum(material)
	key := digest[:5]
	user := encrypt(key, padding)
	objectDigest := md5.Sum(append(append([]byte{}, key...), 5, 0, 0, 0, 0))
	stream := encrypt(objectDigest[:10], []byte(fmt.Sprintf("BT /F1 20 Tf 25 100 Td (%s) Tj ET", text)))
	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>",
		fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(stream), stream),
		fmt.Sprintf("<< /Filter /Standard /V 1 /R 2 /Length 40 /O <%x> /U <%x> /P -4 >>", owner, user),
	}
	var output bytes.Buffer
	output.WriteString("%PDF-1.7\n")
	offsets := []int{}
	for i, object := range objects {
		offsets = append(offsets, output.Len())
		fmt.Fprintf(&output, "%d 0 obj\n%s\nendobj\n", i+1, object)
	}
	xref := output.Len()
	fmt.Fprintf(&output, "xref\n0 %d\n0000000000 65535 f \n", len(objects)+1)
	for _, offset := range offsets {
		fmt.Fprintf(&output, "%010d 00000 n \n", offset)
	}
	identifier := hex.EncodeToString(id[:])
	fmt.Fprintf(&output, "trailer\n<< /Size %d /Root 1 0 R /Encrypt 6 0 R /ID [<%s><%s>] >>\nstartxref\n%d\n%%%%EOF\n", len(objects)+1, identifier, identifier, xref)
	return output.Bytes()
}
