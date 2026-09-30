import 'dart:convert';

import 'package:domabas/app/http_client.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/domain/invoice/models/invoice_search.dart';
import 'package:domabas/presentation/invoice/views/invoices_screen.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'invoice_fixture.dart';

Future<void> exerciseInvoiceWorkflow(
  WidgetTester tester, {
  required String sessionToken,
  required Future<void> Function(String) navigate,
}) async {
  const endpoint = String.fromEnvironment('API_BASE_URL');
  final transport = SessionClient(
    createHttpClient(),
    token: sessionToken,
    onUnauthorized: () {},
  );
  final generated = api.ApiClient(basePath: endpoint)..client.close();
  generated.client = transport;
  final documents = api.DocumentsApi(generated);
  final invoices = api.InvoicesApi(generated);
  addTearDown(transport.close);
  expect(
    (await documents.getDocumentProcessingConfiguration())!.llm!.enabled,
    isFalse,
  );
  debugPrint(
    'Invoice E2E: embedded XML without AI, invoice search, sorting, searchable property filters, details and original document',
  );
  final title = 'Structured invoice ${DateTime.now().microsecondsSinceEpoch}';
  final upload =
      http.MultipartRequest(
          'POST',
          Uri.parse('$endpoint/api/v1/documents/upload'),
        )
        ..fields['metadata'] = jsonEncode({'title': title})
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            structuredInvoicePdf(),
            filename: 'structured-invoice.pdf',
          ),
        );
  final response = await http.Response.fromStream(await transport.send(upload));
  expect(response.statusCode, 202, reason: response.body);
  final id =
      (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  try {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final processing = (await documents.getDocumentProcessing(id))!;
      if (processing.state.toString() == 'ready' &&
          processing.ai?.status.toString() == 'succeeded') {
        break;
      }
      expect(
        processing.state.toString(),
        isNot('failed'),
        reason: processing.failureCode,
      );
      expect(
        processing.ai?.status.toString(),
        isNot('failed'),
        reason: processing.ai?.failureCode,
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      (await documents.getDocumentProcessing(id))!.state.toString(),
      'ready',
    );
    expect(
      (await documents.getDocumentProcessing(id))!.ai!.status.toString(),
      'succeeded',
    );
    final page = (await invoices.listInvoices(
      source_: 'structured',
      limit: 20,
    ))!;
    final invoice = page.items.singleWhere(
      (invoice) => invoice.documentId == id,
    );
    expect(invoice.number, 'INV-2026-001');
    expect(invoice.currency, 'EUR');
    expect(invoice.totalGross, '119.00');
    expect(invoice.seller.name, 'Acme Supplies GmbH');

    await navigate('invoicesNavigation');
    await _wait(
      tester,
      () => find.byType(InvoicesScreen).evaluate().isNotEmpty,
      'Invoice destination loaded',
    );
    await tester.tap(find.byKey(const ValueKey('invoiceFilter-structured')));
    final details = find.byKey(ValueKey('invoiceDetails-${invoice.id}'));
    await _wait(
      tester,
      () => details.evaluate().isNotEmpty,
      'Processed invoice is visible',
    );
    final cubit = tester
        .widget<InvoicesScreen>(find.byType(InvoicesScreen))
        .cubit;
    final search = find.byKey(const Key('invoiceSearchTerm'));
    Future<void> searchFor(String query) async {
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(search, query);
      expect(tester.widget<TextField>(search).controller!.text, query);
      expect(cubit.state.rawTerm, query);
      await _wait(
        tester,
        () {
          expect(
            cubit.state.error,
            isNull,
            reason: 'Invoice search failed for "$query"',
          );
          expect(cubit.state.termError, isNull);
          return !cubit.state.loading &&
              !cubit.state.debouncing &&
              cubit.state.matchesSnapshot &&
              cubit.state.snapshot!.query == query;
        },
        'Invoice search committed: $query',
        diagnostics: () =>
            'raw=${cubit.state.rawTerm}; desired=${cubit.state.criteria.query}; '
            'snapshot=${cubit.state.snapshot?.query}; loading=${cubit.state.loading}; '
            'debouncing=${cubit.state.debouncing}; composing=${cubit.state.composing}; '
            'error=${cubit.state.error}; closed=${cubit.isClosed}',
      );
      expect(cubit.state.error, isNull);
    }

    await searchFor('INV-2026-001');
    expect(details, findsOneWidget);
    await tester.enterText(search, 'unrelated pending term');
    expect(cubit.state.items.any((item) => item.id == invoice.id), isTrue);
    await tester.enterText(search, 'Acme Supplies');
    await tester.tap(find.byKey(const Key('applyInvoiceSearch')));
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.query == 'Acme Supplies',
      'Search submission uses latest invoice party term',
    );
    expect(details, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invoiceFilter-ai')));
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.source == 'ai',
      'AI source combines with the invoice search',
    );
    expect(find.text('No matching invoices'), findsOneWidget);
    expect(cubit.state.rawTerm, 'Acme Supplies');
    await tester.tap(find.byKey(const ValueKey('invoiceFilter-structured')));
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.source == 'structured',
      'Structured source restores matching invoice',
    );
    expect(details, findsOneWidget);
    expect(
      (await invoices.listInvoices(q: title, source_: 'structured'))!.items,
      isEmpty,
      reason: 'Original document title is not an invoice property',
    );
    await searchFor(title);
    expect(
      find.text('No matching invoices'),
      findsOneWidget,
      reason: 'Original document title is outside invoice-property search',
    );
    await searchFor('Printer paper');
    expect(details, findsOneWidget, reason: 'Invoice line item is searchable');
    await tester.tap(find.byKey(const Key('clearInvoiceSearch')));
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.query.isEmpty,
      'Clearing search restores source-filtered invoice list',
    );
    expect(cubit.state.source, 'structured');
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    final sort = find.byKey(const Key('sortInvoices'));
    await tester.ensureVisible(sort);
    await tester.tap(sort);
    await tester.pumpAndSettle();
    final dueSort = find.byKey(const Key('invoiceSort-dueAscending'));
    await tester.ensureVisible(dueSort);
    await tester.tap(dueSort);
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.sort == InvoiceSort.dueAscending,
      'Due-date sort commits without clearing source',
    );
    expect(cubit.state.source, 'structured');
    final filters = find.byKey(const Key('invoiceFilters'));
    await tester.ensureVisible(filters);
    await tester.tap(filters);
    await tester.pumpAndSettle();
    final seller = find.byKey(const Key('invoiceFilterField-seller'));
    await tester.ensureVisible(seller);
    await tester.tap(seller);
    await tester.pumpAndSettle();
    final valueSearch = find.byKey(const Key('invoiceFilterValueSearch'));
    await tester.enterText(valueSearch, 'Acme Supplies');
    final sellerValue = find.byKey(const Key('invoiceFilterValue-0'));
    await _wait(
      tester,
      () =>
          sellerValue.evaluate().isNotEmpty &&
          find.text('Acme Supplies GmbH').evaluate().isNotEmpty,
      'Supplier lookup returns server-backed options',
    );
    await tester.ensureVisible(sellerValue);
    await tester.tap(sellerValue);
    await tester.pumpAndSettle();
    expect(
      cubit.state.criteria.filters.count,
      0,
      reason: 'Draft selections do not change results before Apply',
    );
    await tester.tap(find.byKey(const Key('applyInvoiceFilters')));
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.filters.seller == 'Acme Supplies GmbH',
      'Supplier filter commits with explicit sort',
    );
    expect(cubit.state.criteria.sort, InvoiceSort.dueAscending);
    expect(details, findsOneWidget);
    final clearFilters = find.byKey(const Key('clearInvoiceFilters'));
    await tester.ensureVisible(clearFilters);
    await tester.tap(clearFilters);
    await _wait(
      tester,
      () =>
          !cubit.state.loading &&
          cubit.state.matchesSnapshot &&
          cubit.state.snapshot!.filters.count == 0,
      'Clear filters retains sort and source',
    );
    expect(cubit.state.source, 'structured');
    expect(cubit.state.criteria.sort, InvoiceSort.dueAscending);
    await Scrollable.ensureVisible(tester.element(details), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.textContaining('E-invoice · CII.'), findsOneWidget);
    expect(find.text('Invoice INV-2026-001'), findsWidgets);
    expect(find.text('119.00 EUR'), findsWidgets);
    final line = find.text('Printer paper');
    await Scrollable.ensureVisible(tester.element(line), alignment: .5);
    await tester.pumpAndSettle();
    expect(line.hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('openInvoiceDocument')));
    await _wait(
      tester,
      () => find.byKey(const Key('closeDocument')).evaluate().isNotEmpty,
      'Invoice original opens in the document viewer',
    );
    await tester.tap(find.byKey(const Key('closeDocument')));
    await tester.pumpAndSettle();
    expect(find.byType(InvoicesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await navigate('documentsNavigation');
  } finally {
    await documents.deleteDocument(id);
  }
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String reason, {
  String Function()? diagnostics,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: '$reason${diagnostics == null ? '' : '\n${diagnostics()}'}',
  );
}
