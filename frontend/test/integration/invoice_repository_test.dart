import 'dart:convert';

import 'package:domabas/data/invoice/datasources/invoice_remote_data_source.dart';
import 'package:domabas/data/invoice/repos/remote_invoice_repository.dart';
import 'package:domabas/domain/invoice/models/invoice.dart';
import 'package:domabas/domain/invoice/models/invoice_search.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id = '10000000-0000-0000-0000-000000000001';
const _documentId = '20000000-0000-0000-0000-000000000001';

Map<String, Object?> _invoice() => {
  'id': _id,
  'documentId': _documentId,
  'createdAt': '2026-09-19T00:00:00Z',
  'documentTitle': 'Invoice PDF',
  'source': 'structured',
  'format': 'cii',
  'number': 'INV-1',
  'typeCode': '384',
  'issueDate': '2026-09-19',
  'dueDate': '',
  'currency': 'BHD',
  'taxCurrency': 'EUR',
  'totalNet': '9007199254740993.001',
  'totalTax': '0.000',
  'totalGross': '9007199254740993.001',
  'amountDue': '9007199254740993.001',
  'paidAmount': '',
  'roundingAmount': '-0.001',
  'taxAccountingAmount': '0.00',
  'profile': 'EN16931',
  'extractionModel': '',
  'seller': {
    'name': 'Supplier',
    'taxId': 'TAX',
    'registrationId': '',
    'address': 'Main Street',
    'country': 'DE',
    'email': '',
  },
  'buyer': {
    'name': 'Buyer',
    'taxId': '',
    'registrationId': '',
    'address': '',
    'country': '',
    'email': '',
  },
  'payment': {
    'meansCode': '58',
    'reference': 'INV-1',
    'iban': 'DE123',
    'bic': 'BANK',
    'terms': '',
  },
  'lines': [
    {
      'id': '1',
      'description': 'Service',
      'quantity': '1.5',
      'unitCode': 'HUR',
      'unitPrice': '0.001',
      'netAmount': '0.0015',
      'taxCategory': 'Z',
      'taxRate': '0',
    },
  ],
  'taxes': [
    {
      'category': 'Z',
      'rate': '0',
      'taxableAmount': '9007199254740993.001',
      'taxAmount': '0',
      'exemptionReason': '',
    },
  ],
  'allowances': [
    {
      'charge': false,
      'reason': 'Discount',
      'amount': '0.010',
      'taxCategory': 'Z',
      'taxRate': '0',
    },
  ],
  'references': [
    {
      'number': 'INV-0',
      'issueDate': '2026-08-19',
      'invoiceId': '10000000-0000-0000-0000-000000000002',
      'documentId': '20000000-0000-0000-0000-000000000002',
    },
  ],
  'notes': ['Please retain the original.'],
};

