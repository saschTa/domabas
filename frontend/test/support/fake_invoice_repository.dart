import 'package:domabas/domain/invoice/interfaces/invoice_repository.dart';
import 'package:domabas/domain/invoice/models/invoice.dart';
import 'package:domabas/domain/invoice/models/invoice_search.dart';

Invoice invoiceFixture(
  int index, {
  String source = 'structured',
  String number = '',
  String totalGross = '119.00',
  String currency = 'EUR',
  String typeCode = '380',
  Iterable<InvoiceReference> references = const [],
  Iterable<InvoiceLine> lines = const [],
}) => Invoice(
  id: '10000000-0000-0000-0000-${index.toString().padLeft(12, '0')}',
  documentId: '20000000-0000-0000-0000-${index.toString().padLeft(12, '0')}',
  documentTitle: 'Original invoice $index',
  source: source,
  format: source == 'structured' ? 'cii' : 'ai',
  number: number.isEmpty ? 'INV-$index' : number,
  typeCode: typeCode,
  issueDate: '2026-09-19',
  dueDate: '2026-10-19',
  currency: currency,
  totalNet: '100.00',
  totalTax: '19.00',
  totalGross: totalGross,
  amountDue: totalGross,
  seller: const InvoiceParty(
    name: 'Example supplier',
    address: 'Main Street 1',
  ),
  buyer: const InvoiceParty(name: 'Example customer'),
  references: references,
  lines: lines,
  payment: const InvoicePayment(reference: 'INV payment'),
  createdAt: DateTime.utc(2026, 9, 19),
);

final class FakeInvoiceRepository implements InvoiceRepository {
  final records = <String, Invoice>{};
  final limits = <int>[];
  final cursors = <String?>[];
  final sources = <String?>[];
  final queries = <String?>[];
  final sorts = <InvoiceSort>[];
  final filters = <InvoiceFilters>[];
  final valueRequests = <(InvoiceFilterField, String, String?)>[];
  final values = <InvoiceFilterField, List<String>>{};
  final cancellations = <Future<void>?>[];
  final requested = <String>[];
  InvoiceFailure? failure;
  Future<InvoicePage> Function(String?, String?)? onList;
  Future<InvoicePage> Function(String?, String?, String?)? onSearch;
  Future<Invoice> Function(String)? onGet;
  Future<InvoiceFilterValuePage> Function(InvoiceFilterField, String, String?)?
  onValues;
  bool cancelled = false;

  @override
  void cancelRequests() => cancelled = true;

  @override
  Future<InvoicePage> list({
    int limit = 20,
    String? cursor,
    String? source,
    String? query,
    InvoiceSort sort = InvoiceSort.automatic,
    InvoiceFilters filters = const InvoiceFilters(),
    Future<void>? cancel,
  }) async {
    limits.add(limit);
    cursors.add(cursor);
    sources.add(source);
    queries.add(query);
    sorts.add(sort);
    this.filters.add(filters);
    cancellations.add(cancel);
    if (failure case final failure?) throw failure;
    if (onSearch case final callback?) return callback(cursor, source, query);
    if (onList case final callback?) return callback(cursor, source);
    final items = records.values
        .where((invoice) => source == null || invoice.source == source)
        .where(
          (invoice) => InvoiceFilterField.values.every(
            (field) =>
                filters.value(field).isEmpty ||
                filters.value(field) == _fieldValue(invoice, field),
          ),
        )
        .where(
          (invoice) =>
              query == null ||
              query.isEmpty ||
              '${invoice.number} ${invoice.seller.name} ${invoice.buyer.name}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    final offset = cursor == null ? 0 : int.parse(cursor);
    return InvoicePage(
      items: items.skip(offset).take(limit),
      nextCursor: offset + limit < items.length ? '${offset + limit}' : null,
    );
  }

  String _fieldValue(Invoice invoice, InvoiceFilterField field) =>
      switch (field) {
        InvoiceFilterField.number => invoice.number,
        InvoiceFilterField.seller => invoice.seller.name,
        InvoiceFilterField.buyer => invoice.buyer.name,
        InvoiceFilterField.currency => invoice.currency,
        InvoiceFilterField.typeCode => invoice.typeCode,
        InvoiceFilterField.format => invoice.format,
        InvoiceFilterField.paymentMeansCode => invoice.payment.meansCode,
      };

  @override
  Future<InvoiceFilterValuePage> filterValues({
    required InvoiceFilterField field,
    String query = '',
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) async {
    valueRequests.add((field, query, cursor));
    cancellations.add(cancel);
    if (onValues case final callback?) return callback(field, query, cursor);
    final all =
        values[field] ??
        records.values
            .map((invoice) => _fieldValue(invoice, field))
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList();
    final matching =
        all
            .where((value) => value.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort();
    final offset = cursor == null ? 0 : int.parse(cursor);
    return InvoiceFilterValuePage(
      items: matching.skip(offset).take(limit),
      nextCursor: offset + limit < matching.length ? '${offset + limit}' : null,
    );
  }

  @override
  Future<Invoice> get(String id, {Future<void>? cancel}) async {
    requested.add(id);
    cancellations.add(cancel);
    if (failure case final failure?) throw failure;
    if (onGet case final callback?) return callback(id);
    final invoice = records[id];
    if (invoice == null) throw const InvoiceFailure('not_found');
    return invoice;
  }
}
