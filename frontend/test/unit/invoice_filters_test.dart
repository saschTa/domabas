import 'dart:async';

import 'package:domabas/domain/invoice/models/invoice.dart';
import 'package:domabas/domain/invoice/models/invoice_search.dart';
import 'package:domabas/presentation/invoice/cubits/invoice_filter_values_cubit.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_repository.dart';

void main() {
  test('date and currency-aware total ranges validate without rounding', () {
    expect(const InvoiceFilters(dueFrom: '2026-02-29').validation, isNotNull);
    expect(const InvoiceFilters(dueFrom: '2024-02-29').validation, isNull);
    expect(
      const InvoiceFilters(
        issueFrom: '2026-10-01',
        issueTo: '2026-09-01',
      ).validation,
      isNotNull,
    );
    expect(
      const InvoiceFilters(totalMin: '1').validation,
      contains('currency'),
    );
    expect(
      const InvoiceFilters(
        currency: 'EUR',
        totalMin: '9007199254740993.002',
        totalMax: '9007199254740993.001',
      ).validation,
      contains('minimum'),
    );
    expect(
      const InvoiceFilters(
        currency: 'EUR',
        totalMin: '-0.002',
        totalMax: '-0.001',
      ).validation,
      isNull,
    );
    expect(
      const InvoiceFilters(currency: 'EUR', totalMin: '01.00').validation,
      isNotNull,
    );
    expect(
      const InvoiceFilters(
        currency: 'EUR',
        totalMin: '1.1234567890123',
      ).validation,
      isNotNull,
    );
    expect(
      const InvoiceFilters(
        currency: 'EUR',
        totalMin: '1.123456789012',
        totalMax: '2',
      ).validation,
      isNull,
    );
  });

  testWidgets(
    'sort and filters retain snapshots while requests fail or become stale',
    (tester) async {
      final repository = FakeInvoiceRepository();
      for (var index = 0; index < 45; index++) {
        final invoice = invoiceFixture(index);
        repository.records[invoice.id] = invoice;
      }
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pump();
      await cubit.load(more: true);
      final before = cubit.state;
      final stale = Completer<InvoicePage>();
      final current = Completer<InvoicePage>();
      repository.onList = (_, _) =>
          repository.sorts.last == InvoiceSort.dueAscending
          ? stale.future
          : current.future;
      unawaited(cubit.setSort(InvoiceSort.dueAscending));
      expect(cubit.state.items, before.items);
      expect(cubit.state.cursor, '40');
      expect(cubit.state.canPaginate, isFalse);
      unawaited(cubit.setSort(InvoiceSort.numberDescending));
      stale.complete(InvoicePage(items: [invoiceFixture(100)]));
      await tester.pump();
      expect(cubit.state.items, before.items);
      current.completeError(const InvoiceFailure('unavailable'));
      await tester.pump();
      expect(cubit.state.items, before.items);
      expect(cubit.state.snapshotVersion, before.snapshotVersion);
      repository.onList = null;
      await cubit.setFilters(
        const InvoiceFilters(currency: 'EUR', dueFrom: '2026-01-01'),
      );
      expect(repository.sorts.last, InvoiceSort.numberDescending);
      expect(repository.filters.last.currency, 'EUR');
      expect(cubit.state.snapshotVersion, before.snapshotVersion + 1);
      expect(cubit.state.cursor, '20');
      cubit.editTerm('INV', composing: false);
      cubit.filter('structured');
      await tester.pump();
      expect(repository.filters.last.dueFrom, '2026-01-01');
      expect(repository.sorts.last, InvoiceSort.numberDescending);
      await cubit.clearFilters();
      expect(cubit.state.source, 'structured');
      expect(cubit.state.criteria.query, 'INV');
      expect(cubit.state.criteria.sort, InvoiceSort.numberDescending);
      expect(cubit.state.criteria.filters.count, 0);
      await cubit.close();
    },
  );

  testWidgets(
    'lookup edits cancel and fence stale pages and respect composition',
    (tester) async {
      final old = Completer<InvoiceFilterValuePage>();
      final latest = Completer<InvoiceFilterValuePage>();
      final repository = FakeInvoiceRepository()
        ..onValues = (_, query, _) =>
            query == 'new' ? latest.future : old.future;
      final cubit = InvoiceFilterValuesCubit(
        repository,
        InvoiceFilterField.seller,
      );
      unawaited(cubit.submit());
      var cancelled = false;
      unawaited(repository.cancellations.last!.then((_) => cancelled = true));
      cubit.editQuery('n', composing: true);
      old.complete(InvoiceFilterValuePage(items: ['Old supplier']));
      await tester.pump(const Duration(milliseconds: 500));
      expect(cancelled, isTrue);
      expect(cubit.state.items, isEmpty);
      expect(repository.valueRequests.length, 1);
      cubit.editQuery(' new ', composing: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.valueRequests.last, (
        InvoiceFilterField.seller,
        'new',
        null,
      ));
      latest.complete(InvoiceFilterValuePage(items: ['New supplier']));
      await tester.pump();
      expect(cubit.state.items, ['New supplier']);
      cubit.editQuery(' new ', composing: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(cubit.state.items, ['New supplier']);
      expect(repository.valueRequests.length, 2);
      cubit.editQuery('😀' * 201, composing: false);
      await cubit.submit();
      expect(cubit.state.validation, isNotNull);
      expect(repository.valueRequests.length, 2);
      await cubit.close();
    },
  );

  testWidgets(
    'lookup retains only one page and retries a failed continuation',
    (tester) async {
      final repository = FakeInvoiceRepository()
        ..values[InvoiceFilterField.seller] = List.generate(
          65,
          (index) => 'Supplier ${index.toString().padLeft(2, '0')}',
        );
      final cubit = InvoiceFilterValuesCubit(
        repository,
        InvoiceFilterField.seller,
      );
      await cubit.submit();
      expect(cubit.state.items.length, 20);
      expect(cubit.state.items.first, 'Supplier 00');
      repository.onValues = (_, _, cursor) async {
        expect(cursor, '20');
        throw const InvoiceFailure('unavailable');
      };
      await cubit.next();
      expect(cubit.state.page, 1);
      expect(cubit.state.items.first, 'Supplier 00');
      expect(cubit.state.error, isNotNull);
      repository.onValues = null;
      await cubit.retry();
      expect(repository.valueRequests.last.$3, '20');
      expect(cubit.state.page, 2);
      expect(cubit.state.items.length, 20);
      expect(cubit.state.items.first, 'Supplier 20');
      await cubit.previous();
      expect(cubit.state.items.first, 'Supplier 00');
      await cubit.next();
      await cubit.next();
      await cubit.next();
      expect(cubit.state.items.length, 5);
      expect(cubit.state.nextCursor, isNull);
      await cubit.submit();
      expect(cubit.state.page, 1);
      expect(cubit.state.hasPrevious, isFalse);
      await cubit.close();
    },
  );
}
