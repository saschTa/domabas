// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class InvoicesApi {
  InvoicesApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  Future<Response> getInvoiceWithHttpInfo(String id, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/invoices/{id}'
      .replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  Future<Invoice?> getInvoice(String id, { Future<void>? abortTrigger, }) async {
    final response = await getInvoiceWithHttpInfo(id, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Invoice',) as Invoice;

    }
    return null;
  }

  Future<Response> listInvoiceFilterValuesWithHttpInfo(String field, { String? q, int? limit, String? cursor, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/invoices/filter-values';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

      queryParams.addAll(_queryParams('', 'field', field));
    if (q != null) {
      queryParams.addAll(_queryParams('', 'q', q));
    }
    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }
    if (cursor != null) {
      queryParams.addAll(_queryParams('', 'cursor', cursor));
    }

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  Future<InvoiceFilterValuePage?> listInvoiceFilterValues(String field, { String? q, int? limit, String? cursor, Future<void>? abortTrigger, }) async {
    final response = await listInvoiceFilterValuesWithHttpInfo(field, q: q, limit: limit, cursor: cursor, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'InvoiceFilterValuePage',) as InvoiceFilterValuePage;

    }
    return null;
  }

  Future<Response> listInvoicesWithHttpInfo({ int? limit, String? cursor, String? source_, String? q, String? sort, String? number, String? seller, String? buyer, String? currency, String? typeCode, String? format, String? paymentMeansCode, String? createdFrom, String? createdTo, String? issueFrom, String? issueTo, String? dueFrom, String? dueTo, String? totalMin, String? totalMax, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/invoices';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }
    if (cursor != null) {
      queryParams.addAll(_queryParams('', 'cursor', cursor));
    }
    if (source_ != null) {
      queryParams.addAll(_queryParams('', 'source', source_));
    }
    if (q != null) {
      queryParams.addAll(_queryParams('', 'q', q));
    }
    if (sort != null) {
      queryParams.addAll(_queryParams('', 'sort', sort));
    }
    if (number != null) {
      queryParams.addAll(_queryParams('', 'number', number));
    }
    if (seller != null) {
      queryParams.addAll(_queryParams('', 'seller', seller));
    }
    if (buyer != null) {
      queryParams.addAll(_queryParams('', 'buyer', buyer));
    }
    if (currency != null) {
      queryParams.addAll(_queryParams('', 'currency', currency));
    }
    if (typeCode != null) {
      queryParams.addAll(_queryParams('', 'typeCode', typeCode));
    }
    if (format != null) {
      queryParams.addAll(_queryParams('', 'format', format));
    }
    if (paymentMeansCode != null) {
      queryParams.addAll(_queryParams('', 'paymentMeansCode', paymentMeansCode));
    }
    if (createdFrom != null) {
      queryParams.addAll(_queryParams('', 'createdFrom', createdFrom));
    }
    if (createdTo != null) {
      queryParams.addAll(_queryParams('', 'createdTo', createdTo));
    }
    if (issueFrom != null) {
      queryParams.addAll(_queryParams('', 'issueFrom', issueFrom));
    }
    if (issueTo != null) {
      queryParams.addAll(_queryParams('', 'issueTo', issueTo));
    }
    if (dueFrom != null) {
      queryParams.addAll(_queryParams('', 'dueFrom', dueFrom));
    }
    if (dueTo != null) {
      queryParams.addAll(_queryParams('', 'dueTo', dueTo));
    }
    if (totalMin != null) {
      queryParams.addAll(_queryParams('', 'totalMin', totalMin));
    }
    if (totalMax != null) {
      queryParams.addAll(_queryParams('', 'totalMax', totalMax));
    }

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  Future<InvoicePage?> listInvoices({ int? limit, String? cursor, String? source_, String? q, String? sort, String? number, String? seller, String? buyer, String? currency, String? typeCode, String? format, String? paymentMeansCode, String? createdFrom, String? createdTo, String? issueFrom, String? issueTo, String? dueFrom, String? dueTo, String? totalMin, String? totalMax, Future<void>? abortTrigger, }) async {
    final response = await listInvoicesWithHttpInfo(limit: limit, cursor: cursor, source_: source_, q: q, sort: sort, number: number, seller: seller, buyer: buyer, currency: currency, typeCode: typeCode, format: format, paymentMeansCode: paymentMeansCode, createdFrom: createdFrom, createdTo: createdTo, issueFrom: issueFrom, issueTo: issueTo, dueFrom: dueFrom, dueTo: dueTo, totalMin: totalMin, totalMax: totalMax, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'InvoicePage',) as InvoicePage;

    }
    return null;
  }
}
