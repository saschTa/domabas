package models

import (
	"regexp"
	"sort"
	"strings"
	"unicode"
	"unicode/utf8"
)

const invoiceNumberSpace = `[ \t\p{Zs}]`
const invoiceNumberBody = `(?:[0-9]+(?:` + invoiceNumberSpace + `*[.,'’]` + invoiceNumberSpace + `*[0-9]+|[\x{00a0}\x{202f}\x{2009}][0-9]+)*|[.,]` + invoiceNumberSpace + `*[0-9]+)`
const invoiceGroupedNumberBody = `[1-9][0-9]{0,2}(?: [0-9]{3})+(?:` + invoiceNumberSpace + `*[.,]` + invoiceNumberSpace + `*[0-9]+)?`

var invoiceNumberToken = regexp.MustCompile(invoiceSignedNumberPattern(invoiceNumberBody))
var invoiceGroupedNumberToken = regexp.MustCompile(invoiceSignedNumberPattern(invoiceGroupedNumberBody))
var invoiceNumberPadding = regexp.MustCompile(invoiceNumberSpace + `*([.,'’])` + invoiceNumberSpace + `*`)
var invoiceQuantitySuffix = regexp.MustCompile(`(?i)^(?:kwh|kw|kg|mg|km|cm|mm|ml|std|stunden|stück|stueck|stk|pcs|pc|ea|g|m[²³23]?|l|h)`)

func invoiceSignedNumberPattern(body string) string {
	return `(?:\(` + invoiceNumberSpace + `*` + body + invoiceNumberSpace + `*\)|(?:[+\p{Pd}−]` + invoiceNumberSpace + `*)?` + body + `[\p{Pd}−]?)`
}

func invoiceSourceNumberSpans(text string, dates []invoiceSourceSpan, currencies ...string) []invoiceSourceSpan {
	masked := []byte(text)
	for _, span := range dates {
		for i := span.start; i < span.end; i++ {
			if masked[i] != '\n' && masked[i] != '\r' {
				masked[i] = ' '
			}
		}
	}
	source := string(masked)
	var spans []invoiceSourceSpan
	for _, match := range invoiceNumberToken.FindAllStringIndex(source, -1) {
		span := invoiceSourceSpan{start: match[0], end: match[1]}
		if invoiceNumericBoundary(text, span, currencies) {
			spans = append(spans, span)
		}
	}
	var groups []invoiceSourceSpan
	lineStart, lineEnd := 0, strings.IndexAny(source, "\r\n")
	if lineEnd < 0 {
		lineEnd = len(source)
	}
	for _, match := range invoiceGroupedNumberToken.FindAllStringIndex(source, -1) {
		span := invoiceSourceSpan{start: match[0], end: match[1]}
		if !invoiceNumericBoundary(text, span, currencies) {
			continue
		}
		for span.start > lineEnd {
			lineStart = lineEnd + 1
			if end := strings.IndexAny(source[lineStart:], "\r\n"); end >= 0 {
				lineEnd = lineStart + end
			} else {
				lineEnd = len(source)
			}
		}
		isolated := true
		first := sort.Search(len(spans), func(i int) bool { return spans[i].start >= lineStart })
		for i := first; i < len(spans) && spans[i].end <= lineEnd; i++ {
			number := spans[i]
			if number.start < span.start || number.end > span.end {
				isolated = false
				break
			}
		}
		if isolated {
			groups = append(groups, span)
		}
	}
	result := append([]invoiceSourceSpan(nil), groups...)
	groupIndex := 0
	for _, span := range spans {
		for groupIndex < len(groups) && groups[groupIndex].end <= span.start {
			groupIndex++
		}
		contained := groupIndex < len(groups) && span.start >= groups[groupIndex].start && span.end <= groups[groupIndex].end
		if !contained {
			result = append(result, span)
		}
	}
	return result
}

func invoiceNumericBoundary(text string, span invoiceSourceSpan, currencies []string) bool {
	start, end := span.start, span.end
	for _, currency := range currencies {
		if len(currency) != 3 {
			continue
		}
		if start >= 3 && strings.EqualFold(text[start-3:start], currency) {
			start -= 3
		}
		if end+3 <= len(text) && strings.EqualFold(text[end:end+3], currency) {
			end += 3
		}
	}
	if suffix := invoiceQuantitySuffix.FindString(text[end:]); suffix != "" {
		end += len(suffix)
	}
	last, _ := utf8.DecodeLastRuneInString(text[span.start:span.end])
	if unicode.Is(unicode.Pd, last) || last == '−' {
		after := strings.TrimLeftFunc(text[end:], unicode.IsSpace)
		next, _ := utf8.DecodeRuneInString(after)
		if unicode.IsDigit(next) || unicode.Is(unicode.Pd, next) || strings.ContainsRune("+−", next) {
			return false
		}
	}
	return invoiceTokenBoundary(text, start, end)
}