void main() {
  late api.ApiClient client;
  tearDown(() => client.client.close());

  RemoteInvoiceRepository repository(
    Future<http.Response> Function(http.Request) respond,
  ) {
    client = api.ApiClient(basePath: 'https://example.test');
    client.client.close();
    client.client = MockClient(respond);
    return RemoteInvoiceRepository(
      InvoiceRemoteDataSource(api.InvoicesApi(client)),
    );
  }

  test(
    'search query is trimmed, encoded with source and omitted when empty',
    () async {
      final requests = <http.Request>[];
      final repo = repository((request) async {
        requests.add(request);
        return http.Response('{"items":[]}', 200);
      });
      await repo.list(query: '  INV/é + 1  ', source: 'structured');
      expect(requests.last.url.queryParameters['q'], 'INV/é + 1');
      expect(requests.last.url.queryParameters['source'], 'structured');
      await repo.list(query: '  ');
      expect(requests.last.url.queryParameters.containsKey('q'), isFalse);
    },
  );

  test(
    'sort and every property range cross the generated boundary exactly',
    () async {
      final requests = <http.Request>[];
      final repo = repository((request) async {
        requests.add(request);
        return http.Response('{"items":[]}', 200);
      });
      await repo.list(
        query: 'paper',
        source: 'structured',
        sort: InvoiceSort.dueAscending,
        filters: const InvoiceFilters(
          number: 'INV/1',
          seller: 'Supplier & Co',
          buyer: 'Buyer',
          currency: 'EUR',
          typeCode: '384',
          format: 'cii',
          paymentMeansCode: '58',
          createdFrom: '2026-01-01',
          createdTo: '2026-12-31',
          issueFrom: '2026-02-01',
          issueTo: '2026-02-28',
          dueFrom: '2026-03-01',
          dueTo: '2026-03-31',
          totalMin: '9007199254740993.001',
          totalMax: '9007199254740993.002',
        ),
      );
      expect(requests.single.url.queryParameters, {
        'limit': '20',
        'q': 'paper',
        'source': 'structured',
        'sort': 'due_asc',
        'number': 'INV/1',
        'seller': 'Supplier & Co',
        'buyer': 'Buyer',
        'currency': 'EUR',
        'typeCode': '384',
        'format': 'cii',
        'paymentMeansCode': '58',
        'createdFrom': '2026-01-01',
        'createdTo': '2026-12-31',
        'issueFrom': '2026-02-01',
        'issueTo': '2026-02-28',
        'dueFrom': '2026-03-01',
        'dueTo': '2026-03-31',
        'totalMin': '9007199254740993.001',
        'totalMax': '9007199254740993.002',
      });
      await repo.list();
      expect(requests.last.url.queryParameters, {'limit': '20'});
    },
  );

  test(
    'filter values preserve Unicode and carry server search and continuations',
    () async {
      final requests = <http.Request>[];
      final longValue = '😀' * 4000;
      final longCursor = 'x' * 22000;
      final repo = repository((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'items': [longValue],
            'nextCursor': longCursor,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final page = await repo.filterValues(
        field: InvoiceFilterField.seller,
        query: '  Straße & Co  ',
        cursor: 'first',
      );
      expect(requests.single.url.path, '/api/v1/invoices/filter-values');
      expect(requests.single.url.queryParameters, {
        'field': 'seller',
        'q': 'Straße & Co',
        'limit': '20',
        'cursor': 'first',
      });
      expect(page.items.single, longValue);
      expect(page.nextCursor, longCursor);
    },
  );

  for (final body in [
    {
      'items': ['Repeated', 'Repeated'],
    },
    {
      'items': [''],
    },
    {
      'items': ['a' * 4001],
    },
    {'items': <String>[], 'nextCursor': 'next'},
    {
      'items': ['Value'],
      'nextCursor': 'same',
    },
    {
      'items': ['Value'],
      'nextCursor': 'a' * 32769,
    },
    {'items': List.generate(21, (index) => '$index')},
  ]) {
    test(
      'invalid filter-value page is rejected: ${body.keys} ${jsonEncode(body).length}',
      () async {
        final repo = repository(
          (_) async => http.Response(jsonEncode(body), 200),
        );
        await expectLater(
          repo.filterValues(field: InvoiceFilterField.seller, cursor: 'same'),
          throwsA(isA<InvoiceFailure>()),
        );
      },
    );
  }

  test(
    'generated transport maps exact amounts, source filter and references',
    () async {
      final requests = <http.Request>[];
      final repo = repository((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'items': [_invoice()],
            'nextCursor': 'older',
          }),
          200,
        );
      });
      final page = await repo.list(cursor: 'current', source: 'structured');
      expect(requests.single.url.path, '/api/v1/invoices');
      expect(requests.single.url.queryParameters, {
        'limit': '20',
        'cursor': 'current',
        'source': 'structured',
      });
      final invoice = page.items.single;
      expect(invoice.totalGross, '9007199254740993.001');
      expect(invoice.currency, 'BHD');
      expect(invoice.roundingAmount, '-0.001');
      expect(invoice.taxCurrency, 'EUR');
      expect(invoice.lines.single.netAmount, '0.0015');
      expect(invoice.allowances.single.charge, isFalse);
      expect(invoice.references.single.number, 'INV-0');
      expect(invoice.payment.reference, 'INV-1');
      expect(page.nextCursor, 'older');
    },
  );

  test(
    'detail uses its own endpoint and rejects mismatched responses',
    () async {
      var mismatch = false;
      final repo = repository((request) async {
        expect(request.url.path, '/api/v1/invoices/$_id');
        final body = _invoice();
        if (mismatch) body['id'] = '10000000-0000-0000-0000-000000000002';
        return http.Response(jsonEncode(body), 200);
      });
      expect((await repo.get(_id)).id, _id);
      mismatch = true;
      await expectLater(repo.get(_id), throwsA(isA<InvoiceFailure>()));
    },
  );

  test('invalid decimal and looping cursor responses are rejected', () async {
    var invalidDecimal = true;
    final repo = repository((_) async {
      final body = _invoice();
      if (invalidDecimal) body['totalGross'] = 'NaN';
      return http.Response(
        jsonEncode({
          'items': [body],
          'nextCursor': 'same',
        }),
        200,
      );
    });
    await expectLater(repo.list(), throwsA(isA<InvoiceFailure>()));
    invalidDecimal = false;
    await expectLater(
      repo.list(cursor: 'same'),
      throwsA(isA<InvoiceFailure>()),
    );
  });

  test('permission failures map to actionable domain errors', () async {
    final repo = repository((_) async => http.Response('{}', 403));
    await expectLater(
      repo.list(),
      throwsA(
        isA<InvoiceFailure>().having(
          (failure) => failure.code,
          'code',
          'forbidden',
        ),
      ),
    );
  });
}
