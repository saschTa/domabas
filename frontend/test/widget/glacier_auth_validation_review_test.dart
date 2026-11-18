import 'package:domabas/presentation/identity/cubits/session_cubit.dart';
import 'package:domabas/presentation/identity/views/auth_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_identity_repository.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('real auth validation fits 320px at 200% dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = SessionCubit(FakeAuthRepository());
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: glacierMobileTheme(
            dark ? GlacierTheme.dark() : GlacierTheme.light(),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AuthScreen(cubit: cubit),
        ),
      );
      final submit = find.byKey(const Key('submitAuth'));
      for (final register in [false, true]) {
        if (register) {
          final switchMode = find.byKey(const Key('switchAuthMode'));
          await tester.ensureVisible(switchMode);
          await tester.tap(switchMode);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        for (final message in [
          'Enter a valid email address.',
          'Use 8–128 characters for your password.',
          if (register) 'Enter an account name of 1–100 characters.',
        ]) {
          final error = find.text(message);
          expect(error, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(error);
          expect(paragraph.didExceedMaxLines, isFalse, reason: message);
          expect(paragraph.size.width, lessThanOrEqualTo(216));
        }
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
