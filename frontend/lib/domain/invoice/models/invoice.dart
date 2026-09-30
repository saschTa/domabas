final class Invoice {
  Invoice({
    required this.id,
    required this.documentId,
    required this.documentTitle,
    required this.source,
    required this.format,
    this.number = '',
    this.typeCode = '',
    this.issueDate = '',
    this.dueDate = '',
    this.currency = '',
    this.taxCurrency = '',
    this.totalNet = '',
    this.totalTax = '',
    this.totalGross = '',
    this.amountDue = '',
    this.paidAmount = '',
    this.roundingAmount = '',
    this.taxAccountingAmount = '',
    this.profile = '',
    this.extractionModel = '',
    required this.createdAt,
    this.seller = const InvoiceParty(),
    this.buyer = const InvoiceParty(),
    Iterable<InvoiceLine> lines = const [],
    Iterable<InvoiceTax> taxes = const [],
    Iterable<InvoiceAllowance> allowances = const [],
    Iterable<InvoiceReference> references = const [],
    this.payment = const InvoicePayment(),
    Iterable<String> notes = const [],
  }) : lines = List.unmodifiable(lines),
       taxes = List.unmodifiable(taxes),
       allowances = List.unmodifiable(allowances),
       references = List.unmodifiable(references),
       notes = List.unmodifiable(notes);

  final String id, documentId, documentTitle, source, format, number, typeCode;
  final String issueDate, dueDate, currency, taxCurrency;
  final String totalNet, totalTax, totalGross, amountDue, paidAmount;
  final String roundingAmount, taxAccountingAmount, profile, extractionModel;
  final DateTime createdAt;
  final InvoiceParty seller, buyer;
  final List<InvoiceLine> lines;
  final List<InvoiceTax> taxes;
  final List<InvoiceAllowance> allowances;
  final List<InvoiceReference> references;
  final InvoicePayment payment;
  final List<String> notes;

  bool get structured => source == 'structured';
}

final class InvoiceParty {
  const InvoiceParty({
    this.name = '',
    this.taxId = '',
    this.registrationId = '',
    this.address = '',
    this.country = '',
    this.email = '',
  });
  final String name, taxId, registrationId, address, country, email;
}

final class InvoiceLine {
  const InvoiceLine({
    this.id = '',
    this.description = '',
    this.quantity = '',
    this.unitCode = '',
    this.unitPrice = '',
    this.netAmount = '',
    this.taxCategory = '',
    this.taxRate = '',
  });
  final String id, description, quantity, unitCode, unitPrice, netAmount;
  final String taxCategory, taxRate;
}

final class InvoiceTax {
  const InvoiceTax({
    this.category = '',
    this.rate = '',
    this.taxableAmount = '',
    this.taxAmount = '',
    this.exemptionReason = '',
  });
  final String category, rate, taxableAmount, taxAmount, exemptionReason;
}

final class InvoiceAllowance {
  const InvoiceAllowance({
    required this.charge,
    this.reason = '',
    this.amount = '',
    this.taxCategory = '',
    this.taxRate = '',
  });
  final bool charge;
  final String reason, amount, taxCategory, taxRate;
}

final class InvoiceReference {
  const InvoiceReference({
    required this.number,
    this.issueDate = '',
    this.invoiceId,
    this.documentId,
  });
  final String number, issueDate;
  final String? invoiceId, documentId;
}

final class InvoicePayment {
  const InvoicePayment({
    this.meansCode = '',
    this.reference = '',
    this.iban = '',
    this.bic = '',
    this.terms = '',
  });
  final String meansCode, reference, iban, bic, terms;
}

final class InvoicePage {
  InvoicePage({required Iterable<Invoice> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<Invoice> items;
  final String? nextCursor;
}

final class InvoiceFailure implements Exception {
  const InvoiceFailure(this.code);
  final String code;
  String get message => switch (code) {
    'unauthorized' => 'Sign in again to view invoices.',
    'forbidden' => 'Your current permissions do not allow viewing invoices.',
    'not_found' => 'This invoice is no longer available.',
    'cancelled' => 'The invoice request was cancelled.',
    _ => 'Invoices could not be loaded. Please try again.',
  };
}
