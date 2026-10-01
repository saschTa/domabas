package models

import (
	"regexp"
	"strings"
	"unicode"
)

const invoiceOCRSpace = `[\s\v\p{Z}\x{0085}]`

var invoiceNumberLabel = regexp.MustCompile(`(?i)(?:^|[^\p{L}\p{N}_])(?:nr|no)\.$`)
var invoiceIdentifierContinuation = regexp.MustCompile(`^[ \p{Zs}]*([/._\p{Pd}−])[ \p{Zs}]*([\p{L}\p{N}])`)

func invoiceContainsIdentifier(text, value string, dates []invoiceSourceSpan) bool {
	runes := []rune(strings.TrimSpace(value))
	var pattern strings.Builder
	pattern.WriteString(`(?i)`)
	for i := 0; i < len(runes); i++ {
		r := runes[i]
		if unicode.IsSpace(r) {
			start := i
			for i+1 < len(runes) && unicode.IsSpace(runes[i+1]) {
				i++
			}
			pattern.WriteString(invoiceOCRSpace)
			if start > 0 && i+1 < len(runes) && invoiceIdentifierTransition(runes[start-1], runes[i+1]) {
				pattern.WriteByte('*')
			} else {
				pattern.WriteByte('+')
			}
			continue
		}
		if i > 0 && invoiceIdentifierTransition(runes[i-1], r) {
			pattern.WriteString(invoiceOCRSpace + `*`)
		}
		if unicode.Is(unicode.Pd, r) || r == '−' {
			pattern.WriteString(invoiceOCRSpace + `*[\p{Pd}−]` + invoiceOCRSpace + `*`)
		} else if strings.ContainsRune("/._", r) {
			pattern.WriteString(invoiceOCRSpace + `*` + regexp.QuoteMeta(string(r)) + invoiceOCRSpace + `*`)
		} else {
			pattern.WriteString(regexp.QuoteMeta(string(r)))
		}
	}
	if len(runes) == 0 {
		return false
	}
	matcher, err := regexp.Compile(pattern.String())
	if err != nil {
		return false
	}
	for _, span := range matcher.FindAllStringIndex(text, -1) {
		start, end := span[0], span[1]
		match := text[start:end]
		start += len(match) - len(strings.TrimLeftFunc(match, unicode.IsSpace))
		end -= len(match) - len(strings.TrimRightFunc(match, unicode.IsSpace))
		boundary := invoiceTokenBoundary(text, start, end)
		if !boundary && invoiceNumberLabel.MatchString(text[:start]) {
			boundary = invoiceTokenBoundary(text[start:], 0, end-start)
		}
		if boundary && !invoiceIdentifierContinues(text, end, dates) {
			return true
		}
	}
	return false
}

func invoiceIdentifierContinues(text string, end int, dates []invoiceSourceSpan) bool {
	match := invoiceIdentifierContinuation.FindStringSubmatchIndex(text[end:])
	if match == nil {
		return false
	}
	separator := text[end+match[2] : end+match[3]]
	if separator == "." && match[2] == 0 && match[4] > match[3] {
		return false
	}
	if separator == "/" && match[2] > 0 && match[4] > match[3] {
		for _, date := range dates {
			if date.start == end+match[4] {
				return false
			}
		}
	}
	return true
}

func invoiceIdentifierTransition(a, b rune) bool {
	return unicode.IsLetter(a) && unicode.IsDigit(b) || unicode.IsDigit(a) && unicode.IsLetter(b)
}
