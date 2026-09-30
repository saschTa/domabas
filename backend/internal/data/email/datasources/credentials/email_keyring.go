package credentials

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"sort"

	m "github.com/domabas/domabas/backend/internal/domain/email/models"
)

type EmailCredentialKeyring struct {
	active string
	keys   map[string]cipher.AEAD
}

var keyID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,32}$`)
var ErrMissingKey = errors.New("email credential key unavailable")
var ErrInvalidConfiguration = errors.New("invalid email credential keyring configuration")

func NewEmailCredentialKeyring(raw, active string) (*EmailCredentialKeyring, error) {
	k := &EmailCredentialKeyring{active: active, keys: map[string]cipher.AEAD{}}
	if raw == "" && active == "" {
		return k, nil
	}
	if raw == "" || !keyID.MatchString(active) || len(raw) > 8192 {
		return nil, ErrInvalidConfiguration
	}
	dec := json.NewDecoder(bytes.NewBufferString(raw))
	token, err := dec.Token()
	if err != nil || token != json.Delim('{') {
		return nil, ErrInvalidConfiguration
	}
	for dec.More() {
		token, err = dec.Token()
		if err != nil {
			return nil, ErrInvalidConfiguration
		}
		id, ok := token.(string)
		if !ok || !keyID.MatchString(id) || len(k.keys) >= 8 || k.keys[id] != nil {
			return nil, ErrInvalidConfiguration
		}
		var encoded string
		if dec.Decode(&encoded) != nil {
			return nil, ErrInvalidConfiguration
		}
		key, e := base64.StdEncoding.Strict().DecodeString(encoded)
		if e != nil || len(key) != 32 {
			return nil, ErrInvalidConfiguration
		}
		block, e := aes.NewCipher(key)
		clear(key)
		if e != nil {
			return nil, ErrInvalidConfiguration
		}
		aead, e := cipher.NewGCMWithRandomNonce(block)
		if e != nil {
			return nil, ErrInvalidConfiguration
		}
		k.keys[id] = aead
	}
	if _, err = dec.Token(); err != nil {
		return nil, ErrInvalidConfiguration
	}
	if dec.Decode(new(any)) != io.EOF || k.keys[active] == nil {
		return nil, ErrInvalidConfiguration
	}
	return k, nil
}
func (k *EmailCredentialKeyring) Available() bool  { return k != nil && k.keys[k.active] != nil }
func (k *EmailCredentialKeyring) ActiveID() string { return k.active }
func (k *EmailCredentialKeyring) KeyIDs() []string {
	ids := make([]string, 0, len(k.keys))
	for id := range k.keys {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}
func associated(identity m.EmailCredentialIdentity) []byte {
	var b bytes.Buffer
	for _, v := range []string{"1", identity.ProviderID, identity.OwnerID, identity.AccountID} {
		_ = binary.Write(&b, binary.BigEndian, uint32(len(v)))
		b.WriteString(v)
	}
	return b.Bytes()
}
func (k *EmailCredentialKeyring) Seal(identity m.EmailCredentialIdentity, credentials m.EmailCredentials) (string, []byte, error) {
	if !k.Available() {
		return "", nil, ErrMissingKey
	}
	if err := credentials.Validate(); err != nil {
		return "", nil, err
	}
	payload := make([]byte, 5+len(credentials.Username)+len(credentials.Password))
	payload[0] = 1
	binary.BigEndian.PutUint16(payload[1:3], uint16(len(credentials.Username)))
	binary.BigEndian.PutUint16(payload[3:5], uint16(len(credentials.Password)))
	copy(payload[5:], credentials.Username)
	copy(payload[5+len(credentials.Username):], credentials.Password)
	defer clear(payload)
	return k.active, k.keys[k.active].Seal(nil, nil, payload, associated(identity)), nil
}
func (k *EmailCredentialKeyring) Open(identity m.EmailCredentialIdentity, id string, ciphertext []byte) (m.EmailCredentials, error) {
	if k == nil || k.keys[id] == nil {
		return m.EmailCredentials{}, ErrMissingKey
	}
	if len(ciphertext) > 8192 {
		return m.EmailCredentials{}, ErrMissingKey
	}
	payload, err := k.keys[id].Open(nil, nil, ciphertext, associated(identity))
	if err != nil {
		return m.EmailCredentials{}, ErrMissingKey
	}
	defer clear(payload)
	if len(payload) < 5 || payload[0] != 1 {
		return m.EmailCredentials{}, ErrMissingKey
	}
	userLength := int(binary.BigEndian.Uint16(payload[1:3]))
	passwordLength := int(binary.BigEndian.Uint16(payload[3:5]))
	if len(payload) != 5+userLength+passwordLength {
		return m.EmailCredentials{}, ErrMissingKey
	}
	result := m.EmailCredentials{Username: string(payload[5 : 5+userLength]), Password: string(payload[5+userLength:])}
	if result.Validate() != nil {
		return m.EmailCredentials{}, ErrMissingKey
	}
	return result, nil
}
