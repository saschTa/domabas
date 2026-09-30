package datasources

const invoiceSchema = `{"type":"object","additionalProperties":false,"required":["isInvoice","invoice"],"properties":{"isInvoice":{"type":"boolean"},"invoice":{"anyOf":[{"type":"null"},{"type":"object",` + invoiceObjectFields + `}]}},"$defs":` + invoiceInferenceDefinitions + `}`

const invoiceExtractionSchema = `{"type":"object","additionalProperties":false,"required":["invoice"],"properties":{"invoice":{"type":"object",` + invoiceObjectFields + `}},"$defs":` + invoiceInferenceDefinitions + `}`

const invoiceObjectFields = `
"additionalProperties":false,
"required":["number","currency","totalNet","totalTax","totalGross","seller","vatAccounting"],
"properties":{
  "number":{"type":"string","minLength":1,"maxLength":4000},
  "typeCode":{"type":"string"},
  "issueDate":{"$ref":"#/$defs/date"},
  "dueDate":{"$ref":"#/$defs/date"},
  "currency":{"$ref":"#/$defs/currency"},
  "totalNet":{"$ref":"#/$defs/decimal","description":"Printed final total EXCLUDING VAT, after charges and allowances: Net Total, Nettobetrag or Summe netto. Do not copy the gross total."},
  "totalTax":{"$ref":"#/$defs/decimal","description":"Printed final VAT total for the whole invoice: Tax Total, Umsatzsteuer or Mehrwertsteuer. Include ALL VAT rates; never use a row or individual VAT category amount."},
  "totalGross":{"$ref":"#/$defs/decimal","description":"Printed final total INCLUDING VAT: Grand Total, Gesamtbetrag or Bruttobetrag."},
  "amountDue":{"$ref":"#/$defs/decimal"},
  "paidAmount":{"$ref":"#/$defs/decimal"},
  "roundingAmount":{"$ref":"#/$defs/decimal"},
  "seller":{"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":1,"maxLength":4000},` + invoicePartyFields + `},"additionalProperties":false},
  "buyer":{"type":"object","properties":{"name":{"type":"string"},` + invoicePartyFields + `},"additionalProperties":false},
  "lines":{"type":"array","maxItems":200,"items":{"type":"object","properties":{"id":{"type":"string"},"description":{"type":"string"},"quantity":{"$ref":"#/$defs/decimal"},"unitCode":{"type":"string"},"unitPrice":{"$ref":"#/$defs/decimal"},"netAmount":{"$ref":"#/$defs/decimal"},"taxCategory":{"type":"string"},"taxRate":{"$ref":"#/$defs/decimal"}},"additionalProperties":false}},
  "taxes":{"type":"array","maxItems":50,"items":{"type":"object","properties":{"category":{"type":"string"},"rate":{"$ref":"#/$defs/decimal"},"taxableAmount":{"$ref":"#/$defs/decimal"},"taxAmount":{"$ref":"#/$defs/decimal"},"exemptionReason":{"type":"string"}},"additionalProperties":false}},
  "allowances":{"type":"array","maxItems":100,"items":{"type":"object","properties":{"charge":{"type":"boolean"},"reason":{"type":"string"},"amount":{"$ref":"#/$defs/decimal"},"taxCategory":{"type":"string"},"taxRate":{"$ref":"#/$defs/decimal"}},"additionalProperties":false}},
  "references":{"type":"array","maxItems":50,"items":{"type":"object","properties":{"number":{"type":"string","minLength":1,"maxLength":4000},"issueDate":{"$ref":"#/$defs/date"}},"required":["number"],"additionalProperties":false}},
  "payment":{"type":"object","properties":{"meansCode":{"type":"string"},"reference":{"type":"string"},"iban":{"type":"string"},"bic":{"type":"string"},"terms":{"type":"string"}},"additionalProperties":false},
  "notes":{"type":"array","maxItems":50,"items":{"type":"string"}},
  "vatAccounting":{"description":"VAT reported in a different accounting currency; never repeat ordinary invoice VAT here.","anyOf":[{"type":"null","description":"All VAT is in the invoice currency."},{"type":"object","additionalProperties":false,"required":["currency","amount"],"properties":{"currency":{"$ref":"#/$defs/currency"},"amount":{"type":"string","pattern":"^-?(0|[1-9][0-9]{0,23})(\\.[0-9]{1,12})?$"}}}]}
}`

const invoicePartyFields = `"taxId":{"type":"string"},"registrationId":{"type":"string"},"address":{"type":"string"},"country":{"type":"string"},"email":{"type":"string"}`

const invoiceInferenceDefinitions = `{
  "decimal":{"type":"string","pattern":"^(-?(0|[1-9][0-9]{0,23})(\\.[0-9]{1,12})?)?$"},
  "currency":{"type":"string","pattern":"^[A-Z]{3}$"},
  "date":{"type":"string","pattern":"^([0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01]))?$"}
}`
