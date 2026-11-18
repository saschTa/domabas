import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/mobile_catalog.dart';
import 'package:domabas_widgetbook/catalog/mobile_workflow_cases.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  double scale = 1,
  bool dark = false,
  TargetPlatform platform = TargetPlatform.iOS,
  Map<String, WidgetBuilder> routes = const {},
}) => MaterialApp(
  theme: dark ? GlacierTheme.dark() : GlacierTheme.light(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: MobileCatalogScope(
        routes: routes,
        child: MobileCatalogEnvironment(
          platform: platform,
          child: MobileCatalogHost(child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('invoice disclosure bounds large groups and keeps continuation', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: GlacierMobileInvoiceSection(
              title: 'Line items',
              initiallyExpanded: true,
              pageSize: 2,
              records: [
                for (var i = 1; i <= 3; i++)
                  GlacierInvoiceDetailRecord(
                    title: 'Line $i',
                    values: {'Amount': '€12.00'},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Line 2'), findsOneWidget);
    expect(find.text('Line 3'), findsNothing);
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Line 3'), findsOneWidget);
    expect(find.text('Line 1'), findsNothing);
  });
  test('workflow cases cover every34 stable named state', () {
    final entries = mobileWorkflowCases();
    final named = entries
        .where((entry) => entry.referenceScreen != null)
        .toList();
    expect(named, hasLength(34));
    expect(entries.map((entry) => entry.id).toSet(), hasLength(entries.length));
    for (final family in mobileWorkflowStates.entries) {
      for (final state in family.value) {
        expect(
          named.any((entry) => entry.id == 'mobile-${family.key}-$state'),
          isTrue,
        );
      }
    }
  });

  for (final entry in mobileWorkflowCases()) {
    for (final variant in [(320.0, 1.0, false), (390.0, 2.0, true)]) {
      testWidgets('${entry.id} fits${variant.$1} scale${variant.$2}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(variant.$1, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          host(
            Builder(builder: entry.builder),
            scale: variant.$2,
            dark: variant.$3,
            platform: variant.$3 ? TargetPlatform.android : TargetPlatform.iOS,
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('composer guards IME and pending sends while keeping draft', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Find my policy');
    addTearDown(controller.dispose);
    var sends = 0, checks = 0;
    Widget composer(GlacierMobileChatSubmitState state) => host(
      Scaffold(
        body: GlacierMobileChatComposer(
          controller: controller,
          state: state,
          onSend: () => sends++,
          onCheck: () => checks++,
        ),
      ),
    );
    await tester.pumpWidget(composer(GlacierMobileChatSubmitState.ready));
    await tester.tap(find.byType(TextField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sends, 1);
    controller.value = const TextEditingValue(
      text: '未完成',
      composing: TextRange(start: 0, end: 3),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sends, 1);
    await tester.pumpWidget(composer(GlacierMobileChatSubmitState.uncertain));
    await tester.tap(find.text('Check'));
    expect(checks, 1);
    expect(sends, 1);
    expect(controller.text, '未完成');
  });

  testWidgets('invoice dates align with the trailing amount', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(const MobileWorkflowExample(screen: 'invoices')),
    );
    for (final pair in [
      ('€1,785.00', 'Due 26 November 2026'),
      ('€142.80', 'Due 23 November 2026'),
    ]) {
      expect(
        tester.getRect(find.text(pair.$2)).right,
        closeTo(tester.getRect(find.text(pair.$1)).right, .1),
      );
    }
  });

  testWidgets('workflow input fields expose accessible names', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const MobileWorkflowExample(screen: 'invoices')),
    );
    expect(
      tester.getSemantics(find.byType(TextField).first).label,
      'Search invoice properties',
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(Scaffold(body: GlacierMobileChatComposer(controller: controller))),
    );
    expect(
      tester.getSemantics(find.byType(TextField)).label,
      contains('Message'),
    );
    semantics.dispose();
  });

  testWidgets('selected invoice keeps its exact source identity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Object? source;
    await tester.pumpWidget(
      host(
        const MobileWorkflowExample(screen: 'invoices'),
        routes: {
          'mobile-reader-ready': (context) {
            source = ModalRoute.of(context)?.settings.arguments;
            return const Scaffold(body: Text('Original fixture'));
          },
        },
      ),
    );
    await tester.tap(find.text('Stadtwerke Berlin'));
    await tester.pumpAndSettle();
    expect(find.text('SW-2026-1182'), findsOneWidget);
    expect(find.text('€142.80'), findsWidgets);
    await tester.tap(find.text('Open original'));
    await tester.pumpAndSettle();
    expect(source, 'energy');
  });

  testWidgets('job status uses its natural trailing width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(const MobileWorkflowExample(screen: 'jobs')));
    expect(
      tester.getRect(find.text('Running').at(1)).right + 8,
      closeTo(
        tester
            .getRect(find.widgetWithText(GlacierButton, 'Details').first)
            .right,
        .1,
      ),
    );
  });

  testWidgets('invoice page failure leaves loaded rows in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(const MobileWorkflowExample(screen: 'invoices')),
    );
    final top = tester.getTopLeft(find.text('Forma Studio')).dy;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      host(
        const MobileWorkflowExample(screen: 'invoices', state: 'page-error'),
      ),
    );
    expect(tester.getTopLeft(find.text('Forma Studio')).dy, closeTo(top, .1));
  });

  testWidgets('reindex scopes keep independent pending requests', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(const MobileWorkflowExample(screen: 'reindex', state: 'uncertain')),
    );
    expect(
      tester
          .widget<GlacierButton>(
            find.widgetWithText(GlacierButton, 'Start reindex'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(GlacierButton, 'All libraries'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GlacierButton>(
            find.widgetWithText(GlacierButton, 'Start reindex'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Start reindex'));
    await tester.tap(find.text('Start reindex'));
    await tester.pumpAndSettle();
    expect(find.text('Finding originals…'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(GlacierButton, 'Personal library'),
    );
    await tester.tap(find.widgetWithText(GlacierButton, 'Personal library'));
    await tester.pumpAndSettle();
    expect(find.text('Request outcome unknown'), findsOneWidget);
  });

  testWidgets('history delete is independent of opening a conversation', (
    tester,
  ) async {
    var opens = 0, deletes = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: GlacierMobileChatHistoryRow(
            conversation: const GlacierConversation(
              id: 'policy',
              title: 'Policy',
              updated: 'Today',
            ),
            onOpen: () => opens++,
            onDelete: () => deletes++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Delete Policy conversation'));
    expect(deletes, 1);
    expect(opens, 0);
    await tester.tap(find.text('Policy'));
    expect(opens, 1);
  });

  testWidgets('unknown evidence does not manufacture completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Scaffold(
          body: GlacierMobilePipelineEvidence(
            stages: [
              GlacierPipelineStage(
                label: 'Original',
                state: GlacierStageState.unknown,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
  });
}
