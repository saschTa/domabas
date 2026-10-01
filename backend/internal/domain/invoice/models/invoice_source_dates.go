package models

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

var invoiceDateToken = regexp.MustCompile(`[0-9]{4}` + invoiceOCRSpace + `*[\p{Pd}−/.]` + invoiceOCRSpace + `*[0-9]{1,2}` + invoiceOCRSpace + `*[\p{Pd}−/.]` + invoiceOCRSpace + `*[0-9]{1,2}|[0-9]{1,2}` + invoiceOCRSpace + `*[\p{Pd}−/.]` + invoiceOCRSpace + `*[0-9]{1,2}` + invoiceOCRSpace + `*[\p{Pd}−/.]` + invoiceOCRSpace + `*[0-9]{2}(?:[0-9]{2})?`)
var invoiceDayMonthDate = regexp.MustCompile(`(?i)([0-9]{1,2})[.\s\v\p{Z}\x{0085}/\p{Pd}−]+([\p{L}]+)\.?[\s\v\p{Z}\x{0085}/\p{Pd}−]+([0-9]{4})`)
var invoiceMonthDayDate = regexp.MustCompile(`(?i)([\p{L}]+)\.?[\s\v\p{Z}\x{0085}/\p{Pd}−]+([0-9]{1,2})(?:st|nd|rd|th)?[,]?[\s\v\p{Z}\x{0085}/\p{Pd}−]+([0-9]{4})`)

func invoiceSourceDates(text string) (map[string]bool, []invoiceSourceSpan) {
	var dates []invoiceSourceDate
	for offset := 0; offset < len(text); {
		span := invoiceDateToken.FindStringIndex(text[offset:])
		if span == nil {
			break
		}
		span[0], span[1] = span[0]+offset, span[1]+offset
		offset = span[0] + 1
		if !invoiceTokenBoundary(text, span[0], span[1]) {
			continue
		}
		raw := strings.Map(func(r rune) rune {
			if unicode.IsSpace(r) {
				return -1
			}
			if unicode.Is(unicode.Pd, r) || r == '−' {
				return '-'
			}
			return r
		}, text[span[0]:span[1]])
		parts := strings.FieldsFunc(raw, func(r rune) bool { return r == '-' || r == '/' || r == '.' })
		separator := raw[len(parts[0])]
		if len(parts) != 3 || strings.Count(raw, string(separator)) != 2 {
			continue
		}
		first, _ := strconv.Atoi(parts[0])
		second, _ := strconv.Atoi(parts[1])
		third, _ := strconv.Atoi(parts[2])
		v := invoiceSourceDate{span: invoiceSourceSpan{start: span[0], end: span[1]}, year: third, day: first, month: second, separator: separator, shortYear: len(parts[2]) == 2}
		if len(parts[0]) == 4 {
			v.year, v.month, v.day, v.fixedOrder, v.shortYear = first, second, third, true, false
		}
		dates = append(dates, v)
		offset = span[1]
	}
	for index, pattern := range []*regexp.Regexp{invoiceDayMonthDate, invoiceMonthDayDate} {
		for _, match := range pattern.FindAllStringSubmatchIndex(text, -1) {
			if !invoiceTokenBoundary(text, match[0], match[1]) {
				continue
			}
			day, month := text[match[2]:match[3]], text[match[4]:match[5]]
			if index == 1 {
				day, month = month, day
			}
			v := invoiceSourceDate{span: invoiceSourceSpan{start: match[0], end: match[1]}, fixedOrder: true, month: invoiceNamedMonth(month)}
			if v.month == 0 {
				continue
			}
			v.day, _ = strconv.Atoi(day)
			v.year, _ = strconv.Atoi(text[match[6]:match[7]])
			dates = append(dates, v)
		}
	}
	fullYears := make(map[int]bool)
	orders := make(map[byte]int)
	var spans []invoiceSourceSpan
	for _, v := range dates {
		spans = append(spans, v.span)
		if v.shortYear {
			continue
		}
		dmy, mdy := v.candidates(v.year)
		if dmy != "" || mdy != "" {
			fullYears[v.year] = true
		}
		if !v.fixedOrder {
			if dmy != "" && mdy == "" {
				orders[v.separator] |= 1
			} else if mdy != "" && dmy == "" {
				orders[v.separator] |= 2
			}
		}
	}
	values := make(map[string]bool)
	for _, v := range dates {
		year := v.year
		if v.shortYear {
			year = 0
			for candidate := range fullYears {
				if candidate%100 == v.year {
					if year != 0 {
						year = 0
						break
					}
					year = candidate
				}
			}
		}
		dmy, mdy := v.candidates(year)
		switch {
		case dmy == mdy || mdy == "":
			if dmy != "" {
				values[dmy] = true
			}
		case dmy == "":
			values[mdy] = true
		case orders[v.separator] == 1 || orders[v.separator] == 0 && v.separator == '.':
			values[dmy] = true
		case orders[v.separator] == 2:
			values[mdy] = true
		}
	}
	return values, spans
}

func (v invoiceSourceDate) candidates(year int) (string, string) {
	if year < 1 {
		return "", ""
	}
	dmy := fmt.Sprintf("%04d-%02d-%02d", year, v.month, v.day)
	mdy := fmt.Sprintf("%04d-%02d-%02d", year, v.day, v.month)
	if v.fixedOrder {
		mdy = dmy
	}
	if !date(dmy) {
		dmy = ""
	}
	if !date(mdy) {
		mdy = ""
	}
	return dmy, mdy
}

func invoiceNamedMonth(value string) int {
	switch strings.ToLower(value) {
	case "jan", "january", "januar":
		return 1
	case "feb", "february", "februar":
		return 2
	case "mar", "march", "mär", "märz", "maerz":
		return 3
	case "apr", "april":
		return 4
	case "may", "mai":
		return 5
	case "jun", "june", "juni":
		return 6
	case "jul", "july", "juli":
		return 7
	case "aug", "august":
		return 8
	case "sep", "sept", "september":
		return 9
	case "oct", "october", "okt", "oktober":
		return 10
	case "nov", "november":
		return 11
	case "dec", "december", "dez", "dezember":
		return 12
	}
	return 0
}
