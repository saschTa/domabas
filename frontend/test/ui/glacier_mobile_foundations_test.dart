import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paired normal-scale actions share height when a label wraps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: glacierMobileTheme(GlacierTheme.light()),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: GlacierMobileActionBar(
              children: [
                GlacierButton(label: 'Create account', onPressed: () {}),
                GlacierButton(
                  label: 'Already have an account?',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final buttons = find.byType(OutlinedButton);
    expect(
      tester.getSize(buttons.first).height,
      tester.getSize(buttons.last).height,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('fields and rich choices expose associated accessible labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: glacierMobileTheme(GlacierTheme.light()),
        home: Scaffold(
          body: Column(
            children: [
              const GlacierMobileField(label: 'Email address'),
              GlacierMobileSelectField(
                label: 'Library role',
                value: 'Viewer',
                options: const ['Viewer', 'Admin'],
                onChanged: (_) {},
              ),
              const GlacierMobilePermissionChoice(
                label: 'Read documents',
                detail: 'Included in role',
                selected: true,
                onChanged: null,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(EditableText)).label,
      'Email address',
    );
    expect(
      tester.getSemantics(find.byType(DropdownButtonFormField<String>)).label,
      contains('Library role'),
    );
    expect(
      find.bySemanticsLabel('Read documents. Included in role'),
      findsOneWidget,
    );
    semantics.dispose();
  });
  testWidgets(
    'opened sheet retains local theme and safe context while keyboard updates',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: Builder(
            builder: (context) => Theme(
              data: glacierMobileTheme(
                Theme.of(context),
                platform: TargetPlatform.iOS,
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 44, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
                ),
                child: Builder(
                  builder: (localContext) => Scaffold(
                    body: TextButton(
                      onPressed: () => showGlacierMobileSheet<void>(
                        context: localContext,
                        builder: (_) => GlacierMobileSheet(
                          footer: GlacierButton(
                            label: 'Apply local',
                            onPressed: () {},
                          ),
                          child: const TextField(),
                        ),
                      ),
                      child: const Text('Open local sheet'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open local sheet'));
      await tester.pumpAndSettle();
      final sheetContext = tester.element(find.byType(GlacierMobileSheet));
      expect(Theme.of(sheetContext).platform, TargetPlatform.iOS);
      expect(MediaQuery.of(sheetContext).padding.top, 44);
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, 'Apply local'))
            .height,
        greaterThanOrEqualTo(48),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(
        MediaQuery.of(tester.element(find.byType(GlacierMobileSheet)))
            .viewInsets
            .bottom,
        280,
      );
      expect(tester.getRect(find.text('Apply local')).bottom, lessThan(564));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mobile button theme overrides desktop density', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: glacierMobileTheme(GlacierTheme.light()),
        home: Scaffold(
          body: GlacierButton(label: 'Apply search', onPressed: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(48),
    );
    final theme = Theme.of(tester.element(find.byType(OutlinedButton)));
    expect(
      theme.outlinedButtonTheme.style!.textStyle!.resolve({})!.fontSize,
      14,
    );
  });
  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        testWidgets(
          'mobile shell $size scale$scale $platform keeps content and navigation usable',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final safe = platform == TargetPlatform.iOS
                ? const EdgeInsets.only(top: 44, bottom: 34)
                : const EdgeInsets.only(top: 24, bottom: 24);
            var scans = 0;
            String selected = 'documents';
            await tester.pumpWidget(
              MaterialApp(
                theme: glacierMobileTheme(
                  GlacierTheme.light(),
                  platform: platform,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: size,
                    padding: safe,
                    viewPadding: safe,
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: GlacierMobileShell(
                  title: 'Documents',
                  subtitle: 'Personal library',
                  selectedId: selected,
                  onSelected: (id) => selected = id,
                  destinations: [
                    const GlacierMobileDestination(
                      id: 'documents',
                      label: 'Documents',
                      icon: Icons.description_outlined,
                    ),
                    const GlacierMobileDestination(
                      id: 'invoices',
                      label: 'Invoices',
                      icon: Icons.receipt_outlined,
                    ),
                    GlacierMobileDestination(
                      id: 'capture',
                      label: 'Scan',
                      icon: Icons.document_scanner_outlined,
                      onAction: () => scans++,
                    ),
                    const GlacierMobileDestination(
                      id: 'chat',
                      label: 'Chat',
                      icon: Icons.chat_bubble_outline,
                    ),
                    const GlacierMobileDestination(
                      id: 'more',
                      label: 'More',
                      icon: Icons.more_horiz,
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlacierMobileSearchEntry(onPressed: () {}),
                      for (var i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: GlacierMobileRecordRow(
                            title: 'Retained document $i',
                            detail: 'Personal library · 12 November',
                            icon: Icons.description_outlined,
                            onTap: () {},
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (scale == 1 && size.width == 320) {
              final label = find.descendant(
                of: find.byType(GlacierMobileNavigation),
                matching: find.text('Documents'),
              );
              expect(tester.getSize(label).height, lessThan(20));
            }
            final scan = find.byKey(
              const ValueKey('mobile-destination-capture'),
            );
            await tester.ensureVisible(scan);
            await tester.tap(scan);
            expect(scans, 1);
            expect(selected, 'documents');
            expect(tester.getSize(scan).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('input-first sheet keeps footer above keyboard at 200 percent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: glacierMobileTheme(
          GlacierTheme.dark(),
          platform: TargetPlatform.iOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(320, 740),
            padding: const EdgeInsets.only(top: 44),
            viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
            viewInsets: const EdgeInsets.only(bottom: 280),
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: GlacierMobileSheet(
          header: const TextField(
            decoration: InputDecoration(hintText: 'Find a document'),
          ),
          footer: GlacierMobileActionBar(
            hint: 'Enter applies · Esc clears, then closes',
            children: [
              GlacierButton(label: 'Cancel', onPressed: () {}),
              GlacierButton(
                label: 'Apply search',
                onPressed: () {},
                kind: GlacierButtonKind.primary,
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < 6; i++)
                GlacierMobileField(
                  label: 'Filter $i',
                  initialValue: 'Personal',
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Apply search')).bottom, lessThan(460));
    final surface = tester.widget<GlacierMobileSurface>(
      find.byType(GlacierMobileSurface),
    );
    expect(surface.borderRadius?.bottomLeft, Radius.zero);
    expect(surface.padding.resolve(TextDirection.ltr).bottom, 52);
    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    final apply = tester.getRect(
      find.widgetWithText(FilledButton, 'Apply search'),
    );
    expect(apply.top, greaterThanOrEqualTo(cancel.bottom));
    expect(apply.width, cancel.width);
  });
}
