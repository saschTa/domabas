package models

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

var invoiceDateToken = regexp.MustCompile(`[0-9]{4}[-/.][0-9]{1,2}[-/.][0-9]{1,2}|[0-9]{1,2}[-/.][0-9]{1,2}[-/.][0-9]{4}`)

func invoiceSourceDates(text string) map[string]bool {
	values := make(map[string]bool)
	for _, span := range invoiceDateToken.FindAllStringIndex(text, -1) {
		if !invoiceTokenBoundary(text, span[0], span[1]) {
			continue
		}
		raw := text[span[0]:span[1]]
		parts := strings.FieldsFunc(raw, func(r rune) bool { return r == '-' || r == '/' || r == '.' })
		if len(parts) != 3 || strings.Count(raw, string(raw[len(parts[0])])) != 2 {
			continue
		}
		first, _ := strconv.Atoi(parts[0])
		second, _ := strconv.Atoi(parts[1])
		third, _ := strconv.Atoi(parts[2])
		var candidates []string
		if len(parts[0]) == 4 {
			candidates = []string{fmt.Sprintf("%04d-%02d-%02d", first, second, third)}
		} else {
			candidates = []string{fmt.Sprintf("%04d-%02d-%02d", third, second, first), fmt.Sprintf("%04d-%02d-%02d", third, first, second)}
		}
		valid := make(map[string]bool)
		for _, candidate := range candidates {
			if date(candidate) {
				valid[candidate] = true
			}
		}
		if len(valid) == 1 {
			for value := range valid {
				values[value] = true
			}
		}
	}
	return values
}
