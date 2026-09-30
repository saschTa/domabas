import 'dart:async';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../../../domain/invoice/interfaces/invoice_repository.dart';
import '../../../domain/invoice/models/invoice.dart';
import '../../../domain/invoice/models/invoice_search.dart';
import '../datasources/invoice_remote_data_source.dart';

final class RemoteInvoiceRepository implements InvoiceRepository {
  RemoteInvoiceRepository(this._source);
  final InvoiceRemoteDataSource _source;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _decimal = RegExp(r'^-?\d+(\.\d+)?$');

  @override
  void cancelRequests() => _source.cancelRequests();

  @override
  Future<InvoicePage> list({
    int limit = 20,
    String? cursor,
    String? source,
    String? query,
    InvoiceSort sort = InvoiceSort.automatic,
    InvoiceFilters filters = const InvoiceFilters(),
    Future<void>? cancel,
  }) => _translate(() async {
    final term = query?.trim();
    final page = await _source.list(
      limit,
      cursor,
      source,
      term == null || term.isEmpty ? null : term,
      sort,
      filters,
      cancel,
    );
    if (page.items.length > limit ||
        page.items.map((invoice) => invoice.id).toSet().length !=
            page.items.length ||
        (source != null &&
            page.items.any((invoice) => invoice.source_ != source))) {
      throw const FormatException('Invalid invoice page');
    }
    if (page.nextCursor case final next?) {
      if (next.isEmpty ||
          next.length > 32768 ||
          next == cursor ||
          page.items.isEmpty) {
        throw const FormatException('Invalid invoice continuation');
      }
    }
    return InvoicePage(
      items: page.items.map(_invoiceMapper),
      nextCursor: page.nextCursor,
    );
  });

  @override
  Future<InvoiceFilterValuePage> filterValues({
    required InvoiceFilterField field,
    String query = '',
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) => _translate(() async {
    final page = await _source.filterValues(
      field,
      query.trim(),
      limit,
      cursor,
      cancel,
    );
    if (page.items.length > limit ||
        page.items.toSet().length != page.items.length ||
        page.items.any(
          (item) =>
              item.isEmpty ||
              item.runes.length > 4000 ||
              item.contains('\u0000'),
        )) {
      throw const FormatException('Invalid invoice filter values');
    }
    final next = page.nextCursor;
    if (next != null &&
        (next.isEmpty ||
            next.length > 32768 ||
            next == cursor ||
            page.items.isEmpty)) {
      throw const FormatException('Invalid invoice filter continuation');
    }
    return InvoiceFilterValuePage(items: page.items, nextCursor: next);
  });

  @override
  Future<Invoice> get(String id, {Future<void>? cancel}) =>
      _translate(() async {
        final invoice = await _source.get(id, cancel);
        if (invoice.id != id) throw const FormatException('Mismatched invoice');
        return _invoiceMapper(invoice);
      });

  Invoice _invoiceMapper(api.Invoice value) {
    if (!_uuid.hasMatch(value.id) ||
        !_uuid.hasMatch(value.documentId) ||
        !{'structured', 'ai'}.contains(value.source_)) {
      throw const FormatException('Invalid invoice identity');
    }
    for (final amount in [
      value.totalNet,
      value.totalTax,
      value.totalGross,
      value.amountDue,
      value.paidAmount,
      value.roundingAmount,
      value.taxAccountingAmount,
      for (final line in value.lines) ...[
        line.quantity,
        line.unitPrice,
        line.netAmount,
        line.taxRate,
      ],
      for (final tax in value.taxes) ...[
        tax.rate,
        tax.taxableAmount,
        tax.taxAmount,
      ],
      for (final allowance in value.allowances) ...[
        allowance.amount,
        allowance.taxRate,
      ],
    ]) {
      if (amount.isNotEmpty && !_decimal.hasMatch(amount)) {
        throw const FormatException('Invalid invoice decimal');
      }
    }
    for (final reference in value.references) {
      if ((reference.invoiceId != null &&
              !_uuid.hasMatch(reference.invoiceId!)) ||
          (reference.documentId != null &&
              !_uuid.hasMatch(reference.documentId!))) {
        throw const FormatException('Invalid invoice reference');
      }
    }
    return Invoice(
      id: value.id,
      documentId: value.documentId,
      documentTitle: value.documentTitle,
      source: value.source_,
      format: value.format,
      number: value.number,
      typeCode: value.typeCode,
      issueDate: value.issueDate,
      dueDate: value.dueDate,
      currency: value.currency,
      taxCurrency: value.taxCurrency,
      totalNet: value.totalNet,
      totalTax: value.totalTax,
      totalGross: value.totalGross,
      amountDue: value.amountDue,
      paidAmount: value.paidAmount,
      roundingAmount: value.roundingAmount,
      taxAccountingAmount: value.taxAccountingAmount,
      profile: value.profile,
      extractionModel: value.extractionModel,
      createdAt: value.createdAt,
      seller: _invoicePartyMapper(value.seller),
      buyer: _invoicePartyMapper(value.buyer),
      lines: value.lines.map(
        (line) => InvoiceLine(
          id: line.id,
          description: line.description,
          quantity: line.quantity,
          unitCode: line.unitCode,
          unitPrice: line.unitPrice,
          netAmount: line.netAmount,
          taxCategory: line.taxCategory,
          taxRate: line.taxRate,
        ),
      ),
      taxes: value.taxes.map(
        (tax) => InvoiceTax(
          category: tax.category,
          rate: tax.rate,
          taxableAmount: tax.taxableAmount,
          taxAmount: tax.taxAmount,
          exemptionReason: tax.exemptionReason,
        ),
      ),
      allowances: value.allowances.map(
        (allowance) => InvoiceAllowance(
          charge: allowance.charge,
          reason: allowance.reason,
          amount: allowance.amount,
          taxCategory: allowance.taxCategory,
          taxRate: allowance.taxRate,
        ),
      ),
      references: value.references.map(
        (reference) => InvoiceReference(
          number: reference.number,
          issueDate: reference.issueDate,
          invoiceId: reference.invoiceId,
          documentId: reference.documentId,
        ),
      ),
      payment: InvoicePayment(
        meansCode: value.payment.meansCode,
        reference: value.payment.reference,
        iban: value.payment.iban,
        bic: value.payment.bic,
        terms: value.payment.terms,
      ),
      notes: value.notes,
    );
  }

  InvoiceParty _invoicePartyMapper(api.InvoiceParty party) => InvoiceParty(
    name: party.name,
    taxId: party.taxId,
    registrationId: party.registrationId,
    address: party.address,
    country: party.country,
    email: party.email,
  );

  Future<T> _translate<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on api.ApiException catch (error) {
      throw InvoiceFailure(switch (error.code) {
        401 => 'unauthorized',
        403 => 'forbidden',
        404 => 'not_found',
        499 => 'cancelled',
        _ => 'unavailable',
      });
    } on FormatException {
      throw const InvoiceFailure('invalid_response');
    } on TimeoutException {
      throw const InvoiceFailure('unavailable');
    } on http.ClientException {
      throw const InvoiceFailure('unavailable');
    }
  }
}
