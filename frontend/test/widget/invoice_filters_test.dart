import 'dart:ui' show SemanticsAction, Tristate;

import 'package:domabas/domain/invoice/models/invoice_search.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:domabas/presentation/invoice/views/invoices_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_repository.dart';

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'sort and individual filter removal expose enabled button actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakeInvoiceRepository();
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await cubit.setFilters(const InvoiceFilters(seller: 'Acme Supplies'));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();

      final sortFinder = find.bySemanticsLabel('Sort invoices: Automatic');
      expect(sortFinder, findsOneWidget);
      final sort = tester.getSemantics(sortFinder);
      expect(sort.label, 'Sort invoices: Automatic');
      expect(sort.flagsCollection.isButton, isTrue);
      expect(sort.flagsCollection.isEnabled, Tristate.isTrue);
      expect(sort.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(sort.rect.width, lessThan(400));
      sort.owner!.performAction(sort.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      await _tap(tester, 'invoiceSort-dueAscending');
      expect(cubit.state.criteria.sort, InvoiceSort.dueAscending);

      final removeFinder = find.byTooltip('Remove Supplier: Acme Supplies');
      expect(removeFinder, findsOneWidget);
      final remove = tester.getSemantics(removeFinder);
      expect(
        remove.getSemanticsData().tooltip,
        'Remove Supplier: Acme Supplies',
      );
      expect(remove.flagsCollection.isButton, isTrue);
      expect(remove.flagsCollection.isEnabled, Tristate.isTrue);
      expect(remove.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(remove.rect.width, greaterThanOrEqualTo(48));
      expect(remove.rect.height, greaterThanOrEqualTo(48));
      remove.owner!.performAction(remove.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(cubit.state.criteria.filters.seller, isEmpty);
      expect(cubit.state.criteria.sort, InvoiceSort.dueAscending);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
      semantics.dispose();
    },
  );

  testWidgets(
    'property chooser searches all pages and drafts apply or cancel',
    (tester) async {
      final repository = FakeInvoiceRepository()
        ..values[InvoiceFilterField.seller] = List.generate(
          45,
          (index) => 'Supplier ${index.toString().padLeft(2, '0')}',
        );
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'invoiceFilters');
      await _tap(tester, 'invoiceFilterField-seller');
      expect(find.text('Supplier 00'), findsOneWidget);
      expect(find.text('Supplier 20'), findsNothing);
      await _tap(tester, 'nextInvoiceFilterValues');
      expect(find.text('Supplier 00'), findsNothing);
      expect(find.text('Supplier 20'), findsOneWidget);
      expect(repository.valueRequests.last.$3, '20');
      final search = find.byKey(const Key('invoiceFilterValueSearch'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Supplier 44');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Supplier 44'), findsWidgets);
      expect(repository.valueRequests.last.$2, 'Supplier 44');
      await _tap(tester, 'invoiceFilterValue-0');
      expect(cubit.state.criteria.filters.count, 0);
      await _tap(tester, 'cancelInvoiceFilters');
      expect(cubit.state.criteria.filters.count, 0);
      await _tap(tester, 'invoiceFilters');
      await _tap(tester, 'invoiceFilterField-seller');
      await _tap(tester, 'invoiceFilterValue-0');
      await _tap(tester, 'applyInvoiceFilters');
      expect(cubit.state.criteria.filters.seller, 'Supplier 00');
      expect(find.text('Filters (1)'), findsOneWidget);
      expect(find.text('Supplier: Supplier 00'), findsOneWidget);
      await _tap(tester, 'sortInvoices');
      await _tap(tester, 'invoiceSort-dueAscending');
      expect(repository.sorts.last, InvoiceSort.dueAscending);
      expect(repository.filters.last.seller, 'Supplier 00');
      await _tap(tester, 'clearInvoiceFilters');
      expect(cubit.state.criteria.filters.count, 0);
      expect(cubit.state.criteria.sort, InvoiceSort.dueAscending);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  for (final size in [const Size(320, 320), const Size(320, 640)]) {
    testWidgets(
      'filter form and paginated chooser fit $size with enlarged text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final repository = FakeInvoiceRepository()
          ..values[InvoiceFilterField.seller] = List.generate(
            25,
            (index) => 'Supplier $index ${'Long name ' * 12}',
          );
        final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: InvoicesScreen(cubit: cubit)),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'invoiceFilters');
        expect(tester.takeException(), isNull);
        await _tap(tester, 'invoiceFilterField-seller');
        expect(tester.takeException(), isNull);
        await _tap(tester, 'nextInvoiceFilterValues');
        expect(repository.valueRequests.last.$3, '20');
        expect(tester.takeException(), isNull);
        await _tap(tester, 'invoiceFilterValue-0');
        await _tap(tester, 'applyInvoiceFilters');
        expect(cubit.state.criteria.filters.seller, isNotEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await cubit.close();
      },
    );
  }

  testWidgets('invalid ranges stay in the draft until corrected', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InvoicesScreen(cubit: cubit)),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'invoiceFilters');
    final due = find.byKey(const Key('invoiceDateFrom-2'));
    await tester.ensureVisible(due);
    await tester.enterText(due, '2026-02-29');
    await _tap(tester, 'applyInvoiceFilters');
    expect(cubit.state.criteria.filters.count, 0);
    expect(
      find.text('Due date: use a valid date in YYYY-MM-DD format.'),
      findsOneWidget,
    );
    await tester.ensureVisible(due);
    await tester.enterText(due, '2026-02-28');
    await _tap(tester, 'applyInvoiceFilters');
    expect(cubit.state.criteria.filters.dueFrom, '2026-02-28');
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });
}
