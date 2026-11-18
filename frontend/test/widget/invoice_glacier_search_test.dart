import 'dart:async';

import 'package:domabas/domain/invoice/models/invoice_search.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:domabas/presentation/invoice/widgets/invoices_workspace_toolbar.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_repository.dart';

void main() {
  testWidgets('one apply commits invoice query source and exact filter draft', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
    await tester.pump();
    await cubit.applySearch(
      const InvoiceCriteria(
        query: 'old',
        source: 'ai',
        filters: InvoiceFilters(currency: 'EUR', totalMin: '1'),
      ),
    );
    final toolbar = GlobalKey<InvoicesWorkspaceToolbarState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: Scaffold(
          body: InvoicesWorkspaceToolbar(key: toolbar, cubit: cubit),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reads = repository.queries.length;
    unawaited(toolbar.currentState!.openSearch());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invoiceSearchTerm')),
      ' exact invoice ',
    );
    final source = find.widgetWithText(GlacierChoice, 'E-invoices');
    await tester.ensureVisible(source);
    await tester.tap(source);
    final date = find.byKey(const Key('invoiceDateFrom-2'));
    await tester.ensureVisible(date);
    await tester.enterText(date, '2026-02-28');
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.queries.length, reads);
    expect(cubit.state.criteria.query, 'old');
    final apply = find.byKey(const Key('applyInvoiceSearch'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(repository.queries.length, reads + 1);
    expect(repository.queries.last, 'exact invoice');
    expect(repository.sources.last, 'structured');
    expect(repository.filters.last.currency, 'EUR');
    expect(repository.filters.last.totalMin, '1');
    expect(repository.filters.last.dueFrom, '2026-02-28');
    expect(find.byKey(const Key('invoiceSearchDialog')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
    'Escape clears local invoice criteria then closes without applying',
    (tester) async {
      final repository = FakeInvoiceRepository();
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pump();
      await cubit.applySearch(
        const InvoiceCriteria(
          query: 'saved',
          source: 'ai',
          filters: InvoiceFilters(seller: 'Saved supplier'),
        ),
      );
      final toolbar = GlobalKey<InvoicesWorkspaceToolbarState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.dark(),
          home: Scaffold(
            body: InvoicesWorkspaceToolbar(key: toolbar, cubit: cubit),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reads = repository.queries.length;
      unawaited(toolbar.currentState!.openSearch());
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoiceSearchTerm')))
            .controller!
            .text,
        isEmpty,
      );
      expect(cubit.state.criteria.query, 'saved');
      expect(cubit.state.criteria.filters.seller, 'Saved supplier');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invoiceSearchDialog')), findsNothing);
      expect(repository.queries.length, reads);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  testWidgets('replacing invoice owner removes only its stale search route', (
    tester,
  ) async {
    final first = InvoicesCubit(FakeInvoiceRepository(), allowed: true)
      ..setActive(true);
    final next = InvoicesCubit(FakeInvoiceRepository(), allowed: true)
      ..setActive(true);
    var owner = first;
    late StateSetter update;
    final toolbar = GlobalKey<InvoicesWorkspaceToolbarState>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: GlacierTheme.light(),
        home: StatefulBuilder(
          builder: (context, setter) {
            update = setter;
            return Scaffold(
              body: InvoicesWorkspaceToolbar(key: toolbar, cubit: owner),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(toolbar.currentState!.openSearch());
    await tester.pumpAndSettle();
    update(() => owner = next);
    navigator.currentState!.push(
      DialogRoute<void>(
        context: navigator.currentContext!,
        builder: (_) => const Dialog(child: Text('Replacement route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replacement route'), findsOneWidget);
    expect(
      find.byKey(const Key('invoiceSearchDialog'), skipOffstage: false),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await first.close();
    await next.close();
  });
}
