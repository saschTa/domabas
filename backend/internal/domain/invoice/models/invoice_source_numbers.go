package models

import (
	"strings"
	"unicode"
)

func invoiceSourceNumbers(text string, dates []invoiceSourceSpan, currencies ...string) map[string]bool {
	values := make(map[string]bool)
	var ambiguous []invoiceSourceNumber
	dot, comma := false, false
	for _, span := range invoiceSourceNumberSpans(text, dates, currencies...) {
		raw := text[span.start:span.end]
		dotValue, dotOK := invoiceSourceDecimal(raw, '.')
		commaValue, commaOK := invoiceSourceDecimal(raw, ',')
		switch {
		case dotOK && commaOK && dotValue != commaValue:
			ambiguous = append(ambiguous, invoiceSourceNumber{dot: dotValue, comma: commaValue})
		case dotOK:
			values[dotValue] = true
			dot = dot || !commaOK && strings.Contains(raw, ".")
		case commaOK:
			values[commaValue] = true
			comma = comma || strings.Contains(raw, ",")
		}
	}
	if dot != comma {
		for _, value := range ambiguous {
			if dot {
				values[value.dot] = true
			} else {
				values[value.comma] = true
			}
		}
	}
	return values
}

func invoiceSourceDecimal(raw string, separator byte) (string, bool) {
	raw = invoiceNumberPadding.ReplaceAllString(raw, "$1")
	raw = strings.Map(func(r rune) rune {
		if unicode.Is(unicode.Pd, r) {
			return '-'
		}
		return r
	}, raw)
	raw = strings.NewReplacer("−", "-", "\u00a0", " ", "\u202f", " ", "\u2009", " ", "’", "'").Replace(raw)
	sign := ""
	if strings.HasPrefix(raw, "(") && strings.HasSuffix(raw, ")") {
		sign, raw = "-", strings.TrimSpace(raw[1:len(raw)-1])
	} else if strings.HasSuffix(raw, "-") {
		sign, raw = "-", strings.TrimSpace(raw[:len(raw)-1])
	}
	if strings.HasPrefix(raw, "-") || strings.HasPrefix(raw, "+") {
		if sign != "" {
			return "", false
		}
		sign, raw = raw[:1], strings.TrimLeft(raw[1:], " \t")
	}
	if strings.Count(raw, string(separator)) > 1 {
		return "", false
	}
	integer, fraction := raw, ""
	if at := strings.IndexByte(raw, separator); at >= 0 {
		integer, fraction = raw[:at], raw[at+1:]
		if !invoiceDigits(fraction) {
			return "", false
		}
		if integer == "" {
			integer = "0"
		}
	}
	normalized, ok := invoiceGroupedInteger(integer)
	if !ok || len(normalized) > 24 || len(fraction) > 12 {
		return "", false
	}
	if sign == "+" {
		sign = ""
	}
	value := sign + normalized
	if fraction != "" {
		value += "." + fraction
	}
	return invoiceCanonicalDecimal(value), true
}

func invoiceGroupedInteger(value string) (string, bool) {
	if invoiceDigits(value) {
		return value, true
	}
	groups := strings.FieldsFunc(value, func(r rune) bool { return r == '.' || r == ',' || r == ' ' || r == '\'' })
	if len(groups) < 2 || len(groups[0]) < 1 || len(groups[0]) > 3 || groups[0][0] == '0' {
		return "", false
	}
	separatorCount := 0
	var separator rune
	for _, r := range value {
		if r < '0' || r > '9' {
			if separator != 0 && separator != r {
				return "", false
			}
			separator = r
			separatorCount++
		}
	}
	if separatorCount != len(groups)-1 {
		return "", false
	}
	for index, group := range groups {
		if !invoiceDigits(group) || index > 0 && len(group) != 3 {
			return "", false
		}
	}
	return strings.Join(groups, ""), true
}

func invoiceDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func invoiceCanonicalDecimal(value string) string {
	sign := ""
	if strings.HasPrefix(value, "-") {
		sign, value = "-", value[1:]
	}
	parts := strings.SplitN(value, ".", 2)
	integer := strings.TrimLeft(parts[0], "0")
	if integer == "" {
		integer = "0"
	}
	fraction := ""
	if len(parts) > 1 {
		fraction = strings.TrimRight(parts[1], "0")
	}
	if fraction != "" {
		return sign + integer + "." + fraction
	}
	return sign + integer
}
