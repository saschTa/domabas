package models

import (
	"net"
	"net/url"
	"strconv"
	"strings"
	"unicode/utf8"
)

func (s EmailSettings) Normalize() (EmailSettings, error) {
	s.Label = strings.TrimSpace(s.Label)
	s.Host = strings.TrimSpace(s.Host)
	if strings.Contains(s.Host, "://") {
		u, e := url.Parse(s.Host)
		if e != nil || u.Scheme != "imaps" || u.User != nil || u.Path != "" || strings.ContainsAny(s.Host, "?#") || u.Hostname() == "" || strings.HasSuffix(u.Host, ":") {
			return s, EmailValidationError{"invalid IMAPS endpoint"}
		}
		if u.Port() != "" {
			p, e := strconv.Atoi(u.Port())
			if e != nil || s.Port != 0 && s.Port != p {
				return s, EmailValidationError{"conflicting IMAPS port"}
			}
			s.Port = p
		}
		s.Host = u.Hostname()
	}
	s.Host = strings.ToLower(strings.TrimSuffix(s.Host, "."))
	if s.Port == 0 {
		s.Port = 993
	}
	if s.IntervalMinutes == 0 {
		s.IntervalMinutes = 15
	}
	if s.MaxAgeDays == 0 {
		s.MaxAgeDays = 30
	}
	if s.PageSize == 0 {
		s.PageSize = 50
	}
	if s.Mailbox == "" {
		s.Mailbox = "INBOX"
	}
	if !utf8.ValidString(s.Label) || utf8.RuneCountInString(s.Label) < 1 || utf8.RuneCountInString(s.Label) > 100 {
		return s, EmailValidationError{"label must contain 1 to 100 characters"}
	}
	if len(s.Host) == 0 || len(s.Host) > 253 || strings.ContainsAny(s.Host, " /\\\t\r\n\x00@?#") || (strings.Contains(s.Host, ":") && net.ParseIP(s.Host) == nil) {
		return s, EmailValidationError{"invalid IMAPS host"}
	}
	if net.ParseIP(s.Host) == nil {
		for _, label := range strings.Split(s.Host, ".") {
			if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
				return s, EmailValidationError{"invalid IMAPS host"}
			}
			for _, ch := range label {
				if !(ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '-') {
					return s, EmailValidationError{"invalid IMAPS host"}
				}
			}
		}
	}
	if s.Port < 1 || s.Port > 65535 || s.IntervalMinutes < 5 || s.IntervalMinutes > 1440 || s.MaxAgeDays < 1 || s.MaxAgeDays > 3650 || s.PageSize < 1 || s.PageSize > 100 {
		return s, EmailValidationError{"email settings are outside their allowed bounds"}
	}
	if !utf8.ValidString(s.Mailbox) || len(s.Mailbox) < 1 || len(s.Mailbox) > 255 || strings.ContainsAny(s.Mailbox, "\r\n\x00") {
		return s, EmailValidationError{"invalid mailbox"}
	}
	return s, nil
}
func (c EmailCredentials) Validate() error {
	if !utf8.ValidString(c.Username) || !utf8.ValidString(c.Password) || len(c.Username) < 1 || len(c.Username) > 320 || strings.ContainsAny(c.Username, "\r\n\x00") || len(c.Password) < 1 || len(c.Password) > 4096 || strings.ContainsRune(c.Password, 0) {
		return EmailValidationError{"invalid email credentials"}
	}
	return nil
}
