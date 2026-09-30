import 'dart:async';

import 'package:domabas/domain/invoice/models/invoice.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_repository.dart';

void main() {
  testWidgets(
    'typing fences old responses before debounce and submits latest term',
    (tester) async {
      final old = Completer<InvoicePage>();
      final latest = Completer<InvoicePage>();
      final repository = FakeInvoiceRepository()
        ..onSearch = (_, _, query) =>
            query == 'latest' ? latest.future : old.future;
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      cubit.editTerm('la', composing: false);
      old.complete(InvoicePage(items: [invoiceFixture(1)]));
      await tester.pump(const Duration(milliseconds: 200));
      expect(cubit.state.items, isEmpty);
      expect(repository.queries, ['']);
      cubit.editTerm(' latest ', composing: false);
      await tester.pump(const Duration(milliseconds: 299));
      expect(repository.queries, ['']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.queries, ['', 'latest']);
      latest.complete(InvoicePage(items: [invoiceFixture(2)]));
      await tester.pump();
      expect(cubit.state.snapshot!.query, 'latest');
      expect(cubit.state.items.single.id, invoiceFixture(2).id);
      await cubit.close();
    },
  );

  testWidgets(
    'source transitions retain snapshot and cursor through error and retry',
    (tester) async {
      final repository = FakeInvoiceRepository();
      for (var i = 0; i < 45; i++) {
        final invoice = invoiceFixture(i);
        repository.records[invoice.id] = invoice;
      }
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pump();
      await cubit.load(more: true);
      final previous = cubit.state;
      final pending = Completer<InvoicePage>();
      repository.onSearch = (_, _, _) => pending.future;
      cubit.filter('ai');
      expect(cubit.state.items, previous.items);
      expect(cubit.state.cursor, '40');
      expect(cubit.state.snapshotVersion, previous.snapshotVersion);
      expect(cubit.state.loading, isTrue);
      expect(cubit.state.canPaginate, isFalse);
      await cubit.load(more: true);
      expect(repository.cursors, [null, '20', null]);
      pending.completeError(const InvoiceFailure('unavailable'));
      await tester.pump();
      expect(cubit.state.items, previous.items);
      expect(cubit.state.cursor, '40');
      expect(cubit.state.source, 'ai');
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.canPaginate, isFalse);
      repository.onSearch = (_, _, _) async =>
          InvoicePage(items: [invoiceFixture(99, source: 'ai')]);
      await cubit.load();
      expect(cubit.state.items.single.source, 'ai');
      expect(cubit.state.cursor, isNull);
      expect(cubit.state.browsingHistory, isFalse);
      expect(cubit.state.snapshotVersion, previous.snapshotVersion + 1);
      expect(cubit.state.error, isNull);
      await cubit.close();
    },
  );

  testWidgets(
    'source, submit and clear use current query without duplicate debounce',
    (tester) async {
      final repository = FakeInvoiceRepository();
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pump();
      cubit.editTerm('supplier', composing: false);
      cubit.filter('structured');
      await tester.pump();
      expect(repository.queries.last, 'supplier');
      expect(repository.sources.last, 'structured');
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.queries, ['', 'supplier']);
      cubit.editTerm('INV-2', composing: false);
      await cubit.submitSearch();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.queries, ['', 'supplier', 'INV-2']);
      await cubit.clearSearch();
      expect(cubit.state.rawTerm, isEmpty);
      expect(repository.queries.last, '');
      expect(cubit.state.source, 'structured');
      expect(cubit.state.matchesSnapshot, isTrue);
      await cubit.close();
    },
  );

  testWidgets(
    'composition and Unicode length validation block every read path',
    (tester) async {
      final repository = FakeInvoiceRepository();
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pump();
      cubit.editTerm('供应', composing: true);
      cubit.filter('ai');
      await cubit.submitSearch();
      cubit.invalidate();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.queries, ['']);
      cubit.editTerm('供应商', composing: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.queries.last, '供应商');
      expect(repository.sources.last, 'ai');
      cubit.editTerm('😀' * 201, composing: false);
      await cubit.load();
      expect(cubit.state.termError, isNotNull);
      expect(repository.queries, ['', '供应商']);
      cubit.editTerm('😀' * 200, composing: false);
      await cubit.submitSearch();
      expect(cubit.state.termError, isNull);
      expect(repository.queries.last, '😀' * 200);
      await cubit.close();
    },
  );

  testWidgets(
    'searched history survives background refresh and inactive edits resume safely',
    (tester) async {
      final repository = FakeInvoiceRepository();
      for (var i = 0; i < 60; i++) {
        final invoice = invoiceFixture(i);
        repository.records[invoice.id] = invoice;
      }
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pump();
      cubit.editTerm('supplier', composing: false);
      await cubit.submitSearch();
      await cubit.load(more: true);
      final ids = cubit.state.items.map((invoice) => invoice.id).toList();
      await cubit.load(background: true);
      expect(cubit.state.items.map((invoice) => invoice.id), ids);
      expect(cubit.state.cursor, '40');
      expect(repository.queries.last, 'supplier');
      cubit.editTerm('INV-5', composing: false);
      cubit.setActive(false);
      final requests = repository.queries.length;
      await tester.pump(const Duration(seconds: 1));
      expect(repository.queries.length, requests);
      expect(cubit.state.items.map((invoice) => invoice.id), ids);
      cubit.setActive(true);
      await tester.pump();
      expect(cubit.state.snapshot!.query, 'INV-5');
      expect(cubit.state.browsingHistory, isFalse);
      await cubit.close();
    },
  );

  test(
    'background refresh preserves loaded history and continuation on failure',
    () async {
      final repository = FakeInvoiceRepository();
      for (var index = 0; index < 60; index++) {
        final invoice = invoiceFixture(index);
        repository.records[invoice.id] = invoice;
      }
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await pumpEventQueue();
      await cubit.load(more: true);
      final history = cubit.state.items.map((invoice) => invoice.id).toList();
      expect(history, hasLength(40));
      expect(cubit.state.cursor, '40');
      repository.records[history.first] = invoiceFixture(
        0,
        number: 'Corrected',
      );
      await cubit.load(background: true);
      expect(cubit.state.items.map((invoice) => invoice.id), history);
      expect(cubit.state.items.first.number, 'Corrected');
      expect(cubit.state.cursor, '40');
      repository.failure = const InvoiceFailure('unavailable');
      await cubit.load(more: true);
      expect(cubit.state.items.map((invoice) => invoice.id), history);
      expect(cubit.state.cursor, '40');
      expect(cubit.state.error, isNotNull);
    },
  );

  test('changing source cancels and fences older reads', () async {
    final old = Completer<InvoicePage>();
    final repository = FakeInvoiceRepository()
      ..onList = (_, source) async => source == null
          ? old.future
          : InvoicePage(items: [invoiceFixture(2, source: 'ai')]);
    final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    var cancelled = false;
    unawaited(repository.cancellations.first!.then((_) => cancelled = true));
    cubit.filter('ai');
    await pumpEventQueue();
    old.complete(InvoicePage(items: [invoiceFixture(1)]));
    await pumpEventQueue();
    expect(cancelled, isTrue);
    expect(cubit.state.source, 'ai');
    expect(cubit.state.items.single.source, 'ai');
    expect(repository.sources, [null, 'ai']);
  });

  test('inactive and unauthorized workspaces do not read', () async {
    final repository = FakeInvoiceRepository();
    final blocked = InvoicesCubit(repository, allowed: false)..setActive(true);
    final inactive = InvoicesCubit(repository, allowed: true);
    await blocked.load();
    await inactive.load();
    inactive.invalidate();
    expect(repository.cursors, isEmpty);
    await blocked.close();
    await inactive.close();
  });

  test('detail close cancels and ignores late response', () async {
    final pending = Completer<Invoice>();
    final repository = FakeInvoiceRepository()..onGet = (_) => pending.future;
    final cubit = InvoiceDetailCubit(repository, invoiceFixture(1).id);
    final read = cubit.load();
    var cancelled = false;
    unawaited(repository.cancellations.single!.then((_) => cancelled = true));
    await cubit.close();
    pending.complete(invoiceFixture(1));
    await read;
    expect(cancelled, isTrue);
    expect(cubit.state.invoice, isNull);
  });
}
