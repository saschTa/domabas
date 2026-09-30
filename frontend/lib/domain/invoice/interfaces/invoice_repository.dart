import '../models/invoice.dart';
import '../models/invoice_search.dart';

abstract interface class InvoiceRepository {
  Future<InvoicePage> list({
    int limit = 20,
    String? cursor,
    String? source,
    String? query,
    InvoiceSort sort = InvoiceSort.automatic,
    InvoiceFilters filters = const InvoiceFilters(),
    Future<void>? cancel,
  });
  Future<InvoiceFilterValuePage> filterValues({
    required InvoiceFilterField field,
    String query = '',
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  });
  Future<Invoice> get(String id, {Future<void>? cancel});
  void cancelRequests();
}
