import 'dart:async';

import 'package:domabas_api/api.dart' as api;

import '../../../domain/invoice/models/invoice_search.dart';

final class InvoiceRemoteDataSource {
  InvoiceRemoteDataSource(
    this._api, {
    this.timeout = const Duration(seconds: 15),
  });

  final api.InvoicesApi _api;
  final Duration timeout;
  final _requests = <Completer<void>>{};
  bool _cancelled = false;

  void cancelRequests() {
    _cancelled = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<api.InvoicePage> list(
    int limit,
    String? cursor,
    String? source,
    String? query,
    InvoiceSort sort,
    InvoiceFilters filters,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listInvoices(
      limit: limit,
      cursor: cursor,
      source_: source,
      q: query,
      sort: sort.value,
      number: _optional(filters.number),
      seller: _optional(filters.seller),
      buyer: _optional(filters.buyer),
      currency: _optional(filters.currency),
      typeCode: _optional(filters.typeCode),
      format: _optional(filters.format),
      paymentMeansCode: _optional(filters.paymentMeansCode),
      createdFrom: _optional(filters.createdFrom),
      createdTo: _optional(filters.createdTo),
      issueFrom: _optional(filters.issueFrom),
      issueTo: _optional(filters.issueTo),
      dueFrom: _optional(filters.dueFrom),
      dueTo: _optional(filters.dueTo),
      totalMin: _optional(filters.totalMin),
      totalMax: _optional(filters.totalMax),
      abortTrigger: abort,
    ),
    cancel,
  );

  String? _optional(String value) => value.isEmpty ? null : value;

  Future<api.InvoiceFilterValuePage> filterValues(
    InvoiceFilterField field,
    String query,
    int limit,
    String? cursor,
    Future<void>? cancel,
  ) => _request(
    (abort) => _api.listInvoiceFilterValues(
      field.name,
      q: _optional(query),
      limit: limit,
      cursor: cursor,
      abortTrigger: abort,
    ),
    cancel,
  );

  Future<api.Invoice> get(String id, Future<void>? cancel) =>
      _request((abort) => _api.getInvoice(id, abortTrigger: abort), cancel);

  Future<T> _request<T>(
    Future<T?> Function(Future<void>) send,
    Future<void>? cancel,
  ) async {
    if (_cancelled) throw api.ApiException(499, 'Cancelled');
    final abort = Completer<void>();
    _requests.add(abort);
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      stop();
    });
    if (cancel != null) unawaited(cancel.then((_) => stop()));
    try {
      final result = await send(abort.future).timeout(timeout);
      if (timedOut) throw TimeoutException('Invoice request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      if (result == null) {
        throw const FormatException('Missing invoice response');
      }
      return result;
    } on TypeError {
      throw const FormatException('Invalid invoice response');
    } on AssertionError {
      throw const FormatException('Missing invoice response fields');
    } catch (_) {
      if (timedOut) throw TimeoutException('Invoice request timed out');
      if (abort.isCompleted) throw api.ApiException(499, 'Cancelled');
      rethrow;
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
