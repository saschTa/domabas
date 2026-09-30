import 'dart:async';

import 'package:domabas/domain/licenses/models/third_party_license.dart';
import 'package:domabas/presentation/licenses/cubits/licenses_cubit.dart';
import 'package:domabas/presentation/licenses/views/licenses_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_third_party_license_repository.dart';
import '../support/workspace_navigation.dart';

ThirdPartyLicense _license(
  String name, {
  String component = 'Frontend',
  String license = 'MIT',
}) => ThirdPartyLicense(
  id: name,
  name: name,
  version: '1.2.3',
  component: component,
  license: license,
  sourceUrl: 'https://example.test/$name',
  notices: [
    ThirdPartyLicenseNotice(
      title: 'LICENSE',
      text: 'Copyright Example contributors.\n\nPermission is hereby granted.',
    ),
    ThirdPartyLicenseNotice(
      title: 'NOTICE',
      text: 'Additional attribution for $name.',
    ),
  ],
);

void main() {
  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<LicensesCubit> mount(
    WidgetTester tester,
    FakeThirdPartyLicenseRepository repository, {
    double scale = 1,
    bool dark = false,
  }) async {
    final cubit = LicensesCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: LicensesScreen(cubit: cubit)),
      ),
    );
    unawaited(cubit.load());
    await tester.pumpAndSettle();
    return cubit;
  }

  for (final (size, scale, dark) in [
    (const Size(1280, 900), 1.0, false),
    (const Size(390, 844), 1.0, true),
    (const Size(320, 480), 2.0, false),
  ]) {
    testWidgets(
      'search and selectable notices fit ${size.width}px at ${scale}x',
      (tester) async {
        viewport(tester, size);
        final repository = FakeThirdPartyLicenseRepository(
          entries: [
            _license('zebra', component: 'Backend', license: 'Apache-2.0'),
            _license('alpha'),
          ],
        );
        await mount(tester, repository, scale: scale, dark: dark);
        expect(find.text('2 components'), findsOneWidget);
        expect(repository.reads, 1);
        await tester.enterText(
          find.byKey(const Key('licenseSearch')),
          'backend apache',
        );
        await tester.pumpAndSettle();
        expect(find.text('1 of 2 components'), findsOneWidget);
        expect(find.text('alpha'), findsNothing);
        final scroll = find
            .descendant(
              of: find.byKey(const Key('licensesScroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        await revealWorkspaceContent(
          tester,
          find.text('Read license'),
          scrollable: scroll,
        );
        await tester.tap(find.text('Read license'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('licenseDetails')), findsOneWidget);
        expect(
          find.widgetWithText(SelectableText, 'https://example.test/zebra'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            SelectableText,
            'Copyright Example contributors.\n\nPermission is hereby granted.',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            SelectableText,
            'Additional attribution for zebra.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('closeLicenseDetails')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('closeLicenseDetails')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('licenseDetails')), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('licenseSearch')),
          -300,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('clearLicenseSearch')));
        await tester.pumpAndSettle();
        expect(find.text('2 components'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('all pages remain reachable and search resets pagination', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final repository = FakeThirdPartyLicenseRepository(
      entries: List.generate(
        45,
        (index) => _license('Package ${index.toString().padLeft(2, '0')}'),
      ).reversed.toList(),
    );
    await mount(tester, repository);
    expect(find.text('Package 00'), findsOneWidget);
    expect(find.text('Package 20'), findsNothing);
    final scroll = find
        .descendant(
          of: find.byKey(const Key('licensesScroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final next = find.byKey(const Key('nextLicensesPage'));
    for (final start in ['Package 20', 'Package 40']) {
      await revealWorkspaceContent(tester, next, scrollable: scroll);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text(start), findsOneWidget);
    }
    await revealWorkspaceContent(tester, next, scrollable: scroll);
    expect(tester.widget<TextButton>(next).onPressed, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('licenseSearch')),
      -300,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('licenseSearch')),
      'package 00',
    );
    await tester.pumpAndSettle();
    expect(find.text('Package 00'), findsOneWidget);
    expect(find.text('1 of 45 components'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('licenseSearch')), 'absent');
    await tester.pumpAndSettle();
    expect(find.text('No matching licenses'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clearLicenseSearch')));
    await tester.pumpAndSettle();
    expect(find.text('Package 00'), findsOneWidget);
    expect(find.text('Package 20'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed bundled read can be retried without exposing its error', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final repository = FakeThirdPartyLicenseRepository()
      ..onLoad = () async => throw StateError('Internal bundle path');
    final cubit = await mount(tester, repository);
    expect(find.textContaining('Internal bundle path'), findsNothing);
    expect(find.byKey(const Key('retryLicenses')), findsOneWidget);
    repository.onLoad = () async => [_license('Recovered package')];
    await tester.tap(find.byKey(const Key('retryLicenses')));
    await tester.pumpAndSettle();
    expect(find.text('Recovered package'), findsOneWidget);
    expect(repository.reads, 2);
    await cubit.load();
    expect(repository.reads, 2);
    await tester.tap(find.text('Read license'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('licenseDetails')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late bundled result after disposal is ignored', (tester) async {
    final pending = Completer<List<ThirdPartyLicense>>();
    final repository = FakeThirdPartyLicenseRepository()
      ..onLoad = () => pending.future;
    final cubit = LicensesCubit(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LicensesScreen(cubit: cubit)),
      ),
    );
    final loading = cubit.load();
    await tester.pump();
    expect(find.text('Loading license notices…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
    pending.complete([_license('Late package')]);
    await loading;
    expect(tester.takeException(), isNull);
  });
}
