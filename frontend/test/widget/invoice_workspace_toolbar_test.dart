import 'package:domabas/presentation/invoice/widgets/invoices_workspace_toolbar.dart';
import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_invoice_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/navigation_fonts.dart';
import '../support/workspace_navigation.dart';

void main() {
  setUpAll(loadNavigationFonts);

  for (final dark in [false, true]) {
    testWidgets(
      'invoice workspace preserves composing search across responsive shell dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final invoice = invoiceFixture(1);
        final repository = FakeInvoiceRepository()
          ..records[invoice.id] = invoice;
        final dependencies = AuthenticatedDependencies(
          documents: FakeDocumentRepository(),
          invoices: repository,
          identity: FakeIdentityRepository(),
          processing: FakeProcessingRepository(),
          email: FakeEmailRepository(),
          activity: FakeActivityRepository(),
          realtime: FakeRealtimeRepository(),
          externalLinks: FakeExternalLinkLauncher(),
          close: () {},
        );
        addTearDown(dependencies.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: AccountWorkspace(
              session: testSession(
                extraPermissions: [IdentityPermission.readInvoices],
              ),
              dependencies: dependencies,
              onLogout: () {},
              onSessionEnded: (_) {},
              onSwitch: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await navigateWorkspace(tester, 'invoicesNavigation');
        final search = find.byKey(const Key('invoiceSearchTerm'));
        expect(search, findsNothing);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('invoiceSearchDialog')), findsOneWidget);
        expect(find.byKey(const Key('documentSearchDialog')), findsNothing);
        final controller = tester.widget<TextField>(search).controller!;
        await tester.showKeyboard(search);
        const draft = TextEditingValue(
          text: 'Example sup',
          selection: TextSelection.collapsed(offset: 11),
          composing: TextRange(start: 8, end: 11),
        );
        tester.testTextInput.updateEditingValue(draft);
        await tester.pump(const Duration(milliseconds: 500));
        final reads = repository.queries.length;

        void expectSearchInModal() {
          expect(
            find.descendant(
              of: find.byKey(const Key('invoiceSearchDialog')),
              matching: search,
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(InvoicesWorkspaceToolbar),
              matching: search,
            ),
            findsNothing,
          );
        }

        expectSearchInModal();
        for (final (size, scale) in [
          (const Size(320, 640), 1.0),
          (const Size(320, 320), 2.0),
        ]) {
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(search).controller, same(controller));
          expect(controller.value, draft);
          expect(repository.queries.length, reads);
          expectSearchInModal();
          expect(tester.takeException(), isNull);
        }
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'Example supplier',
            selection: TextSelection.collapsed(offset: 16),
          ),
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(repository.queries.last, 'Example supplier');
        final header = tester.getRect(
          find
              .ancestor(
                of: find.byType(GlacierMobileHeader),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        final navigation = tester.getRect(
          find.byKey(const Key('workspaceBottomNavigation')),
        );
        expect(navigation.top - header.bottom, greaterThanOrEqualTo(48));

        expect(search, findsNothing);
        final source = find.byKey(const Key('invoiceSource'));
        await revealWorkspaceHeader(tester, source);
        expect(source.hitTestable(), findsOneWidget);
        await tester.tap(source);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('invoiceFilter-structured')),
        );
        await tester.tap(
          find.byKey(const ValueKey('invoiceFilter-structured')),
        );
        await tester.pumpAndSettle();
        expect(repository.sources.last, 'structured');

        await revealWorkspaceHeader(
          tester,
          find.byKey(const Key('invoiceFilters')),
        );
        await tester.tap(find.byKey(const Key('invoiceFilters')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('invoiceSearchDialog')), findsOneWidget);
        expect(
          tester.widget<TextField>(search).controller!.text,
          'Example supplier',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
