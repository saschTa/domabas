import 'dart:async';

import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/invoice/models/invoice.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:domabas/presentation/invoice/views/invoices_screen.dart';
import 'package:domabas/presentation/invoice/widgets/invoice_labels.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_invoice_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  testWidgets(
    'search retains results during typing, errors and source changes, then clears',
    (tester) async {
      final invoice = invoiceFixture(1);
      final repository = FakeInvoiceRepository()..records[invoice.id] = invoice;
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('invoice-${invoice.id}'));
      final originalRow = tester.element(row);
      final pending = Completer<InvoicePage>();
      repository.onSearch = (_, _, _) => pending.future;
      await tester.enterText(
        find.byKey(const Key('invoiceSearchTerm')),
        'no match',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(row, findsOneWidget);
      expect(tester.element(row), same(originalRow));
      expect(find.textContaining('Showing previous results'), findsOneWidget);
      final filterPositions = [
        for (final source in ['all', 'structured', 'ai'])
          tester.getRect(find.byKey(ValueKey('invoiceFilter-$source'))),
      ];
      await tester.tap(find.byKey(const ValueKey('invoiceFilter-ai')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refreshInvoices')))
            .onPressed,
        isNull,
      );
      expect([
        for (final source in ['all', 'structured', 'ai'])
          tester.getRect(find.byKey(ValueKey('invoiceFilter-$source'))),
      ], filterPositions);
      expect(repository.queries.last, 'no match');
      expect(repository.sources.last, 'ai');
      expect(tester.element(row), same(originalRow));
      pending.completeError(const InvoiceFailure('unavailable'));
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('Showing previous results'), findsOneWidget);
      repository.onSearch = (_, _, _) async => InvoicePage(items: []);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No matching invoices'), findsOneWidget);
      expect(row, findsNothing);
      repository.onSearch = null;
      await tester.tap(find.byKey(const Key('clearInvoiceSearch')));
      await tester.pumpAndSettle();
      expect(cubit.state.rawTerm, isEmpty);
      expect(cubit.state.source, 'ai');
      expect(cubit.state.snapshot!.query, isEmpty);
      expect(find.text('No matching invoices'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('invoiceFilter-all')));
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  testWidgets(
    'search composition, keyboard submission and controller survive compact layout',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = FakeInvoiceRepository();
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('invoiceSearchTerm'));
      await tester.showKeyboard(search);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '供应',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.queries, ['']);
      final controller = tester.widget<TextField>(search).controller;
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      expect(tester.widget<TextField>(search).controller, same(controller));
      expect(controller!.value.composing, const TextRange(start: 0, end: 2));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '供应商',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(repository.queries, ['', '供应商']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.queries, ['', '供应商']);
      await tester.enterText(search, 'x' * 201);
      await tester.pumpAndSettle();
      expect(find.text('Use 200 characters or fewer.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  test('amount labels keep currency precision and missing data explicit', () {
    expect(
      invoiceAmount('9007199254740993.001', 'BHD'),
      '9007199254740993.001 BHD',
    );
    expect(invoiceAmount('100', 'JPY'), '100 JPY');
    expect(invoiceAmount('-0.001', 'EUR'), '-0.001 EUR');
    expect(invoiceAmount('', 'EUR'), 'Not available');
    expect(invoiceAmount('1.00', ''), contains('currency not recorded'));
  });

  testWidgets('invoice source controls retain labeled 48-pixel targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cubit = InvoicesCubit(FakeInvoiceRepository(), allowed: true)
      ..setActive(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InvoicesScreen(cubit: cubit)),
      ),
    );
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('refreshInvoices'));
    expect(tester.widget<IconButton>(refresh).tooltip, 'Refresh invoices');
    expect(tester.getSize(refresh), const Size(48, 48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets(
    'invoice details expose field labels and complete values to accessibility',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final invoice = invoiceFixture(1);
      final repository = FakeInvoiceRepository()..records[invoice.id] = invoice;
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('invoiceDetails-${invoice.id}')));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Total including tax: 119.00 EUR'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Name: Example supplier'), findsOneWidget);
      await tester.tap(find.byKey(const Key('closeInvoiceDetails')));
      await tester.pumpAndSettle();
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 320),
      const Size(320, 640),
      const Size(1280, 900),
    ]) {
      testWidgets(
        'invoice list and details fit $size dark=$dark with enlarged text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final invoice = invoiceFixture(
            1,
            totalGross: '9007199254740993.001',
            currency: 'BHD',
          );
          final repository = FakeInvoiceRepository()
            ..records[invoice.id] = invoice;
          final cubit = InvoicesCubit(repository, allowed: true)
            ..setActive(true);
          String? opened;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: Scaffold(
                body: InvoicesScreen(
                  cubit: cubit,
                  onOpenDocument: (id) async => opened = id,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await revealWorkspaceContent(
            tester,
            find.byKey(ValueKey('invoiceDetails-${invoice.id}')),
            scrollable: find.byKey(
              const PageStorageKey('invoiceWorkspaceScroll'),
            ),
          );
          expect(find.text('E-invoice · CII'), findsOneWidget);
          expect(find.text('9007199254740993.001 BHD'), findsOneWidget);
          await tester.ensureVisible(
            find.byKey(ValueKey('invoiceDetails-${invoice.id}')),
          );
          await revealWorkspaceContent(
            tester,
            find.byKey(ValueKey('invoiceDetails-${invoice.id}')),
            scrollable: find.byKey(
              const PageStorageKey('invoiceWorkspaceScroll'),
            ),
          );
          await tester.tap(
            find.byKey(ValueKey('invoiceDetails-${invoice.id}')),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('legal validity'), findsOneWidget);
          expect(
            find.byKey(const Key('openInvoiceDocument')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('openInvoiceDocument')));
          await tester.pumpAndSettle();
          expect(opened, invoice.documentId);
          await tester.pumpWidget(const SizedBox.shrink());
          await cubit.close();
        },
      );
    }
  }

  testWidgets(
    'AI source filtering and correction reference navigation work without document access',
    (tester) async {
      final previous = invoiceFixture(2, source: 'ai');
      final correction = invoiceFixture(
        1,
        typeCode: '384',
        references: [
          InvoiceReference(number: previous.number, invoiceId: previous.id),
        ],
      );
      final repository = FakeInvoiceRepository()
        ..records[correction.id] = correction
        ..records[previous.id] = previous;
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('invoiceDetails-${correction.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('openInvoiceDocument')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('openInvoiceReference-0')),
      );
      await tester.tap(find.byKey(const ValueKey('openInvoiceReference-0')));
      await tester.pumpAndSettle();
      expect(repository.requested, [correction.id, previous.id]);
      expect(
        find.textContaining('Missing or incorrect values'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('closeInvoiceDetails')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('closeInvoiceDetails')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('invoiceFilter-ai')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('invoice-${correction.id}')), findsNothing);
      expect(find.text('AI extracted · Review details'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  testWidgets(
    'list continuation reaches older invoices with bounded visible rows',
    (tester) async {
      final repository = FakeInvoiceRepository();
      for (var index = 0; index < 23; index++) {
        final invoice = invoiceFixture(index);
        repository.records[invoice.id] = invoice;
      }
      final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: InvoicesScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('nextInvoices')));
      await revealWorkspaceContent(
        tester,
        find.byKey(const Key('nextInvoices')),
        scrollable: find.byKey(const PageStorageKey('invoiceWorkspaceScroll')),
      );
      await tester.tap(find.byKey(const Key('nextInvoices')));
      await tester.pumpAndSettle();
      expect(repository.cursors, [null, '20']);
      expect(find.text('Invoice INV-22'), findsOneWidget);
      expect(find.text('Invoice INV-0'), findsNothing);
      final visiblePage = tester.element(find.byType(AppPagedList));
      final pending = Completer<InvoicePage>();
      repository.onSearch = (_, _, _) => pending.future;
      cubit.filter('ai');
      await tester.pump();
      expect(tester.element(find.byType(AppPagedList)), same(visiblePage));
      expect(find.text('Invoice INV-22'), findsOneWidget);
      expect(find.text('Invoice INV-0'), findsNothing);
      pending.completeError(const InvoiceFailure('unavailable'));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AppPagedList)), same(visiblePage));
      expect(find.text('Invoice INV-22'), findsOneWidget);
      expect(find.text('Invoice INV-0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  testWidgets('automatic refresh keeps the visible invoice history page', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    for (var index = 0; index < 45; index++) {
      final invoice = invoiceFixture(index);
      repository.records[invoice.id] = invoice;
    }
    final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InvoicesScreen(cubit: cubit)),
      ),
    );
    await tester.pumpAndSettle();
    await revealWorkspaceContent(
      tester,
      find.byKey(const Key('nextInvoices')),
      scrollable: find.byKey(const PageStorageKey('invoiceWorkspaceScroll')),
    );
    await tester.tap(find.byKey(const Key('nextInvoices')));
    await tester.pumpAndSettle();
    final visiblePage = tester.element(find.byType(AppPagedList));
    expect(find.text('21–40'), findsOneWidget);
    repository.records[invoiceFixture(25).id] = invoiceFixture(
      25,
      number: 'Corrected',
    );
    repository.records.remove(invoiceFixture(28).id);
    final original = Map<String, Invoice>.of(repository.records);
    final head = invoiceFixture(99);
    repository.records
      ..clear()
      ..[head.id] = head
      ..addAll(original);

    await cubit.load(background: true);
    await tester.pumpAndSettle();

    expect(tester.element(find.byType(AppPagedList)), same(visiblePage));
    expect(find.text('21–40'), findsOneWidget);
    expect(find.text('Invoice Corrected'), findsOneWidget);
    expect(find.text('Invoice INV-28'), findsNothing);
    expect(find.text('Invoice INV-99'), findsNothing);
    expect(find.text('Invoice INV-0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  for (final allowed in [false, true]) {
    testWidgets(
      'workspace invoice destination follows its own claim: $allowed',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dependencies = AuthenticatedDependencies(
          documents: FakeDocumentRepository(),
          invoices: FakeInvoiceRepository(),
          identity: FakeIdentityRepository(),
          processing: FakeProcessingRepository(),
          email: FakeEmailRepository(),
          activity: FakeActivityRepository(),
          realtime: FakeRealtimeRepository(),
          externalLinks: FakeExternalLinkLauncher(),
          close: () {},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AccountWorkspace(
              session: testSession(
                extraPermissions: [
                  if (allowed) IdentityPermission.readInvoices,
                ],
              ),
              dependencies: dependencies,
              onLogout: () {},
              onSessionEnded: (_) {},
              onSwitch: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final destination = find.byKey(const Key('invoicesNavigation'));
        expect(destination, allowed ? findsOneWidget : findsNothing);
        if (allowed) {
          await tester.ensureVisible(destination);
          await tester.tap(destination);
          await tester.pumpAndSettle();
          expect(find.text('No invoices yet'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        dependencies.dispose();
      },
    );
  }
}
