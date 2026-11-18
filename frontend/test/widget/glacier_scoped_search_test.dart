import 'dart:async';

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
import '../support/workspace_navigation.dart';

void main() {
  for (final invoicesOnly in [false, true]) {
    testWidgets(
      'CmdK respects active invoice scope and covered routes invoiceOnly=$invoicesOnly',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.reset);
        final invoices = FakeInvoiceRepository();
        final dependencies = AuthenticatedDependencies(
          documents: FakeDocumentRepository(),
          invoices: invoices,
          identity: FakeIdentityRepository(),
          processing: FakeProcessingRepository(),
          email: FakeEmailRepository(),
          activity: FakeActivityRepository(),
          realtime: FakeRealtimeRepository(),
          externalLinks: FakeExternalLinkLauncher(),
          close: () {},
        );
        final session = AuthSession(
          token: 'test',
          expiresAt: DateTime.utc(2100),
          identity: Identity(
            userId: 'user',
            email: 'user@example.test',
            accountId: 'library',
            accountName: 'Real library',
            role: AccountRole.viewer,
            mustChangePassword: false,
            permissions: [
              IdentityPermission.readInvoices,
              if (!invoicesOnly) ...[
                IdentityPermission.readDocuments,
                IdentityPermission.searchDocuments,
              ],
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: GlacierTheme.light(),
            home: AccountWorkspace(
              session: session,
              dependencies: dependencies,
              onLogout: () {},
              onSessionEnded: (_) {},
              onSwitch: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await navigateWorkspace(tester, 'invoicesNavigation');
        Future<void> search() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
        }

        expect(find.byKey(const Key('invoiceSearchTerm')), findsNothing);
        await search();
        expect(find.byKey(const Key('invoiceSearchDialog')), findsOneWidget);
        expect(find.byKey(const Key('documentSearchDialog')), findsNothing);
        final reads = invoices.queries.length;
        await tester.enterText(
          find.byKey(const Key('invoiceSearchTerm')),
          'Unapplied invoice draft',
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(invoices.queries.length, reads);
        await search();
        expect(find.byKey(const Key('invoiceSearchDialog')), findsOneWidget);
        Navigator.of(
          tester.element(find.byKey(const Key('invoiceSearchDialog'))),
        ).pop();
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(AccountWorkspace));
        unawaited(
          showGlacierDialog<void>(
            context: context,
            builder: (_) => const GlacierDialog(
              title: 'Protected draft',
              child: Text('Keep editing'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await search();
        expect(find.text('Protected draft'), findsOneWidget);
        expect(find.byKey(const Key('invoiceSearchDialog')), findsNothing);
        expect(find.byKey(const Key('documentSearchDialog')), findsNothing);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        if (!invoicesOnly) {
          await navigateWorkspace(tester, 'documentsNavigation');
          await search();
          expect(find.byKey(const Key('documentSearchDialog')), findsOneWidget);
          expect(find.byKey(const Key('invoiceSearchDialog')), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        dependencies.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
