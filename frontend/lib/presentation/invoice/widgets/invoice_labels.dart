import '../../../domain/invoice/models/invoice_search.dart';

String invoiceType(String code) => switch (code) {
  '381' => 'Credit note',
  '384' => 'Corrected invoice',
  '389' => 'Self-billed invoice',
  '380' || '' => 'Invoice',
  _ => 'Invoice · type $code',
};

String invoiceFormat(String format) => switch (format) {
  'cii' => 'CII',
  'ubl' => 'UBL',
  'zugferd-1' => 'ZUGFeRD 1',
  'ai' => 'AI extracted',
  _ => format,
};

String invoiceAmount(String amount, String currency) {
  if (amount.isEmpty) return 'Not available';
  return currency.isEmpty
      ? '$amount · currency not recorded'
      : '$amount $currency';
}

String invoiceFilterValueLabel(InvoiceFilterField field, String value) =>
    switch (field) {
      InvoiceFilterField.typeCode => '${invoiceType(value)} ($value)',
      InvoiceFilterField.format => invoiceFormat(value),
      InvoiceFilterField.paymentMeansCode => switch (value) {
        '10' => 'Cash (10)',
        '20' => 'Cheque (20)',
        '30' => 'Credit transfer (30)',
        '48' => 'Bank card (48)',
        '49' => 'Direct debit (49)',
        '54' => 'Credit card (54)',
        '55' => 'Debit card (55)',
        '58' => 'SEPA credit transfer (58)',
        '59' => 'SEPA direct debit (59)',
        _ => value,
      },
      _ => value,
    };
