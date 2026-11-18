import 'dart:async';

import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/identity/cubits/session_cubit.dart';
import 'package:domabas/presentation/identity/views/auth_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_identity_repository.dart';

void main() {
  testWidgets(
    'compact Glacier auth keeps validation, autofill and busy submission',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final response = Completer<AuthSession>();
      var requests = 0;
      final repository = FakeAuthRepository()
        ..onLogin = () {
          requests++;
          return response.future;
        };
      final cubit = SessionCubit(repository);
      addTearDown(() => unawaited(cubit.close()));
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AuthScreen(cubit: cubit),
        ),
      );
      final submit = find.byKey(const Key('submitAuth'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(requests, 0);
      final email = find.byKey(const Key('authEmail'));
      final password = find.byKey(const Key('authPassword'));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: email, matching: find.byType(EditableText)),
            )
            .autofillHints,
        contains(AutofillHints.username),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: password,
                matching: find.byType(EditableText),
              ),
            )
            .autofillHints,
        contains(AutofillHints.password),
      );
      await tester.enterText(email, 'reader@example.test');
      await tester.enterText(password, 'correct horse battery');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(requests, 1);
      expect(tester.widget<TextFormField>(email).enabled, isFalse);
      expect(tester.widget<GlacierButton>(submit).busy, isTrue);
      expect(
        tester
            .widget<GlacierButton>(find.byKey(const Key('switchAuthMode')))
            .onPressed,
        isNull,
      );
      response.complete(testSession());
      await tester.pumpAndSettle();
      expect(repository.saved, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      unawaited(cubit.close());
      await tester.pump();
    },
  );

  testWidgets(
    'Glacier settings refresh keeps invalid form draft and caller controller',
    (tester) async {
      final draft = TextEditingController(text: 'not yet valid');
      final scroll = ScrollController();
      addTearDown(draft.dispose);
      addTearDown(scroll.dispose);
      var reads = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: Scaffold(
            body: GlacierSettingsPage(
              scrollController: scroll,
              onRefresh: () {
                reads++;
                return pending.future;
              },
              sections: [TextField(controller: draft)],
              actions: [GlacierButton(label: 'Save', onPressed: null)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(reads, 1);
      expect(draft.text, 'not yet valid');
      expect(scroll.hasClients, isTrue);
      pending.complete();
      await tester.pumpAndSettle();
      expect(draft.text, 'not yet valid');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
